import Foundation
import ListenBrainzKit

protocol PinProviding: Sendable {
    func currentPin(username: String) async throws -> PinnedRecording?
    func pin(_ recording: Recording, blurb: String?) async throws -> PinnedRecording
    func pinHistory(username: String, count: Int, offset: Int) async throws -> (pins: [PinnedRecording], totalCount: Int)
    func unpin() async throws
    func updatePinBlurb(rowID: Int, blurb: String) async throws
    func deletePin(rowID: Int) async throws
}

struct ListenBrainzPinProvider: PinProviding {
    private let client: LBClient
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        client = LBClient(token: token, userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)")
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    func currentPin(username: String) async throws -> PinnedRecording? {
        try await read(.currentPin(readScope, user: username)) {
            try await client.pins.current(user: username).map {
                Self.map($0, isCurrent: true)
            }
        }
    }

    func pin(_ recording: Recording, blurb: String?) async throws -> PinnedRecording {
        guard recording.identity.mbid != nil || recording.identity.msid != nil else { throw PinProviderError.pinNeedsIdentifier }
        guard blurb.map(\.count) ?? 0 <= 280 else { throw PinProviderError.blurbTooLong }
        return try await perform {
            let pin = try await client.pins.create(
                recordingMBID: recording.identity.mbid,
                recordingMSID: recording.identity.msid,
                blurb: blurb.flatMap { $0.isEmpty ? nil : $0 }
            )
            return Self.map(pin, isCurrent: true, fallbackRecording: recording)
        }
    }

    func pinHistory(username: String, count: Int, offset: Int) async throws -> (pins: [PinnedRecording], totalCount: Int) {
        let safeCount = min(max(count, 1), 100)
        let safeOffset = max(offset, 0)
        return try await read(.pinHistory(readScope, user: username, count: safeCount, offset: safeOffset)) {
            let page = try await client.pins.history(user: username, count: safeCount, offset: safeOffset)
            return (page.pinnedRecordings.map { Self.map($0, isCurrent: false) }, page.totalCount)
        }
    }

    func unpin() async throws { try await perform { try await client.pins.unpin() } }
    func updatePinBlurb(rowID: Int, blurb: String) async throws {
        guard blurb.count <= 280 else { throw PinProviderError.blurbTooLong }
        try await perform { try await client.pins.updateBlurb(rowID: rowID, blurb: blurb) }
    }
    func deletePin(rowID: Int) async throws { try await perform { try await client.pins.delete(rowID: rowID) } }

    private func perform<Result: Sendable>(_ operation: @escaping @Sendable () async throws -> Result) async throws -> Result {
        do {
            return try await gate.perform(operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
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
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }

    private static func map(_ pin: LBPinnedRecording, isCurrent: Bool, fallbackRecording: Recording? = nil) -> PinnedRecording {
        let metadata = pin.trackMetadata
        let mapped = metadata?.mbidMapping
        let additional = metadata?.additionalInfo
        let recording = fallbackRecording ?? Recording(
            identity: .init(mbid: pin.recordingMBID ?? mapped?.recordingMbid ?? additional?.recordingMbid, msid: pin.recordingMSID),
            title: mapped?.recordingName ?? metadata?.track ?? "Unknown recording",
            artistName: metadata?.artist ?? "Unknown artist",
            artistMBIDs: mapped?.artistMbids ?? additional?.artistMbids ?? [],
            releaseTitle: metadata?.release,
            releaseMBID: mapped?.releaseMbid ?? additional?.releaseMbid,
            releaseGroupMBID: mapped?.releaseGroupMbid ?? additional?.releaseGroupMbid,
            artworkReleaseMBID: mapped?.caaReleaseMbid ?? mapped?.releaseMbid ?? additional?.releaseMbid,
            durationMilliseconds: additional?.durationMs ?? additional?.duration.map { $0 * 1_000 },
            source: nil
        )
        return PinnedRecording(rowID: pin.rowID, created: pin.created, pinnedUntil: pin.pinnedUntil, blurb: pin.blurbContent, username: pin.userName, recording: recording, isCurrent: isCurrent)
    }
}

enum PinProviderError: LocalizedError {
    case pinNeedsIdentifier
    case blurbTooLong
    var errorDescription: String? {
        switch self {
        case .pinNeedsIdentifier: "ListenBrainz cannot pin this unmapped recording yet."
        case .blurbTooLong: "A pin note can be up to 280 characters."
        }
    }
}
