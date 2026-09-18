import Foundation
import ListenBrainzKit
import XCTest
@testable import Brainz

@MainActor
final class RecommendationsModelTests: XCTestCase {
    func testSuccessfulEmptyPageSkipsMetadataHydration() async throws {
        let transport = RecommendationTransportSpy(source: try emptySource())
        let provider = ListenBrainzRecommendationsProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let page = try await provider.recordingRecommendations(
            username: "listener",
            offset: 25,
            count: 25
        )

        XCTAssertEqual(page?.recommendations, [])
        XCTAssertEqual(page?.nextOffset, 25)
        let calls = await transport.calls
        XCTAssertEqual(calls.recommendations, 1)
        XCTAssertEqual(calls.metadata, 0)
    }

    func testProviderBatchesAndMapsRecommendationFeedback() async throws {
        let liked = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
        let hiddenServerRating = UUID(uuidString: "a6081bc1-2a76-4984-b21f-38bc3dcca3a5")!
        let transport = RecommendationTransportSpy(
            source: try emptySource(),
            feedbackBatch: try feedbackBatch(liked: liked, badRecommendation: hiddenServerRating)
        )
        let provider = ListenBrainzRecommendationsProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let feedback = try await provider.recommendationFeedback(
            username: "listener",
            recordingMBIDs: [liked, hiddenServerRating]
        )

        XCTAssertEqual(feedback, [liked: .like])
        let calls = await transport.calls
        XCTAssertEqual(calls.feedbackReads, 1)
    }

    func testProviderRoutesSubmitAndClearRecommendationFeedback() async throws {
        let mbid = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
        let transport = RecommendationTransportSpy(source: try emptySource())
        let provider = ListenBrainzRecommendationsProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        try await provider.setRecommendationFeedback(.love, recordingMBID: mbid)
        try await provider.setRecommendationFeedback(nil, recordingMBID: mbid)

        let calls = await transport.calls
        XCTAssertEqual(calls.feedbackSubmissions, 1)
        XCTAssertEqual(calls.feedbackClears, 1)
    }

    func testInitialPageLoadsOnceAndFreshCacheAvoidsTransport() async {
        let account = Account(username: "Listener", token: "")
        let cache = EntityDetailCache<RecommendationPageKey, RecordingRecommendationPage>()
        let firstProvider = RecommendationFixtureProvider(pages: [0: page(offset: 0, count: 2, total: 2)])
        let first = RecommendationsModel(
            account: account,
            provider: firstProvider,
            recordingCache: cache,
            playlistCache: EntityDetailCache(),
            pageSize: 2
        )

        await first.loadRecommendations()
        await first.loadRecommendations()

        XCTAssertEqual(first.recordingPhase, .ready)
        XCTAssertEqual(first.recommendations.map(\.recording.title), ["Track 0", "Track 1"])
        let firstCalls = await firstProvider.recordingCalls
        XCTAssertEqual(firstCalls, [0])

        let secondProvider = RecommendationFixtureProvider(pages: [0: page(offset: 0, count: 1, total: 1)])
        let second = RecommendationsModel(
            account: account,
            provider: secondProvider,
            recordingCache: cache,
            playlistCache: EntityDetailCache(),
            pageSize: 2
        )
        await second.loadRecommendations()

        XCTAssertEqual(second.recommendations.map(\.recording.title), ["Track 0", "Track 1"])
        let secondCalls = await secondProvider.recordingCalls
        XCTAssertTrue(secondCalls.isEmpty)
    }

    func testPaginationUsesServerOffsetAndDeduplicatesOverlappingRows() async {
        let duplicated = recommended(position: 1)
        let provider = RecommendationFixtureProvider(pages: [
            0: page(offset: 0, count: 2, total: 4),
            2: RecordingRecommendationPage(
                username: "listener",
                lastUpdated: .now,
                offset: 2,
                serverCount: 2,
                totalCount: 4,
                recommendations: [duplicated, recommended(position: 2)]
            ),
        ])
        let model = RecommendationsModel(
            account: .init(username: "listener", token: ""),
            provider: provider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache(),
            pageSize: 2
        )

        await model.loadRecommendations()
        await model.loadMoreRecommendations()

        let recordingCalls = await provider.recordingCalls
        XCTAssertEqual(recordingCalls, [0, 2])
        XCTAssertEqual(model.recommendations.map(\.recording.title), ["Track 0", "Track 1", "Track 2"])
        XCTAssertFalse(model.hasMoreRecommendations)
        XCTAssertEqual(model.nextOffset, 4)
    }

