import Foundation
import ListenBrainzKit

protocol RecordingShareProviding: Sendable {
    func followers(of username: String) async throws -> [SearchUser]
    func recommendToFollowers(username: String, recording: Recording) async throws
    func recommendPersonally(
        username: String,
        recording: Recording,
        recipients: [String],
        blurb: String?
    ) async throws
}

protocol RecordingShareTransport: Sendable {
    func followers(username: String) async throws -> [String]
    func recommendToFollowers(
        username: String,
        recordingMBID: UUID?,
        recordingMSID: UUID?
    ) async throws
    func recommendPersonally(
        username: String,
        recordingMBID: UUID?,
        recordingMSID: UUID?,
        recipients: [String],
        blurb: String?
    ) async throws
}

private struct LiveRecordingShareTransport: RecordingShareTransport {
    let client: LBClient

    func followers(username: String) async throws -> [String] {
        try await client.social.followers(username: username)
    }

    func recommendToFollowers(
        username: String,
        recordingMBID: UUID?,
        recordingMSID: UUID?
    ) async throws {
        _ = try await client.feed.createRecordingRecommendation(
            username: username,
            recordingMBID: recordingMBID,
            recordingMSID: recordingMSID
        )
    }

    func recommendPersonally(
        username: String,
        recordingMBID: UUID?,
        recordingMSID: UUID?,
        recipients: [String],
        blurb: String?
    ) async throws {
        _ = try await client.feed.createPersonalRecordingRecommendation(
            username: username,
            recordingMBID: recordingMBID,
            recordingMSID: recordingMSID,
            users: recipients,
            blurbContent: blurb
        )
    }
}

struct ListenBrainzRecordingShareProvider: RecordingShareProviding {
    private let transport: any RecordingShareTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        transport = LiveRecordingShareTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        transport: some RecordingShareTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func followers(of username: String) async throws -> [SearchUser] {
        try await read(.recordingShareFollowers(readScope, user: username)) {
            try await transport.followers(username: username)
                .map { SearchUser(username: $0) }
                .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        }
    }

    func recommendToFollowers(username: String, recording: Recording) async throws {
        try validate(recording)
        try await performAction {
            try await transport.recommendToFollowers(
                username: username,
                recordingMBID: recording.identity.mbid,
                recordingMSID: recording.identity.msid
            )
        }
    }

    func recommendPersonally(
        username: String,
        recording: Recording,
        recipients: [String],
        blurb: String?
    ) async throws {
        try validate(recording)
        let recipients = uniqueUsernames(recipients)
        guard !recipients.isEmpty else { throw RecordingShareProviderError.noRecipients }
        let note = blurb?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note?.count ?? 0 <= 280 else { throw RecordingShareProviderError.blurbTooLong }
        try await performAction {
            try await transport.recommendPersonally(
                username: username,
                recordingMBID: recording.identity.mbid,
                recordingMSID: recording.identity.msid,
                recipients: recipients,
                blurb: note?.isEmpty == true ? nil : note
            )
        }
    }

    private func validate(_ recording: Recording) throws {
        guard recording.identity.mbid != nil || recording.identity.msid != nil else {
            throw RecordingShareProviderError.missingRecordingIdentifier
        }
    }

    private func uniqueUsernames(_ usernames: [String]) -> [String] {
        var seen: Set<String> = []
        return usernames.compactMap { value in
            let username = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty else { return nil }
            let key = username.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return username
        }
    }

    private func read<Result: Sendable>(
        _ key: RequestGate.ReadKey,
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await gate.read(for: key, operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch LBError.invalidAuth, LBError.noToken, LBError.forbidden {
            throw RecordingShareProviderError.invalidAuthentication
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }

    private func performAction<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await gated(operation)
        } catch LBError.invalidAuth, LBError.noToken {
            throw RecordingShareProviderError.invalidAuthentication
        } catch LBError.forbidden, LBError.badRequest, LBError.invalidParam,
                LBError.notFound, LBError.invalidJSON {
            throw RecordingShareProviderError.actionRejected
        }
    }

    private func gated<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await gate.perform(operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }
}

enum RecordingShareProviderError: LocalizedError {
    case invalidAuthentication
    case missingRecordingIdentifier
    case noRecipients
    case blurbTooLong
    case actionRejected

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            "Your ListenBrainz token no longer authorizes recommendations."
        case .missingRecordingIdentifier:
            "This recording needs a MusicBrainz or MessyBrainz ID before it can be recommended."
        case .noRecipients:
            "Choose at least one follower."
        case .blurbTooLong:
            "A personal recommendation note can be up to 280 characters."
        case .actionRejected:
            "ListenBrainz couldn’t share this recommendation. A selected listener may no longer follow you."
        }
    }
}

#if DEBUG
struct RecordingSharePreviewProvider: RecordingShareProviding {
    func followers(of username: String) async throws -> [SearchUser] {
        try await Task.sleep(for: .milliseconds(120))
        return [
            "ambient_archives",
            "cassetteclub",
            "maya",
            "nocturne",
            "polaroidghost",
            "softstatic",
            "tapeecho",
        ].map { SearchUser(username: $0) }
    }

    func recommendToFollowers(username: String, recording: Recording) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    func recommendPersonally(
        username: String,
        recording: Recording,
        recipients: [String],
        blurb: String?
    ) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }
}
#endif
