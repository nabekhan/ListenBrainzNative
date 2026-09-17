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
}

private actor RecommendationTransportSpy: RecommendationsTransport {
    struct CallCounts: Sendable {
        var recommendations = 0
        var metadata = 0
        var playlists = 0
    }

    private let source: LBRecordingRecommendations?
    private(set) var calls = CallCounts()

    init(source: LBRecordingRecommendations?) {
        self.source = source
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

    func recommendationPlaylists(username: String) async throws -> [LBPlaylistMetadata] {
        calls.playlists += 1
        return []
    }
}

private actor RecommendationFixtureProvider: RecommendationsProviding {
    private(set) var recordingCalls: [Int] = []
    private(set) var playlistCalls = 0
    private let pages: [Int: RecordingRecommendationPage]
    private let unavailableOffsets: Set<Int>
    private let playlists: [SearchPlaylist]
    private let error: (any Error & Sendable)?
    private let delayedOffsets: Set<Int>

    init(
        pages: [Int: RecordingRecommendationPage] = [:],
        unavailableOffsets: Set<Int> = [],
        playlists: [SearchPlaylist] = [],
        error: (any Error & Sendable)? = nil,
        delayedOffsets: Set<Int> = []
    ) {
        self.pages = pages
        self.unavailableOffsets = unavailableOffsets
        self.playlists = playlists
        self.error = error
        self.delayedOffsets = delayedOffsets
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
