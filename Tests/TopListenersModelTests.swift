import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class TopListenersModelTests: XCTestCase {
    func testNormalizationKeepsTheBestCanonicalUsernameAndDropsMalformedRows() {
        let entity = TopListenersEntity(kind: .artist, mbid: UUID())
        let value = TopListeners(
            entity: entity,
            listeners: [
                .init(username: "  Ada ", listenCount: 4),
                .init(username: "ada", listenCount: 7),
                .init(username: " ", listenCount: 9),
                .init(username: "negative", listenCount: -1),
                .init(username: "Bea", listenCount: 7),
            ],
            totalListenCount: -3
        )

        XCTAssertEqual(value.listeners.map(\.username), ["ada", "Bea"])
        XCTAssertEqual(value.listeners.map(\.listenCount), [7, 7])
        XCTAssertNil(value.totalListenCount)
    }

    func testFreshCacheAvoidsASecondProviderRead() async {
        let entity = TopListenersEntity(kind: .artist, mbid: UUID())
        let provider = TopListenersFixtureProvider(results: [.success(listeners(entity))])
        let cache = EntityDetailCache<TopListenersCacheKey, TopListeners>()
        let scope = RequestGate.ReadScope.isolated()
        let first = TopListenersModel(entity: entity, scope: scope, provider: provider, cache: cache)
        let second = TopListenersModel(entity: entity, scope: scope, provider: provider, cache: cache)

        await first.load()
        await second.load()

        XCTAssertEqual(first.phase, .loaded(listeners(entity)))
        XCTAssertEqual(second.phase, .loaded(listeners(entity)))
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testEmptyResponseIsUnavailableRatherThanAnEmptyLeaderboard() async {
        let entity = TopListenersEntity(kind: .releaseGroup, mbid: UUID())
        let provider = TopListenersFixtureProvider(results: [.success(.init(entity: entity, listeners: [], totalListenCount: 0))])
        let model = TopListenersModel(entity: entity, provider: provider)

        await model.load()

        XCTAssertEqual(model.phase, .unavailable)
    }

    func testNoContentResponseIsUnavailable() async {
        let entity = TopListenersEntity(kind: .artist, mbid: UUID())
        let provider = TopListenersFixtureProvider(results: [.success(nil)])
        let cache = EntityDetailCache<TopListenersCacheKey, TopListeners>()
        let scope = RequestGate.ReadScope.isolated()
        let first = TopListenersModel(entity: entity, scope: scope, provider: provider, cache: cache)
        let second = TopListenersModel(entity: entity, scope: scope, provider: provider, cache: cache)

        await first.load()
        await second.load()

        XCTAssertEqual(first.phase, .unavailable)
        XCTAssertEqual(second.phase, .unavailable)
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testStaleContentRemainsVisibleWhenRefreshFails() async {
        let entity = TopListenersEntity(kind: .artist, mbid: UUID())
        let cache = EntityDetailCache<TopListenersCacheKey, TopListeners>(timeToLive: -1)
        let seed = listeners(entity)
        let scope = RequestGate.ReadScope.isolated()
        await cache.save(seed, for: .init(entity: entity, scope: scope))
        let provider = TopListenersFixtureProvider(results: [.failure])
        let model = TopListenersModel(entity: entity, scope: scope, provider: provider, cache: cache)

        await model.load()

        XCTAssertEqual(model.phase, .loaded(seed))
        XCTAssertEqual(model.refreshMessage, "Fixture request failed.")
    }
}

@MainActor
final class TopListenersProviderTests: XCTestCase {
    func testExactConcurrentEntityReadIsCoalescedByTheSharedGate() async throws {
        let entity = TopListenersEntity(kind: .artist, mbid: UUID())
        let transport = TopListenersTransportFixture(response: rawListeners())
        let provider = ListenBrainzTopListenersProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: { _ in try await transport.value() }
        )

        async let first = provider.topListeners(for: entity)
        async let second = provider.topListeners(for: entity)
        let loaded = try await [first, second]

        XCTAssertEqual(loaded.compactMap { $0?.listeners.first?.username }, ["listener", "listener"])
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testArtistAndReleaseGroupWithSameMBIDDoNotCoalesce() async throws {
        let mbid = UUID()
        let transport = TopListenersTransportFixture(response: rawListeners())
        let provider = ListenBrainzTopListenersProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: { _ in try await transport.value() }
        )

        async let artist = provider.topListeners(for: .init(kind: .artist, mbid: mbid))
        async let releaseGroup = provider.topListeners(for: .init(kind: .releaseGroup, mbid: mbid))
        _ = try await [artist, releaseGroup]

        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 2)
    }
}

private actor TopListenersFixtureProvider: TopListenersProviding {
    enum Result: Sendable { case success(TopListeners?), failure }
    private let results: [Result]
    private var calls = 0

    init(results: [Result]) { self.results = results }

    func topListeners(for entity: TopListenersEntity) async throws -> TopListeners? {
        let index = calls
        calls += 1
        switch results.indices.contains(index) ? results[index] : results.last ?? .failure {
        case let .success(value): return value
        case .failure: throw TopListenersFixtureError.failed
        }
    }

    func callCount() -> Int { calls }
}

private actor TopListenersTransportFixture {
    private let response: LBTopListeners
    private var calls = 0
    init(response: LBTopListeners) { self.response = response }
    func value() async throws -> LBTopListeners {
        calls += 1
        try await ContinuousClock().sleep(for: .milliseconds(25))
        return response
    }
    func callCount() -> Int { calls }
}

private enum TopListenersFixtureError: LocalizedError {
    case failed
    var errorDescription: String? { "Fixture request failed." }
}

private func listeners(_ entity: TopListenersEntity) -> TopListeners {
    .init(entity: entity, listeners: [.init(username: "listener", listenCount: 12)], totalListenCount: 12)
}

private func rawListeners() -> LBTopListeners {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .secondsSince1970
    return try! decoder.decode(LBTopListeners.self, from: Data("""
    { "listeners": [{ "user_name": "listener", "listen_count": 12 }], "total_listen_count": 12 }
    """.utf8))
}
