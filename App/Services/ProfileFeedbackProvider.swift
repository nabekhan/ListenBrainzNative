import Foundation
import ListenBrainzKit

enum ProfileFeedbackCategory: Int, CaseIterable, Hashable, Sendable {
    case loved = 1
    case hated = -1

    fileprivate var score: LBScore {
        switch self {
        case .loved: .love
        case .hated: .hate
        }
    }
}

enum ProfileFeedbackIdentity: Hashable, Sendable {
    case mbid(UUID)
    case msid(UUID)
}

struct ProfileFeedbackItem: Identifiable, Equatable, Sendable {
    let id: ProfileFeedbackIdentity
    let recording: Recording
    let createdAt: Date?
    let category: ProfileFeedbackCategory
}

struct ProfileFeedbackPage: Equatable, Sendable {
    let username: String
    let category: ProfileFeedbackCategory
    let items: [ProfileFeedbackItem]
    let serverCount: Int
    let offset: Int
    let totalCount: Int
}

protocol ProfileFeedbackProviding: Sendable {
    func page(
        username: String,
        category: ProfileFeedbackCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfileFeedbackPage
}

protocol ProfileFeedbackTransport: Sendable {
    func page(
        username: String,
        score: LBScore,
        offset: Int,
        count: Int
    ) async throws -> LBFeedbackPage
}

private struct LiveProfileFeedbackTransport: ProfileFeedbackTransport {
    let client: LBClient

    func page(
        username: String,
        score: LBScore,
        offset: Int,
        count: Int
    ) async throws -> LBFeedbackPage {
        try await client.recordings.feedbackPage(
            user: username,
            score: score,
            count: count,
            offset: offset,
            metadata: true
        )
    }
}

struct ListenBrainzProfileFeedbackProvider: ProfileFeedbackProviding {
    private let transport: any ProfileFeedbackTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(gate: RequestGate = .shared) {
        transport = LiveProfileFeedbackTransport(
            client: LBClient(
                token: "",
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        readScope = .anonymous
    }

    init(
        transport: some ProfileFeedbackTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func page(
        username: String,
        category: ProfileFeedbackCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfileFeedbackPage {
        let safeOffset = max(offset, 0)
        let safeCount = min(max(count, 1), 1_000)
        do {
            let source: LBFeedbackPage = try await gate.read(
                for: .profileFeedback(
                    readScope,
                    user: username,
                    score: category.rawValue,
                    offset: safeOffset,
                    count: safeCount
                )
            ) {
                try await transport.page(
                    username: username,
                    score: category.score,
                    offset: safeOffset,
                    count: safeCount
                )
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }

            let boundedFeedback = source.feedback.prefix(safeCount)
            return ProfileFeedbackPage(
                username: username,
                category: category,
                items: boundedFeedback.compactMap { Self.map($0, expected: category) },
                serverCount: min(max(source.count, 0), safeCount),
                offset: safeOffset,
                totalCount: max(source.totalCount, 0)
            )
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.notFound {
            throw ProfileFeedbackProviderError.profileUnavailable
        }
    }

    private static func map(
        _ source: LBFeedback,
        expected category: ProfileFeedbackCategory
    ) -> ProfileFeedbackItem? {
        guard source.score.rawValue == category.rawValue else { return nil }
        let identity: ProfileFeedbackIdentity
        if let mbid = source.recordingMbid {
            identity = .mbid(mbid)
        } else if let msid = source.recordingMsid {
            identity = .msid(msid)
        } else {
            return nil
        }

        let recording: Recording
        if let metadata = source.trackMetadata {
            recording = ListenBrainzProvider.map(
                metadata,
                msid: source.recordingMsid,
                mbid: source.recordingMbid
            )
        } else {
            recording = Recording(
                identity: .init(mbid: source.recordingMbid, msid: source.recordingMsid),
                title: String(localized: "Unknown recording"),
                artistName: String(localized: "Unknown artist"),
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            )
        }

        return ProfileFeedbackItem(
            id: identity,
            recording: recording,
            createdAt: source.created,
            category: category
        )
    }
}

enum ProfileFeedbackProviderError: LocalizedError {
    case profileUnavailable

    var errorDescription: String? {
        switch self {
        case .profileUnavailable:
            String(localized: "ListenBrainz couldn’t find this listener.")
        }
    }
}
