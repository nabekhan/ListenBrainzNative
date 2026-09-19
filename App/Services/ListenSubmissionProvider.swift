import Foundation
import ListenBrainzKit

protocol ListenSubmitting: Sendable {
    func submit(_ payload: ListenSubmissionPayload) async throws
}

protocol ListenSubmissionTransport: Sendable {
    func submitListen(metadata: LBTrackMetadata, at listenedAt: Date) async throws
    func submitPlayingNow(metadata: LBTrackMetadata) async throws
}

private struct LiveListenSubmissionTransport: ListenSubmissionTransport {
    let client: LBClient

    func submitListen(metadata: LBTrackMetadata, at listenedAt: Date) async throws {
        try await client.core.submitListen(meta: metadata, at: listenedAt)
    }

    func submitPlayingNow(metadata: LBTrackMetadata) async throws {
        try await client.core.submitPlayingNow(meta: metadata)
    }
}

private actor SubmissionAttemptState {
    private(set) var didStartTransport = false
    func markStarted() { didStartTransport = true }
}

struct ListenBrainzSubmissionProvider: ListenSubmitting {
    private let transport: any ListenSubmissionTransport
    private let gate: RequestGate

    init(token: String, gate: RequestGate = .shared) {
        transport = LiveListenSubmissionTransport(
            client: LBClient(
                token: token,
                userAgent: "Brainz/\(Self.appVersion) (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
    }

    init(transport: some ListenSubmissionTransport, gate: RequestGate) {
        self.transport = transport
        self.gate = gate
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    func submit(_ payload: ListenSubmissionPayload) async throws {
        if payload.mode == .listen, payload.listenedAt == nil {
            throw ListenSubmissionError.rejected
        }
        let attempt = SubmissionAttemptState()
        let metadata = LBTrackMetadata(
            artist: payload.artist, track: payload.track, release: payload.release,
            durationMs: payload.durationMilliseconds, artistMbids: payload.artistMBIDs.isEmpty ? nil : payload.artistMBIDs,
            releaseGroupMbid: payload.releaseGroupMBID, releaseMbid: payload.releaseMBID,
            recordingMbid: payload.recordingMBID, submissionClient: "Brainz", submissionClientVersion: payload.appVersion
        )
        do {
            try await gate.perform {
                await attempt.markStarted()
                switch payload.mode {
                case .listen:
                    guard let listenedAt = payload.listenedAt else { throw ListenSubmissionError.rejected }
                    try await transport.submitListen(metadata: metadata, at: listenedAt)
                case .playingNow:
                    try await transport.submitPlayingNow(metadata: metadata)
                }
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) { throw ListenSubmissionError.rateLimited(max(resetIn, 1))
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam { throw ListenSubmissionError.rejected
        } catch LBError.invalidAuth, LBError.noToken { throw ListenSubmissionError.authentication
        } catch LBError.forbidden { throw ListenSubmissionError.forbidden
        } catch is CancellationError {
            if await attempt.didStartTransport { throw ListenSubmissionError.indeterminate }
            throw CancellationError()
        } catch { throw ListenSubmissionError.indeterminate }
    }
}
