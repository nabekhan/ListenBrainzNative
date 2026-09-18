import Foundation
import ListenBrainzKit
import XCTest
@testable import Brainz

@MainActor
final class FeedModelTests: XCTestCase {
    func testUnauthenticatedFeedDoesNotUseCacheOrProvider() async {
        let provider = FeedFixtureProvider(pages: [:])
        let cache = EntityDetailCache<FeedPageKey, FeedPage>()
        let cachedKey = FeedPageKey(
            username: "listener",
            mode: .activity,
            beforeTimestamp: nil,
            count: 2
        )
        await cache.save(page(mode: .activity, position: 0, count: 2), for: cachedKey)
        let model = FeedModel(
            account: .init(username: "listener", token: ""),
            provider: provider,
            cache: cache,
            activityPageSize: 2,
            listeningPageSize: 2
        )

        await model.load(mode: .activity)

        XCTAssertEqual(model.state(for: .activity).phase, .requiresAuthentication)
        XCTAssertTrue(model.state(for: .activity).events.isEmpty)
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testProviderMapsEmbeddedMetadataWithOneFeedCall() async throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        let source = try decoder.decode(LBFeedPage.self, from: Data(#"""
        {"count":1,"user_id":"listener","events":[{
          "event_type":"listen","user_name":"friend","created":1700000000,"hidden":false,
          "metadata":{"track_metadata":{"artist_name":"Artist","track_name":"Track","release_name":"Album","additional_info":{"recording_msid":"526bd613-fddd-4bd6-9137-ab709ac74cab"}}}
        }]}
        """#.utf8))
        let transport = FeedTransportSpy(page: source)
        let provider = ListenBrainzFeedProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let page = try await provider.page(
            username: "listener",
            mode: .following,
            before: nil,
            minimumTimestamp: nil,
            count: 40
        )

        XCTAssertEqual(page.events.first?.recording?.title, "Track")
        XCTAssertEqual(
            page.events.first?.recording?.identity.msid?.uuidString,
            "526BD613-FDDD-4BD6-9137-AB709AC74CAB"
        )
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
    }

    func testModesUseIndependentCachedFirstPages() async {
        let cache = EntityDetailCache<FeedPageKey, FeedPage>()
        let provider = FeedFixtureProvider(pages: [
            .init(mode: .activity, before: nil): page(mode: .activity, position: 0, count: 2),
            .init(mode: .following, before: nil): page(mode: .following, position: 10, count: 2),
        ])
        let model = FeedModel(
            account: .init(username: "Listener", token: "token"),
            provider: provider,
            cache: cache,
            activityPageSize: 2,
            listeningPageSize: 2
        )

        await model.load(mode: .activity)
        await model.load(mode: .following)
        await model.load(mode: .activity)

        XCTAssertEqual(model.state(for: .activity).events.map(\.recording?.title), ["Track 0", "Track 1"])
        XCTAssertEqual(model.state(for: .following).events.map(\.recording?.title), ["Track 10", "Track 11"])
        let initialCalls = await provider.calls
        XCTAssertEqual(initialCalls.map(\.mode), [.activity, .following])

        let key = FeedPageKey(username: "listener", mode: .similar, beforeTimestamp: nil, count: 2)
        await cache.save(page(mode: .similar, position: 20, count: 2), for: key)
        let cached = FeedModel(
            account: .init(username: "LISTENER", token: "token"),
            provider: provider,
            cache: cache,
            activityPageSize: 2,
            listeningPageSize: 2
        )
        await cached.load(mode: .similar)

        XCTAssertEqual(cached.state(for: .similar).events.map(\.recording?.title), ["Track 20", "Track 21"])
        XCTAssertEqual(cached.state(for: .similar).phase, .ready)
        let cachedCalls = await provider.calls
        XCTAssertEqual(cachedCalls.map(\.mode), [.activity, .following])
    }

    func testSyntheticIdentityKeepsDifferentListenersAtTheSameSecond() {
        let first = FeedEvent.fixture(position: 0, created: 200, userName: "alice")
        let second = FeedEvent.fixture(position: 0, created: 200, userName: "bob")

        XCTAssertNotEqual(first.id, second.id)
    }

    func testShortNetworkPageStopsAtTheRecentWindowBoundary() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let provider = FeedFixtureProvider(pages: [
            .init(mode: .following, before: nil): page(mode: .following, position: 0, count: 1),
        ])
        let model = FeedModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: EntityDetailCache(),
            activityPageSize: 2,
            listeningPageSize: 2,
            now: { now }
        )

        await model.load(mode: .following)

        XCTAssertFalse(model.state(for: .following).hasMore)
        let calls = await provider.calls
        XCTAssertEqual(calls.first?.minimumTimestamp, now.addingTimeInterval(-7 * 24 * 60 * 60))
    }

    func testNetworkPaginationKeepsOneSevenDayLowerBound() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let firstPage = FeedPage(
            username: "listener",
            serverCount: 2,
            events: [
                .fixture(position: 0, created: 999_900),
                .fixture(position: 1, created: 999_800),
            ]
        )
        let secondPage = FeedPage(
            username: "listener",
            serverCount: 1,
            events: [.fixture(position: 2, created: 999_700)]
        )
        let provider = FeedFixtureProvider(pages: [
            .init(mode: .similar, before: nil): firstPage,
            .init(mode: .similar, before: 999_800): secondPage,
        ])
        let model = FeedModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: EntityDetailCache(),
            activityPageSize: 2,
            listeningPageSize: 2,
            now: { now }
        )

        await model.load(mode: .similar)
        await model.loadMore(mode: .similar)

        let calls = await provider.calls
        XCTAssertEqual(calls.map(\.minimumTimestamp), Array(repeating: now.addingTimeInterval(-7 * 24 * 60 * 60), count: 2))
    }

    func testPaginationUsesOldestTimestampAndDeduplicates() async {
        let first = FeedEvent.fixture(position: 0, created: 200)
        let duplicate = FeedEvent.fixture(position: 0, created: 200)
        let older = FeedEvent.fixture(position: 1, created: 100)
        let provider = FeedFixtureProvider(pages: [
            .init(mode: .activity, before: nil): .init(username: "listener", serverCount: 2, events: [first, FeedEvent.fixture(position: 2, created: 150)]),
            .init(mode: .activity, before: 150): .init(username: "listener", serverCount: 2, events: [duplicate, older]),
        ])
        let model = FeedModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: EntityDetailCache(),
            activityPageSize: 2,
            listeningPageSize: 2
        )

        await model.load(mode: .activity)
        XCTAssertEqual(model.state(for: .activity).nextTimestamp?.timeIntervalSince1970, 150)
        await model.loadMore(mode: .activity)

        let calls = await provider.calls
        XCTAssertEqual(calls.map(\.before?.timeIntervalSince1970), [nil, 150])
        XCTAssertEqual(model.state(for: .activity).events.map(\.recording?.title), ["Track 0", "Track 2", "Track 1"])
    }

    func testNonDecreasingPaginationStopsWithoutAppendingAmbiguousPage() async {
        let provider = FeedFixtureProvider(pages: [
            .init(mode: .activity, before: nil): page(mode: .activity, position: 0, count: 2, created: 200),
            .init(mode: .activity, before: 199): .init(
                username: "listener",
                serverCount: 2,
                events: [FeedEvent.fixture(position: 2, created: 199), FeedEvent.fixture(position: 3, created: 199)]
            ),
        ])
        let model = FeedModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: EntityDetailCache(),
            activityPageSize: 2,
            listeningPageSize: 2
        )

        await model.load(mode: .activity)
        await model.loadMore(mode: .activity)

        XCTAssertEqual(model.state(for: .activity).events.count, 2)
        XCTAssertFalse(model.state(for: .activity).hasMore)
    }

    func testRefreshDoesNotQueueBehindPagination() async {
        let provider = FeedFixtureProvider(
            pages: [
                .init(mode: .activity, before: nil): page(mode: .activity, position: 0, count: 2),
                .init(mode: .activity, before: 199): page(mode: .activity, position: 2, count: 2),
            ],
            delayedKeys: [.init(mode: .activity, before: 199)]
        )
        let model = FeedModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: EntityDetailCache(),
            activityPageSize: 2,
            listeningPageSize: 2
        )
        await model.load(mode: .activity)

        let pagination = Task { await model.loadMore(mode: .activity) }
        while await provider.calls.count < 2 { await Task.yield() }
        await model.refresh(mode: .activity)
        await pagination.value

        let calls = await provider.calls
        XCTAssertEqual(calls.count, 2)
    }

    func testStaleCachedContentSurvivesRefreshFailure() async {
        let cache = EntityDetailCache<FeedPageKey, FeedPage>(timeToLive: -1)
        let key = FeedPageKey(username: "listener", mode: .activity, beforeTimestamp: nil, count: 2)
        await cache.save(page(mode: .activity, position: 0, count: 2), for: key)
        let provider = FeedFixtureProvider(pages: [:], error: FeedFixtureError.failed)
        let model = FeedModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: cache,
            activityPageSize: 2,
            listeningPageSize: 2
        )

        await model.load(mode: .activity)

        XCTAssertEqual(model.state(for: .activity).phase, .ready)
        XCTAssertEqual(model.state(for: .activity).events.count, 2)
        XCTAssertNotNil(model.state(for: .activity).refreshMessage)
    }

    private func page(mode: FeedMode, position: Int, count: Int, created: TimeInterval = 200) -> FeedPage {
        .init(
            username: "listener",
            serverCount: count,
            events: (position ..< position + count).map { FeedEvent.fixture(position: $0, created: created - Double($0 - position)) }
        )
    }
}

private actor FeedFixtureProvider: FeedProviding {
    struct Key: Hashable, Sendable {
        let mode: FeedMode
        let before: Int?
    }

    struct Call: Sendable {
        let mode: FeedMode
        let before: Date?
        let minimumTimestamp: Date?
        let count: Int
    }

    private let pages: [Key: FeedPage]
    private let delayedKeys: Set<Key>
    private let error: Error?
    private(set) var calls: [Call] = []

    init(pages: [Key: FeedPage], delayedKeys: Set<Key> = [], error: Error? = nil) {
        self.pages = pages
        self.delayedKeys = delayedKeys
        self.error = error
    }

    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> FeedPage {
        let key = Key(mode: mode, before: before.map { Int($0.timeIntervalSince1970) })
        calls.append(.init(mode: mode, before: before, minimumTimestamp: minimumTimestamp, count: count))
        if delayedKeys.contains(key) {
            try await Task.sleep(for: .milliseconds(100))
        }
        if let error { throw error }
        return pages[key] ?? .init(username: username, serverCount: 0, events: [])
    }
}

private enum FeedFixtureError: LocalizedError { case failed }

private actor FeedTransportSpy: FeedTransport {
    private let source: LBFeedPage
    private(set) var calls = 0

    init(page: LBFeedPage) {
        source = page
    }

    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> LBFeedPage {
        calls += 1
        return source
    }
}

private extension FeedEvent {
    static func fixture(
        position: Int,
        created: TimeInterval,
        userName: String = "friend"
    ) -> FeedEvent {
        let recording = Recording(
            identity: .init(mbid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", position + 1)), msid: nil),
            title: "Track \(position)",
            artistName: "Artist",
            artistMBIDs: [],
            releaseTitle: nil,
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: nil,
            source: nil
        )
        return FeedEvent(
            serverID: nil,
            kind: .listen,
            userName: userName,
            created: .init(timeIntervalSince1970: created),
            hidden: false,
            similarity: nil,
            recording: recording,
            blurb: nil,
            users: [],
            userName0: nil,
            userName1: nil,
            relationshipType: nil,
            message: nil,
            entityName: nil,
            entityID: nil,
            entityType: nil,
            rating: nil,
            text: nil,
            reviewMBID: nil,
            originalEventID: nil,
            originalEventType: nil,
            thankerUsername: nil,
            thankeeUsername: nil
        )
    }
}
