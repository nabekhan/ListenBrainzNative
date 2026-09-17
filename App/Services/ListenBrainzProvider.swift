import Foundation
import ListenBrainzKit

struct ListenBrainzProvider: ListeningProvider {
    private let client: LBClient
    private let gate: RequestGate

    init(token: String, gate: RequestGate = .shared) {
        self.client = LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        self.gate = gate
    }

    func validateToken() async throws -> String {
        try await perform {
            let info = try await client.core.isTokenValid()
            guard info.valid, let username = info.userName, !username.isEmpty else {
                throw ProviderError.invalidToken
            }
            return username
        }
    }

    func recentListens(username: String, before: Date?, count: Int) async throws -> [Listen] {
        try await perform {
            let result = try await client.core.userListens(
                username: username,
                latest: before,
                count: min(max(count, 1), 100)
            )
            return result.listens.map(Self.map)
        }
    }

    func playingNow(username: String) async throws -> Listen? {
        try await perform {
            guard let value = try await client.core.userPlayingNow(username: username) else {
                return nil
            }
            return Listen(
                recording: Self.map(value.trackMetadata, msid: nil),
                listenedAt: .now,
                insertedAt: nil,
                isPlayingNow: value.playingNow
            )
        }
    }

    func listenCount(username: String) async throws -> Int {
        try await perform { try await client.core.userListensCount(username: username) }
    }

    func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
        try await perform {
            let value = try await client.stats.topArtists(user: username, count: count, range: .allTime)
            return value?.artists.map {
                RankedArtist(mbid: $0.mbid, name: $0.name, listenCount: $0.listenCount)
            } ?? []
        }
    }

    func topReleases(username: String, count: Int) async throws -> [RankedRelease] {
        try await perform {
            let value = try await client.stats.topReleases(user: username, count: count, range: .allTime)
            return value?.releases.map {
                RankedRelease(
                    mbid: $0.releaseMbid,
                    name: $0.releaseName,
                    artistName: $0.artistName,
                    artistMBIDs: $0.artistMbids ?? [],
                    listenCount: $0.listenCount
                )
            } ?? []
        }
    }

    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
        try await perform {
            let value = try await client.stats.topRecordings(user: username, count: count, range: .allTime)
            return value?.recordings.map {
                RankedRecording(
                    mbid: $0.recordingMbid,
                    releaseMBID: $0.releaseMbid,
                    title: $0.trackName,
                    artistName: $0.artistName,
                    artistMBIDs: $0.artistMbids ?? [],
                    releaseTitle: $0.releaseName,
                    listenCount: $0.listenCount
                )
            } ?? []
        }
    }

    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {
        if let mbid = recording.identity.mbid {
            try await perform {
                let score = LBScore(rawValue: feedback.rawValue) ?? .none
                try await client.recordings.submitFeedback(
                    mbid: mbid,
                    msid: recording.identity.msid,
                    score: score
                )
            }
        } else if let msid = recording.identity.msid {
            try await perform {
                let score = LBScore(rawValue: feedback.rawValue) ?? .none
                try await client.recordings.submitFeedback(msid: msid, mbid: nil, score: score)
            }
        } else {
            throw ProviderError.feedbackNeedsIdentifier
        }
    }

    private func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await gate.perform(operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            let delay = max(resetIn, 1)
            throw ProviderError.rateLimited(retryAfterSeconds: delay)
        }
    }

    private static func map(_ listen: LBListen) -> Listen {
        Listen(
            recording: map(listen.trackMetadata, msid: listen.recordingMsid),
            listenedAt: listen.listenedAt,
            insertedAt: listen.insertedAt,
            isPlayingNow: false
        )
    }

    private static func map(_ metadata: LBTrackMetadata, msid: UUID?) -> Recording {
        let mapped = metadata.mbidMapping
        let additional = metadata.additionalInfo
        return Recording(
            identity: .init(mbid: mapped?.recordingMbid ?? additional?.recordingMbid, msid: msid),
            title: mapped?.recordingName ?? metadata.track,
            artistName: metadata.artist,
            artistMBIDs: mapped?.artistMbids ?? additional?.artistMbids ?? [],
            releaseTitle: metadata.release,
            releaseMBID: mapped?.releaseMbid ?? additional?.releaseMbid,
            releaseGroupMBID: mapped?.releaseGroupMbid ?? additional?.releaseGroupMbid,
            artworkReleaseMBID: mapped?.caaReleaseMbid ?? mapped?.releaseMbid ?? additional?.releaseMbid,
            durationMilliseconds: additional?.durationMs ?? additional?.duration.map { $0 * 1_000 },
            source: additional?.musicServiceName
                ?? additional?.musicService
                ?? additional?.submissionClient
                ?? additional?.mediaPlayer
        )
    }
}

actor RequestGate {
    static let shared = RequestGate()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let minimumInterval: Duration
    private var nextRequestAt = ContinuousClock.now
    private var deferredUntil = ContinuousClock.now
    private var requestInFlight = false
    private var waiters: [Waiter] = []

    init(minimumInterval: Duration = .seconds(1)) {
        self.minimumInterval = minimumInterval
    }

    func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result,
        deferralForError: @escaping @Sendable (any Error) -> Duration? = { _ in nil }
    ) async throws -> Result {
        try await acquire()
        var operationStarted = false

        do {
            try await waitUntilAllowed()
            try Task.checkCancellation()
            operationStarted = true
            let result = try await operation()
            finishRequest(operationStarted: operationStarted)
            return result
        } catch {
            if let delay = deferralForError(error) {
                applyDeferral(for: delay)
            }
            finishRequest(operationStarted: operationStarted)
            throw error
        }
    }

    func deferRequests(for delay: Duration) {
        applyDeferral(for: delay)
    }

    #if DEBUG
    func queuedRequestCountForTesting() -> Int { waiters.count }
    #endif

    private func acquire() async throws {
        try Task.checkCancellation()
        guard requestInFlight else {
            requestInFlight = true
            return
        }

        let id = UUID()
        let ownershipGranted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
        guard ownershipGranted else { throw CancellationError() }
    }

    private func waitUntilAllowed() async throws {
        let clock = ContinuousClock()
        while true {
            let now = clock.now
            let allowedTime = max(nextRequestAt, deferredUntil)
            if now < allowedTime {
                try await clock.sleep(until: allowedTime)
            }

            // A response on another task may extend the server delay while this
            // owner is asleep. Re-read shared state before beginning the call.
            if clock.now >= max(nextRequestAt, deferredUntil) {
                return
            }
        }
    }

    private func applyDeferral(for delay: Duration) {
        let deferredTime = ContinuousClock.now.advanced(by: delay)
        deferredUntil = max(deferredUntil, deferredTime)
    }

    private func finishRequest(operationStarted: Bool) {
        if operationStarted {
            nextRequestAt = max(
                nextRequestAt,
                ContinuousClock.now.advanced(by: minimumInterval)
            )
        }

        if waiters.isEmpty {
            requestInFlight = false
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}