    func testRefreshDoesNotQueueRequestsWhilePaginationIsInFlight() async {
        let provider = RecommendationFixtureProvider(
            pages: [
                0: page(offset: 0, count: 2, total: 4),
                2: page(offset: 2, count: 2, total: 4),
            ],
            delayedOffsets: [2]
        )
        let model = RecommendationsModel(
            account: .init(username: "listener", token: ""),
            provider: provider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache(),
            pageSize: 2
        )
        await model.loadRecommendations()

        let pagination = Task { await model.loadMoreRecommendations() }
        while await provider.recordingCalls.count < 2 {
            await Task.yield()
        }
        await model.refreshRecommendations()
        await pagination.value

        let calls = await provider.recordingCalls
        XCTAssertEqual(calls, [0, 2])
        XCTAssertEqual(model.recommendations.count, 4)
    }

    func testUnavailableRecommendationsAreAnHonestEmptyState() async {
        let provider = RecommendationFixtureProvider(unavailableOffsets: [0])
        let model = RecommendationsModel(
            account: .init(username: "listener", token: ""),
            provider: provider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache()
        )

        await model.loadRecommendations()

        XCTAssertEqual(model.recordingPhase, .unavailable)
        XCTAssertTrue(model.recommendations.isEmpty)
        let playlistCalls = await provider.playlistCalls
        XCTAssertEqual(playlistCalls, 0)
    }

    func testStaleRecommendationsSurviveRefreshFailure() async {
        let cache = EntityDetailCache<RecommendationPageKey, RecordingRecommendationPage>(timeToLive: -1)
        let key = RecommendationPageKey(username: "listener", offset: 0, count: 25)
        await cache.save(page(offset: 0, count: 2, total: 2), for: key)
        let provider = RecommendationFixtureProvider(error: RecommendationFixtureError.failed)
        let model = RecommendationsModel(
            account: .init(username: "listener", token: ""),
            provider: provider,
            recordingCache: cache,
            playlistCache: EntityDetailCache()
        )

        await model.loadRecommendations()

        XCTAssertEqual(model.recordingPhase, .ready)
        XCTAssertEqual(model.recommendations.count, 2)
        XCTAssertNotNil(model.recordingRefreshMessage)
    }

    func testPlaylistsLoadLazilyAndUseTheirOwnCache() async {
        let playlist = SearchPlaylist(
            title: "Weekly Jams",
            creator: "troi-bot",
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(UUID().uuidString)",
            isPublic: true,
            lastModifiedAt: nil,
            recommendationType: "weekly-jams",
            expiresAt: nil
        )
        let provider = RecommendationFixtureProvider(
            pages: [0: page(offset: 0, count: 1, total: 1)],
            playlists: [playlist]
        )
        let model = RecommendationsModel(
            account: .init(username: "listener", token: ""),
            provider: provider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache()
        )

        await model.loadRecommendations()
        let playlistCallsBefore = await provider.playlistCalls
        XCTAssertEqual(playlistCallsBefore, 0)
        await model.loadPlaylists()
        await model.loadPlaylists()

        XCTAssertEqual(model.playlistPhase, .ready)
        XCTAssertEqual(model.playlists.first?.recommendationType, "weekly-jams")
        let playlistCallsAfter = await provider.playlistCalls
        XCTAssertEqual(playlistCallsAfter, 1)
    }

    func testAuthenticatedLoadFetchesFeedbackOnceForThePage() async {
        let firstPage = page(offset: 0, count: 2, total: 2)
        let firstMBID = firstPage.recommendations[0].recording.identity.mbid!
        let provider = RecommendationFixtureProvider(
            pages: [0: firstPage],
            feedback: [firstMBID: .like]
        )
        let model = RecommendationsModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache(),
            pageSize: 2
        )

        await model.loadRecommendations()

