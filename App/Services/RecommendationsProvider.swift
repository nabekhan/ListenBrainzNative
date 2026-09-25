import Foundation
import ListenBrainzKit

protocol RecommendationsProviding: Sendable {
    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> RecordingRecommendationPage?

    func recommendationFeedback(
        username: String,
        recordingMBIDs: [UUID]
    ) async throws -> [UUID: RecommendationRating]

    func setRecommendationFeedback(
        _ rating: RecommendationRating?,
        recordingMBID: UUID
    ) async throws

    func recommendationPlaylists(username: String) async throws -> [SearchPlaylist]
}

protocol RecommendationsTransport: Sendable {
    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> LBRecordingRecommendations?

    func recordingMetadata(mbids: [UUID]) async throws -> [UUID: LBRecording]
    func recommendationFeedback(
        username: String,
        recordingMBIDs: [UUID]
    ) async throws -> LBRecommendationFeedbackBatch
    func submitRecommendationFeedback(
        recordingMBID: UUID,
        rating: LBRecommendationFeedbackRating
    ) async throws -> LBRecommendationFeedbackStatus
    func clearRecommendationFeedback(
        recordingMBID: UUID
    ) async throws -> LBRecommendationFeedbackStatus
    func recommendationPlaylists(username: String) async throws -> [LBPlaylistMetadata]
}

private struct LiveRecommendationsTransport: RecommendationsTransport {
    let client: LBClient

    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> LBRecordingRecommendations? {
        try await client.recommendations.recordings(
            user: username,
            count: count,
            offset: offset
        )
    }

    func recordingMetadata(mbids: [UUID]) async throws -> [UUID: LBRecording] {
        try await client.metadata.recordings(
            mbids: mbids,
            including: [LBMetaInclusion.artist, .release]
        )
    }

    func recommendationFeedback(
        username: String,
        recordingMBIDs: [UUID]
    ) async throws -> LBRecommendationFeedbackBatch {
        try await client.recommendations.feedback(
            user: username,
            recordingMBIDs: recordingMBIDs
        )
    }

    func submitRecommendationFeedback(
        recordingMBID: UUID,
        rating: LBRecommendationFeedbackRating
    ) async throws -> LBRecommendationFeedbackStatus {
        try await client.recommendations.submitFeedback(
            recordingMBID: recordingMBID,
            rating: rating
        )
    }

    func clearRecommendationFeedback(
        recordingMBID: UUID
    ) async throws -> LBRecommendationFeedbackStatus {
        try await client.recommendations.clearFeedback(recordingMBID: recordingMBID)
    }

    func recommendationPlaylists(username: String) async throws -> [LBPlaylistMetadata] {
        try await client.core.userPlaylistsRecommendation(username: username)
    }
}

struct ListenBrainzRecommendationsProvider: RecommendationsProviding {
    private let transport: any RecommendationsTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        self.transport = LiveRecommendationsTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        transport: some RecommendationsTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> RecordingRecommendationPage? {
        let safeOffset = max(offset, 0)
        let safeCount = min(max(count, 1), 100)
        guard let source = try await read(.recommendations(readScope, user: username, offset: safeOffset, count: safeCount), {
            try await transport.recordingRecommendations(
                username: username,
                offset: safeOffset,
                count: safeCount
            )
        }) else { return nil }

        let orderedRecommendations = source.recommendations
        guard !orderedRecommendations.isEmpty else {
            return Self.map(source, recommendations: [])
        }

        let orderedIDs = orderedRecommendations.map(\.recordingMBID)
        let recommendations = try await read(.recommendationMetadata(readScope, mbids: orderedIDs)) {
            let metadata = try await transport.recordingMetadata(
                mbids: orderedIDs
            )
            return orderedRecommendations.map { recommendation in
                Self.map(recommendation, metadata: metadata[recommendation.recordingMBID])
            }
        }

        return Self.map(source, recommendations: recommendations)
    }

