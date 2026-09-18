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

    func testMyFeedEligibilityIsLimitedToServerSupportedActions() async {
        let model = FeedModel(account: .init(username: "listener", token: "token"), cache: EntityDetailCache())
        let foreignRecommendation = FeedEvent.fixture(position: 1, created: 200, kind: .recordingRecommendation, serverID: 4)
        let ownRecommendation = FeedEvent.fixture(position: 2, created: 200, userName: "Listener", kind: .recordingRecommendation, serverID: 5)
        let foreignReview = FeedEvent.fixture(position: 3, created: 200, kind: .critiquebrainzReview, serverID: 6)
        let foreignListen = FeedEvent.fixture(position: 4, created: 200, kind: .listen, serverID: 7)
        let ownPin = FeedEvent.fixture(position: 5, created: 200, userName: "listener", kind: .recordingPin, serverID: 8)
        let hiddenRecommendation = FeedEvent.fixture(position: 6, created: 200, kind: .recordingRecommendation, serverID: 9, hidden: true)
        let ownNotification = FeedEvent.fixture(position: 7, created: 200, userName: "listener", kind: .notification, serverID: 10)
        let foreignNotification = FeedEvent.fixture(position: 8, created: 200, kind: .notification, serverID: 11)

        XCTAssertTrue(model.canThank(foreignRecommendation, in: .activity))
        XCTAssertFalse(model.canThank(ownRecommendation, in: .activity))
        XCTAssertFalse(model.canThank(foreignReview, in: .activity))
        XCTAssertFalse(model.canThank(hiddenRecommendation, in: .activity))
        XCTAssertTrue(model.canHide(foreignReview, in: .activity))
        XCTAssertFalse(model.canHide(foreignListen, in: .activity))
        XCTAssertTrue(model.canHide(ownNotification, in: .activity))
        XCTAssertFalse(model.canHide(foreignNotification, in: .activity))
        XCTAssertTrue(model.canDelete(ownRecommendation, in: .activity))
        XCTAssertTrue(model.canDelete(ownPin, in: .activity))
        XCTAssertFalse(model.canDelete(ownPin, in: .following))
    }

    func testThankMarksExistingCardWithoutRefreshing() async {
        let event = FeedEvent.fixture(position: 1, created: 200, kind: .recordingRecommendation, serverID: 4)
        let provider = FeedMutationFixtureProvider(page: .init(username: "listener", serverCount: 1, events: [event]))
        let model = FeedModel(account: .init(username: "listener", token: "token"), provider: provider, cache: EntityDetailCache(), activityPageSize: 2)
        await model.load(mode: .activity)

        let succeeded = await model.thank(event, in: .activity, blurb: "Lovely pick")

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.state(for: .activity).events.count, 1)
        XCTAssertTrue(model.hasThanked(event, in: .activity))
        XCTAssertEqual(model.actionAlert?.kind, .confirmation)
        let operations = await provider.operations
        let pageCalls = await provider.pageCalls
        XCTAssertEqual(operations, [.thank(4, "Lovely pick")])
        XCTAssertEqual(pageCalls, 1)
    }

    func testThankFailureReturnsFalseAndDoesNotMarkCard() async {
        let event = FeedEvent.fixture(position: 1, created: 200, kind: .recordingRecommendation, serverID: 4)
        let provider = FeedMutationFixtureProvider(
            page: .init(username: "listener", serverCount: 1, events: [event]),
            mutationError: FeedFixtureError.failed
        )
        let model = FeedModel(account: .init(username: "listener", token: "token"), provider: provider, cache: EntityDetailCache(), activityPageSize: 2)
        await model.load(mode: .activity)

        let succeeded = await model.thank(event, in: .activity, blurb: nil)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(model.hasThanked(event, in: .activity))
        XCTAssertEqual(model.actionAlert?.kind, .error)
    }

    func testHideFailureRestoresEventByStableIdentity() async {
        let event = FeedEvent.fixture(position: 1, created: 200, kind: .recordingPin, serverID: 4)
        let provider = FeedMutationFixtureProvider(page: .init(username: "listener", serverCount: 1, events: [event]), mutationError: FeedFixtureError.failed)
        let model = FeedModel(account: .init(username: "listener", token: "token"), provider: provider, cache: EntityDetailCache(), activityPageSize: 2)
        await model.load(mode: .activity)

        await model.setHidden(event, in: .activity, hidden: true)

        XCTAssertEqual(model.state(for: .activity).events.first?.id, event.id)
        XCTAssertFalse(model.state(for: .activity).events.first?.hidden ?? true)
        XCTAssertEqual(model.actionAlert?.kind, .error)
    }

    func testOwnNotificationHideSucceedsAndInvalidatesCachedFeed() async {
        let event = FeedEvent.fixture(position: 1, created: 200, userName: "listener", kind: .notification, serverID: 4)
        let page = FeedPage(username: "listener", serverCount: 1, events: [event])
        let provider = FeedMutationFixtureProvider(page: page)
        let cache = EntityDetailCache<FeedPageKey, FeedPage>()
        let model = FeedModel(account: .init(username: "listener", token: "token"), provider: provider, cache: cache, activityPageSize: 2)
        await model.load(mode: .activity)
        let cacheKey = FeedPageKey(username: "listener", mode: .activity, beforeTimestamp: nil, count: 2)
        await cache.save(page, for: cacheKey)

        await model.setHidden(event, in: .activity, hidden: true)

        XCTAssertEqual(model.state(for: .activity).events.first?.hidden, true)
        let operations = await provider.operations
        XCTAssertEqual(operations, [.hidden(4, true)])
        let cached = await cache.value(for: cacheKey)
        XCTAssertNil(cached)
    }

    func testOwnPinDeletionUsesDedicatedRouteAndRollsBackOnFailure() async {
        let event = FeedEvent.fixture(position: 1, created: 200, userName: "listener", kind: .recordingPin, serverID: 12)
        let provider = FeedMutationFixtureProvider(page: .init(username: "listener", serverCount: 1, events: [event]), mutationError: FeedFixtureError.failed)
        let model = FeedModel(account: .init(username: "listener", token: "token"), provider: provider, cache: EntityDetailCache(), activityPageSize: 2)
        await model.load(mode: .activity)

        await model.delete(event, in: .activity)

        XCTAssertEqual(model.state(for: .activity).events.map(\.id), [event.id])
        let operations = await provider.operations
        XCTAssertEqual(operations, [.deletePin(12)])
    }

    func testOwnedRecommendationDeletionSucceedsAndInvalidatesCachedFeed() async {
        let event = FeedEvent.fixture(position: 1, created: 200, userName: "listener", kind: .recordingRecommendation, serverID: 12)
        let neighbor = FeedEvent.fixture(position: 2, created: 199, kind: .recordingPin, serverID: 13)
        let page = FeedPage(username: "listener", serverCount: 2, events: [event, neighbor])
        let provider = FeedMutationFixtureProvider(page: page)
        let cache = EntityDetailCache<FeedPageKey, FeedPage>()
        let model = FeedModel(account: .init(username: "listener", token: "token"), provider: provider, cache: cache, activityPageSize: 2)
        await model.load(mode: .activity)
        let cacheKey = FeedPageKey(username: "listener", mode: .activity, beforeTimestamp: nil, count: 2)
        await cache.save(page, for: cacheKey)

        await model.delete(event, in: .activity)

        XCTAssertEqual(model.state(for: .activity).events.map(\.id), [neighbor.id])
        let operations = await provider.operations
        XCTAssertEqual(operations, [.deleteEvent(12)])
        let cached = await cache.value(for: cacheKey)
        XCTAssertNil(cached)
    }

    func testDuplicateActionTapsSerializePerStableEvent() async {
        let event = FeedEvent.fixture(position: 1, created: 200, kind: .recordingRecommendation, serverID: 4)
        let provider = FeedMutationFixtureProvider(
            page: .init(username: "listener", serverCount: 1, events: [event]),
            delaysMutations: true
        )
        let model = FeedModel(account: .init(username: "listener", token: "token"), provider: provider, cache: EntityDetailCache(), activityPageSize: 2)
        await model.load(mode: .activity)

        async let first: Bool = model.thank(event, in: .activity, blurb: nil)
        async let second: Bool = model.thank(event, in: .activity, blurb: nil)
        _ = await (first, second)

        let operations = await provider.operations
        XCTAssertEqual(operations, [.thank(4, nil)])
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

private actor FeedMutationFixtureProvider: FeedProviding {
    enum Operation: Equatable, Sendable {
        case thank(Int, String?)
        case hidden(Int, Bool)
        case deleteEvent(Int)
        case deletePin(Int)
    }

    let pageValue: FeedPage
    let mutationError: Error?
    let delaysMutations: Bool
    private(set) var pageCalls = 0
    private(set) var operations: [Operation] = []

    init(page: FeedPage, mutationError: Error? = nil, delaysMutations: Bool = false) {
        pageValue = page
        self.mutationError = mutationError
        self.delaysMutations = delaysMutations
    }

    func page(username: String, mode: FeedMode, before: Date?, minimumTimestamp: Date?, count: Int) async throws -> FeedPage {
        pageCalls += 1
        return pageValue
    }

    func thank(username: String, eventType: String, eventID: Int, blurb: String?) async throws {
        operations.append(.thank(eventID, blurb))
        if delaysMutations { try await Task.sleep(for: .milliseconds(50)) }
        if let mutationError { throw mutationError }
    }

    func setHidden(username: String, eventType: String, eventID: Int, hidden: Bool) async throws {
        operations.append(.hidden(eventID, hidden))
        if let mutationError { throw mutationError }
    }

    func deleteEvent(username: String, eventType: String, eventID: Int) async throws {
        operations.append(.deleteEvent(eventID))
        if let mutationError { throw mutationError }
    }

    func deletePin(rowID: Int) async throws {
        operations.append(.deletePin(rowID))
        if let mutationError { throw mutationError }
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
        userName: String = "friend",
        kind: FeedEventKind = .listen,
        serverID: Int? = nil,
        hidden: Bool = false
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
            serverID: serverID,
            kind: kind,
            userName: userName,
            created: .init(timeIntervalSince1970: created),
            hidden: hidden,
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
