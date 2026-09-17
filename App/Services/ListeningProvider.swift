import Foundation

protocol ListeningProvider: Sendable {
    func validateToken() async throws -> String
    func recentListens(username: String, before: Date?, count: Int) async throws -> [Listen]
    func playingNow(username: String) async throws -> Listen?
    func listenCount(username: String) async throws -> Int
    func topArtists(username: String, count: Int) async throws -> [RankedArtist]
    func topReleases(username: String, count: Int) async throws -> [RankedRelease]
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording]
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws
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
