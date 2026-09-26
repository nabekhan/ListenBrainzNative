import Foundation

protocol ListeningProvider: Sendable {
    func validateToken() async throws -> String
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen]
    func playingNow(username: String) async throws -> Listen?
    func listenCount(username: String) async throws -> Int
    func topArtists(username: String, count: Int) async throws -> [RankedArtist]
    func topReleases(username: String, count: Int) async throws -> [RankedRelease]
    func topReleaseGroups(username: String, count: Int) async throws -> [RankedReleaseGroup]
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording]
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity
    func dailyActivity(username: String, period: ListeningActivityPeriod) async throws -> DailyActivity?
    func eraActivity(username: String, period: ListeningActivityPeriod) async throws -> EraActivity?
    func artistEvolutionActivity(username: String, period: ListeningActivityPeriod) async throws -> ArtistEvolutionActivity?
    func genreActivity(username: String, period: ListeningActivityPeriod) async throws -> GenreActivity?
    func artistOrigins(username: String, period: ListeningActivityPeriod) async throws -> ArtistOrigins?
    func artistActivity(username: String, period: ListeningActivityPeriod) async throws -> ArtistActivity?
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease]
    func freshReleases(username: String, query: FreshReleaseQuery) async throws -> [FreshRelease]
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws
    /// Asks ListenBrainz to queue deletion of one submitted listen. The server
    /// processes accepted deletions asynchronously.
    func deleteListen(listenedAt: Date, recordingMSID: UUID) async throws
}

extension ListeningProvider {
    /// Keeps existing fixture and preview providers source-compatible while
    /// production providers adopt the complete server query shape.
    func freshReleases(username: String, query: FreshReleaseQuery) async throws -> [FreshRelease] {
        try await freshReleases(username: username, scope: query.scope)
    }

    func topReleaseGroups(username: String, count: Int) async throws -> [RankedReleaseGroup] { [] }

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
    case manualMappingRejected
    case manualMappingOutcomeUnknown
    case manualMappingCheckUnavailable
    case missingUsername
    case rateLimited(retryAfterSeconds: Int)

    var errorDescription: String? {
        switch self {
        case .invalidToken: String(localized: "ListenBrainz couldn’t verify this token. Check the token and try again.")
        case .feedbackNeedsIdentifier: String(localized: "ListenBrainz cannot rate this unmapped recording yet.")
        case .deleteListenRejected: String(localized: "ListenBrainz couldn’t schedule this deletion. Refresh your history and try again.")
        case .deleteListenUnavailable: String(localized: "Deletion isn’t available in this build.")
        case .deleteListenOutcomeUnknown:
            String(localized: "We couldn’t confirm the deletion. Wait until shortly after the next hour, then refresh before trying again.")
        case .manualMappingRejected:
            String(localized: "ListenBrainz didn’t accept this MusicBrainz match. Check the recording and try again.")
        case .manualMappingOutcomeUnknown:
            String(localized: "We couldn’t confirm whether the match was saved. Refresh later before sending it again.")
        case .manualMappingCheckUnavailable:
            String(localized: "Couldn’t check your saved MusicBrainz match. Try again.")
        case .missingUsername: String(localized: "Enter a ListenBrainz username.")
        case let .rateLimited(seconds): String(localized: "ListenBrainz is busy. Try again in about \(seconds) seconds.")
        }
    }
}
