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
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease]
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws
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
}

enum ProviderError: LocalizedError {
    case invalidToken
    case feedbackNeedsIdentifier
    case missingUsername
    case rateLimited(retryAfterSeconds: Int)

    var errorDescription: String? {
        switch self {
        case .invalidToken: "That ListenBrainz token is not valid."
        case .feedbackNeedsIdentifier: "ListenBrainz cannot rate this unmapped recording yet."
        case .missingUsername: "Enter a ListenBrainz username."
        case let .rateLimited(seconds): "ListenBrainz is busy. Try again in about \(seconds) seconds."
        }
    }
}
