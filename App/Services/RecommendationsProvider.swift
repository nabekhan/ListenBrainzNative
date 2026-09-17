import Foundation
import ListenBrainzKit

protocol RecommendationsProviding: Sendable {
    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> RecordingRecommendationPage?

    func recommendationPlaylists(username: String) async throws -> [SearchPlaylist]
}

protocol RecommendationsTransport: Sendable {
    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> LBRecordingRecommendations?

    func recordingMetadata(mbids: [UUID]) async throws -> [UUID: LBRecording]
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

    func recommendationPlaylists(username: String) async throws -> [LBPlaylistMetadata] {
        try await client.core.userPlaylistsRecommendation(username: username)
    }
}

struct ListenBrainzRecommendationsProvider: RecommendationsProviding {
    private let transport: any RecommendationsTransport
    private let gate: RequestGate

    init(token: String, gate: RequestGate = .shared) {
        self.transport = LiveRecommendationsTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
    }

    init(transport: some RecommendationsTransport, gate: RequestGate) {
        self.transport = transport
        self.gate = gate
    }

    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> RecordingRecommendationPage? {
        guard let source = try await perform({
            try await transport.recordingRecommendations(
                username: username,
                offset: offset,
                count: count
            )
        }) else { return nil }

        let orderedRecommendations = source.recommendations
        guard !orderedRecommendations.isEmpty else {
            return Self.map(source, recommendations: [])
        }

        let recommendations = try await perform {
            let metadata = try await transport.recordingMetadata(
                mbids: orderedRecommendations.map(\.recordingMBID)
            )
            return orderedRecommendations.map { recommendation in
                Self.map(recommendation, metadata: metadata[recommendation.recordingMBID])
            }
        }

        return Self.map(source, recommendations: recommendations)
    }

    func recommendationPlaylists(username: String) async throws -> [SearchPlaylist] {
        try await perform {
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
            title: nonempty(metadata?.recording.name) ?? "Metadata unavailable",
            artistName: nonempty(artist?.name) ?? "MusicBrainz recording",
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