    func recommendationFeedback(
        username: String,
        recordingMBIDs: [UUID]
    ) async throws -> [UUID: RecommendationRating] {
        guard !recordingMBIDs.isEmpty else { return [:] }
        var feedback: [UUID: RecommendationRating] = [:]
        for start in stride(from: 0, to: recordingMBIDs.count, by: 75) {
            let end = min(start + 75, recordingMBIDs.count)
            let chunk = Array(recordingMBIDs[start ..< end])
            let source = try await read(.recommendationFeedback(readScope, user: username, mbids: chunk)) {
                try await transport.recommendationFeedback(
                    username: username,
                    recordingMBIDs: chunk
                )
            }
            for item in source.feedback {
                guard let rating = Self.map(item.rating) else { continue }
                feedback[item.recordingMBID] = rating
            }
        }
        return feedback
    }

    func setRecommendationFeedback(
        _ rating: RecommendationRating?,
        recordingMBID: UUID
    ) async throws {
        let status = try await perform {
            if let rating {
                return try await transport.submitRecommendationFeedback(
                    recordingMBID: recordingMBID,
                    rating: Self.map(rating)
                )
            }
            return try await transport.clearRecommendationFeedback(recordingMBID: recordingMBID)
        }
        guard status.status.lowercased() == "ok" else {
            throw RecommendationsProviderError.invalidMutationResponse
        }
    }

    func recommendationPlaylists(username: String) async throws -> [SearchPlaylist] {
        try await read(.recommendationPlaylists(readScope, user: username)) {
            try await transport.recommendationPlaylists(username: username).map {
                SearchPlaylist(
                    title: $0.title,
                    creator: $0.creator,
                    annotation: $0.annotation,
                    identifier: $0.identifier,
                    isPublic: $0.isPublic,
                    lastModifiedAt: $0.lastModifiedAt,
                    recommendationType: $0.recommendationType,
                    expiresAt: $0.expiresAt
                )
            }
        }
    }

    private static func map(
        _ source: LBRecordingRecommendations,
        recommendations: [RecommendedRecording]
    ) -> RecordingRecommendationPage {
        RecordingRecommendationPage(
            username: source.userName,
            lastUpdated: source.lastUpdated,
            offset: source.offset,
            serverCount: source.count,
            totalCount: source.totalCount,
            recommendations: recommendations
        )
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
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth {
            throw RecommendationsProviderError.invalidAuthentication
        } catch LBError.forbidden {
            throw RecommendationsProviderError.invalidAuthentication
        } catch LBError.noToken {
            throw RecommendationsProviderError.invalidAuthentication
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
        } catch LBError.invalidAuth, LBError.forbidden, LBError.noToken {
            throw RecommendationsProviderError.invalidAuthentication
        }
    }

    private static func map(_ source: LBRecommendationFeedbackRating) -> RecommendationRating? {
        switch source {
        case .hate: .hate
        case .dislike: .dislike
        case .like: .like
        case .love: .love
        case .badRecommendation: nil
        }
    }

    private static func map(_ source: RecommendationRating) -> LBRecommendationFeedbackRating {
        switch source {
        case .hate: .hate
        case .dislike: .dislike
        case .like: .like
        case .love: .love
        }
    }

    private static func map(
        _ recommendation: LBRecordingRecommendation,
        metadata: LBRecording?
    ) -> RecommendedRecording {
        let release = metadata?.release
        let artist = metadata?.artist
        let recording = Recording(
            identity: .init(mbid: recommendation.recordingMBID, msid: nil),
            title: nonempty(metadata?.recording.name) ?? String(localized: "Metadata unavailable"),
            artistName: nonempty(artist?.name) ?? String(localized: "MusicBrainz recording"),
            artistMBIDs: artist?.artists.map(\.id) ?? [],
            releaseTitle: nonempty(release?.name),
            releaseMBID: release?.mbid,
            releaseGroupMBID: release?.releaseGroupMbid,
            artworkReleaseMBID: release?.caaReleaseMbid ?? release?.mbid,
            durationMilliseconds: metadata?.recording.length,
            source: nil
        )
        return RecommendedRecording(
            recording: recording,
            score: recommendation.score,
            lastListenedAt: recommendation.latestListenedAt
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum RecommendationsProviderError: LocalizedError {
    case invalidAuthentication
    case invalidMutationResponse

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            String(localized: "Your ListenBrainz sign-in is no longer valid. Reconnect your token to tune recommendations.")
        case .invalidMutationResponse:
            String(localized: "ListenBrainz did not confirm the recommendation update.")
        }
    }
}