        XCTAssertEqual(model.feedback(for: firstPage.recommendations[0]), .like)
        XCTAssertNil(model.feedback(for: firstPage.recommendations[1]))
        let calls = await provider.feedbackReadCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(Set(calls[0]), Set(firstPage.recommendations.compactMap(\.recording.identity.mbid)))
    }

    func testFeedbackMutationIsOptimisticAndBlocksStaleQueuedChoices() async {
        let firstPage = page(offset: 0, count: 1, total: 1)
        let recommendation = firstPage.recommendations[0]
        let provider = RecommendationFixtureProvider(
            pages: [0: firstPage],
            delaysFeedbackMutation: true
        )
        let model = RecommendationsModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache()
        )
        await model.loadRecommendations()

        let firstMutation = Task { await model.setFeedback(.love, for: recommendation) }
        while await provider.feedbackMutationCalls.isEmpty { await Task.yield() }

        XCTAssertEqual(model.feedback(for: recommendation), .love)
        XCTAssertTrue(model.isUpdatingFeedback(for: recommendation))
        await model.setFeedback(.hate, for: recommendation)
        await firstMutation.value

        XCTAssertEqual(model.feedback(for: recommendation), .love)
        XCTAssertFalse(model.isUpdatingFeedback(for: recommendation))
        let calls = await provider.feedbackMutationCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.rating, .love)
    }

    func testSelectingCurrentFeedbackClearsIt() async {
        let firstPage = page(offset: 0, count: 1, total: 1)
        let recommendation = firstPage.recommendations[0]
        let mbid = recommendation.recording.identity.mbid!
        let provider = RecommendationFixtureProvider(
            pages: [0: firstPage],
            feedback: [mbid: .love]
        )
        let model = RecommendationsModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache()
        )
        await model.loadRecommendations()

        await model.setFeedback(.love, for: recommendation)

        XCTAssertNil(model.feedback(for: recommendation))
        let calls = await provider.feedbackMutationCalls
        XCTAssertEqual(calls.last?.recordingMBID, mbid)
        XCTAssertNil(calls.last?.rating)
    }

    func testFeedbackFailureRollsBackAndUnauthenticatedUseShortCircuits() async {
        let firstPage = page(offset: 0, count: 1, total: 1)
        let recommendation = firstPage.recommendations[0]
        let failingProvider = RecommendationFixtureProvider(
            pages: [0: firstPage],
            mutationError: RecommendationFixtureError.failed
        )
        let authenticated = RecommendationsModel(
            account: .init(username: "listener", token: "token"),
            provider: failingProvider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache()
        )
        await authenticated.loadRecommendations()

        await authenticated.setFeedback(.dislike, for: recommendation)

        XCTAssertNil(authenticated.feedback(for: recommendation))
        XCTAssertNotNil(authenticated.feedbackActionError)

        let publicProvider = RecommendationFixtureProvider(pages: [0: firstPage])
        let publicModel = RecommendationsModel(
            account: .init(username: "listener", token: ""),
            provider: publicProvider,
            recordingCache: EntityDetailCache(),
            playlistCache: EntityDetailCache()
        )
        await publicModel.setFeedback(.like, for: recommendation)

        XCTAssertNotNil(publicModel.feedbackActionError)
        let publicCalls = await publicProvider.feedbackMutationCalls
        XCTAssertTrue(publicCalls.isEmpty)
    }

    private func page(offset: Int, count: Int, total: Int) -> RecordingRecommendationPage {
        RecordingRecommendationPage(
            username: "listener",
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            offset: offset,
            serverCount: count,
            totalCount: total,
            recommendations: (offset ..< offset + count).map(recommended)
        )
    }

    private func recommended(position: Int) -> RecommendedRecording {
        RecommendedRecording(
            recording: Recording(
                identity: .init(
                    mbid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", position + 1)),
                    msid: nil
                ),
                title: "Track \(position)",
                artistName: "Artist",
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            score: Double(100 - position),
            lastListenedAt: nil
        )
    }

    private func emptySource() throws -> LBRecordingRecommendations {
        let data = Data(#"""
        {
          "modelId": "model-1",
          "modelUrl": "https://example.com/model",
          "mbids": [],
          "entity": "recording",
          "userName": "listener",
          "lastUpdated": 1700000000,
          "count": 0,
          "totalMbidCount": 0,
          "offset": 25
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(LBRecordingRecommendations.self, from: data)
    }

    private func feedbackBatch(
        liked: UUID,
        badRecommendation: UUID
    ) throws -> LBRecommendationFeedbackBatch {
        let data = Data(#"""
        {"feedback":[
          {"created":1700000000,"recording_mbid":"\#(liked.uuidString)","rating":"like"},
          {"created":1700000001,"recording_mbid":"\#(badRecommendation.uuidString)","rating":"bad_recommendation"}
        ],"user_name":"listener"}
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(LBRecommendationFeedbackBatch.self, from: data)
    }
}

private actor RecommendationTransportSpy: RecommendationsTransport {
    struct CallCounts: Sendable {
        var recommendations = 0
        var metadata = 0
        var feedbackReads = 0
        var feedbackSubmissions = 0
        var feedbackClears = 0
        var playlists = 0
    }

    private let source: LBRecordingRecommendations?
    private let feedbackBatch: LBRecommendationFeedbackBatch?
    private(set) var calls = CallCounts()

    init(
        source: LBRecordingRecommendations?,
        feedbackBatch: LBRecommendationFeedbackBatch? = nil
    ) {
        self.source = source
        self.feedbackBatch = feedbackBatch
    }

    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> LBRecordingRecommendations? {
        calls.recommendations += 1
        return source
    }

    func recordingMetadata(mbids: [UUID]) async throws -> [UUID: LBRecording] {
        calls.metadata += 1
        return [:]
    }

    func recommendationFeedback(
        username: String,
        recordingMBIDs: [UUID]
    ) async throws -> LBRecommendationFeedbackBatch {
        calls.feedbackReads += 1
        guard let feedbackBatch else { throw RecommendationFixtureError.missingFixture }
        return feedbackBatch
    }

    func submitRecommendationFeedback(
        recordingMBID: UUID,
        rating: LBRecommendationFeedbackRating
    ) async throws -> LBRecommendationFeedbackStatus {
        calls.feedbackSubmissions += 1
        return try status()
    }

    func clearRecommendationFeedback(
        recordingMBID: UUID
    ) async throws -> LBRecommendationFeedbackStatus {
        calls.feedbackClears += 1
        return try status()
    }

    func recommendationPlaylists(username: String) async throws -> [LBPlaylistMetadata] {
        calls.playlists += 1
        return []
    }

    private func status() throws -> LBRecommendationFeedbackStatus {
        try JSONDecoder().decode(
            LBRecommendationFeedbackStatus.self,
            from: Data(#"{"status":"ok"}"#.utf8)
        )
    }
}

private actor RecommendationFixtureProvider: RecommendationsProviding {
    struct MutationCall: Equatable, Sendable {
        let recordingMBID: UUID
        let rating: RecommendationRating?
    }

    private(set) var recordingCalls: [Int] = []
    private(set) var playlistCalls = 0
    private(set) var feedbackReadCalls: [[UUID]] = []
    private(set) var feedbackMutationCalls: [MutationCall] = []
    private let pages: [Int: RecordingRecommendationPage]
    private let unavailableOffsets: Set<Int>
    private let playlists: [SearchPlaylist]
    private let feedback: [UUID: RecommendationRating]
    private let error: (any Error & Sendable)?
    private let mutationError: (any Error & Sendable)?
    private let delayedOffsets: Set<Int>
    private let delaysFeedbackMutation: Bool

    init(
        pages: [Int: RecordingRecommendationPage] = [:],
        unavailableOffsets: Set<Int> = [],
        playlists: [SearchPlaylist] = [],
        feedback: [UUID: RecommendationRating] = [:],
        error: (any Error & Sendable)? = nil,
        mutationError: (any Error & Sendable)? = nil,
        delayedOffsets: Set<Int> = [],
        delaysFeedbackMutation: Bool = false
    ) {
        self.pages = pages
        self.unavailableOffsets = unavailableOffsets
        self.playlists = playlists
        self.feedback = feedback
        self.error = error
        self.mutationError = mutationError
        self.delayedOffsets = delayedOffsets
        self.delaysFeedbackMutation = delaysFeedbackMutation
    }

    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> RecordingRecommendationPage? {
        recordingCalls.append(offset)
        if delayedOffsets.contains(offset) {
            try await Task.sleep(for: .milliseconds(50))
        }
        if let error { throw error }
        if unavailableOffsets.contains(offset) { return nil }
        guard let page = pages[offset] else { throw RecommendationFixtureError.missingFixture }
        return page
    }

    func recommendationFeedback(
        username: String,
        recordingMBIDs: [UUID]
    ) async throws -> [UUID: RecommendationRating] {
        feedbackReadCalls.append(recordingMBIDs)
        if let error { throw error }
        return feedback.filter { recordingMBIDs.contains($0.key) }
    }

    func setRecommendationFeedback(
        _ rating: RecommendationRating?,
        recordingMBID: UUID
    ) async throws {
        feedbackMutationCalls.append(.init(recordingMBID: recordingMBID, rating: rating))
        if delaysFeedbackMutation {
            try await Task.sleep(for: .milliseconds(75))
        }
        if let mutationError { throw mutationError }
    }

    func recommendationPlaylists(username: String) async throws -> [SearchPlaylist] {
        playlistCalls += 1
        if let error { throw error }
        return playlists
    }
}

private enum RecommendationFixtureError: LocalizedError, Sendable {
    case failed
    case missingFixture

    var errorDescription: String? { "Fixture recommendation request failed." }
}
