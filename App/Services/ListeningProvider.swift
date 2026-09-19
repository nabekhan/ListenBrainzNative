import Foundation

protocol ListeningProvider: Sendable {
    func validateToken() async throws -> String
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen]
    func playingNow(username: String) async throws -> Listen?
    func listenCount(username: String) async throws -> Int
    func topArtists(username: String, count: Int) async throws -> [RankedArtist]
    func topReleases(username: String, count: Int) async throws -> [RankedRelease]
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording]
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity
    func dailyActivity(username: String, period: ListeningActivityPeriod) async throws -> DailyActivity?
    func eraActivity(username: String, period: ListeningActivityPeriod) async throws -> EraActivity?
    func artistEvolutionActivity(username: String, period: ListeningActivityPeriod) async throws -> ArtistEvolutionActivity?
    func genreActivity(username: String, period: ListeningActivityPeriod) async throws -> GenreActivity?
    func artistOrigins(username: String, period: ListeningActivityPeriod) async throws -> ArtistOrigins?
    func artistActivity(username: String, period: ListeningActivityPeriod) async throws -> ArtistActivity?
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease]
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws
    /// Asks ListenBrainz to queue deletion of one submitted listen. The server
    /// processes accepted deletions asynchronously.
    func deleteListen(listenedAt: Date, recordingMSID: UUID) async throws
}

extension ListeningProvider {
    func recentListens(username: String, before: Date?, count: Int) async throws -> [Listen] {
        try await recentListens(username: username, before: before, after: nil, count: count)
    }

    func dailyActivity(username: String, period: ListeningActivityPeriod) async throws -> DailyActivity? {
        nil
    }

    func eraActivity(username: String, period: ListeningActivityPeriod) async throws -> EraActivity? {
        nil
    }

    func artistEvolutionActivity(
        username: String,
        period: ListeningActivityPeriod
    ) async throws -> ArtistEvolutionActivity? {
        nil
    }

    func genreActivity(username: String, period: ListeningActivityPeriod) async throws -> GenreActivity? {
        nil
    }

    func artistOrigins(username: String, period: ListeningActivityPeriod) async throws -> ArtistOrigins? {
        nil
    }

    func artistActivity(username: String, period: ListeningActivityPeriod) async throws -> ArtistActivity? { nil }

    func deleteListen(listenedAt: Date, recordingMSID: UUID) async throws {
        throw ProviderError.deleteListenUnavailable
    }
}

enum ProviderError: LocalizedError {
    case invalidToken
    case feedbackNeedsIdentifier
    case deleteListenRejected
    case deleteListenUnavailable
    case deleteListenOutcomeUnknown
    case missingUsername
    case rateLimited(retryAfterSeconds: Int)

    var errorDescription: String? {
        switch self {
        case .invalidToken: "ListenBrainz couldn’t verify this token. Check the token and try again."
        case .feedbackNeedsIdentifier: "ListenBrainz cannot rate this unmapped recording yet."
        case .deleteListenRejected: "ListenBrainz couldn’t schedule this deletion. Refresh your history and try again."
        case .deleteListenUnavailable: "Deletion isn’t available in this build."
        case .deleteListenOutcomeUnknown:
            "We couldn’t confirm the deletion. Wait until shortly after the next hour, then refresh before trying again."
        case .missingUsername: "Enter a ListenBrainz username."
        case let .rateLimited(seconds): "ListenBrainz is busy. Try again in about \(seconds) seconds."
        }
    }
}
