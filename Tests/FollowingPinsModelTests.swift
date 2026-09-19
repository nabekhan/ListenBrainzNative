import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class FollowingPinsModelTests: XCTestCase {
    func testFreshPageCacheAvoidsASecondRead() async {
        let cache = EntityDetailCache<FollowingPinsPageKey, FollowingPinsPage>()
        let provider = FollowingPinsFixtureProvider(results: [.success(page(offset: 0, count: 1))])
        let first = FollowingPinsModel(username: "Viewer", provider: provider, cache: cache)
        let second = FollowingPinsModel(username: "Viewer", provider: provider, cache: cache)
        await first.load()
        await second.load()
        XCTAssertEqual(first.pins.count, 1)
        XCTAssertEqual(second.pins.count, 1)
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testPaginationUsesServerCountNotDeduplicatedCountAndStopsOnShortPage() async {
        let first = FollowingPinsPage(username: "viewer", pins: [pin(1, "one"), pin(1, "one"), pin(2, "two")], serverCount: 3, offset: 0)
        let second = FollowingPinsPage(username: "viewer", pins: [pin(3, "one")], serverCount: 1, offset: 3)
        let provider = FollowingPinsFixtureProvider(results: [.success(first), .success(second)])
        let model = FollowingPinsModel(username: "viewer", provider: provider, cache: EntityDetailCache(), pageSize: 3)
        await model.load()
        XCTAssertEqual(model.pins.count, 2)
        XCTAssertTrue(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(model.pins.map(\.rowID), [1, 2, 3])
        XCTAssertFalse(model.hasMore)
        let offsets = await provider.offsets()
        XCTAssertEqual(offsets, [0, 3])
    }

    func testIdentityDeduplicatesOwnerCaseButKeepsTheSameRowForAnotherOwner() async {
        let source = FollowingPinsPage(
            username: "viewer",
            pins: [pin(7, "Owner"), pin(7, " owner "), pin(7, "AnotherOwner")],
            serverCount: 3,
            offset: 0
        )
        let model = FollowingPinsModel(
            username: "viewer",
            provider: FollowingPinsFixtureProvider(results: [.success(source)]),
            cache: EntityDetailCache(),
            pageSize: 25
        )

        await model.load()

        XCTAssertEqual(model.pins.map(\.username), ["Owner", "AnotherOwner"])
    }

    func testEmptyFirstPageIsAReadyEmptyState() async {
        let provider = FollowingPinsFixtureProvider(results: [
            .success(.init(username: "viewer", pins: [], serverCount: 0, offset: 0))
        ])
        let model = FollowingPinsModel(username: "viewer", provider: provider, cache: EntityDetailCache())

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.pins.isEmpty)
        XCTAssertFalse(model.hasMore)
    }

    func testCancelledLoadCanRestartAndLateResultCannotReplaceTheNewPage() async {
        let provider = ControlledFollowingPinsProvider()
        let model = FollowingPinsModel(username: "viewer", provider: provider, cache: EntityDetailCache())

        let first = Task { await model.load() }
        while await provider.callCount() < 1 { await Task.yield() }
        model.cancel()

        let second = Task { await model.load() }
        while await provider.callCount() < 2 { await Task.yield() }
        await provider.resolve(call: 1, with: .init(
            username: "viewer",
            pins: [pin(2, "new")],
            serverCount: 1,
            offset: 0
        ))
        await second.value
        XCTAssertEqual(model.pins.map(\.rowID), [2])

        await provider.resolve(call: 0, with: .init(
            username: "viewer",
            pins: [pin(1, "late")],
            serverCount: 1,
            offset: 0
        ))
        await first.value
        XCTAssertEqual(model.pins.map(\.rowID), [2])
    }

    func testStaleContentSurvivesRefreshFailure() async {
        let cache = EntityDetailCache<FollowingPinsPageKey, FollowingPinsPage>(timeToLive: -1)
        await cache.save(page(offset: 0, count: 1), for: .init(username: "viewer", count: 25, offset: 0))
        let provider = FollowingPinsFixtureProvider(results: [.failure])
        let model = FollowingPinsModel(username: "viewer", provider: provider, cache: cache)
        await model.load()
        XCTAssertEqual(model.pins.count, 1)
        XCTAssertEqual(model.refreshMessage, "Couldn’t refresh. Showing saved pins.")
    }
}

@MainActor
final class FollowingPinsProviderTests: XCTestCase {
    func testExactPublicPageReadCoalescesAndKeepsWireUsername() async throws {
        let transport = FollowingPinsTransportFixture(response: rawPage())
        let provider = ListenBrainzFollowingPinsProvider(gate: RequestGate(minimumInterval: .zero)) { user, _, _ in
            XCTAssertEqual(user, "Viewer Name")
            return try await transport.value(user: user, count: 25, offset: 0)
        }
        async let one = provider.page(username: "Viewer Name", count: 25, offset: 0)
        async let two = provider.page(username: "Viewer Name", count: 25, offset: 0)
        let pages = try await [one, two]
        XCTAssertEqual(pages.map(\.pins.count), [1, 1])
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testDifferentOffsetsDoNotCoalesceAndWireBoundsAreApplied() async throws {
        let transport = FollowingPinsTransportFixture(response: rawPage())
        let provider = ListenBrainzFollowingPinsProvider(gate: RequestGate(minimumInterval: .zero)) { user, count, offset in
            try await transport.value(user: user, count: count, offset: offset)
        }

        async let first = provider.page(username: "Viewer", count: 2_000, offset: -4)
        async let second = provider.page(username: "Viewer", count: 25, offset: 25)
        let pages = try await [first, second]

        let requests = await transport.requests()
        XCTAssertEqual(Set(requests), Set([
            .init(user: "Viewer", count: 1_000, offset: 0),
            .init(user: "Viewer", count: 25, offset: 25),
        ]))
        XCTAssertEqual(Set(pages.map(\.offset)), Set([0, 25]))
    }
}

private actor FollowingPinsFixtureProvider: FollowingPinsProviding {
    enum Result: Sendable { case success(FollowingPinsPage), failure }
    private var calls = 0
    private var requestedOffsets: [Int] = []
    private let results: [Result]
    init(results: [Result]) { self.results = results }
    func page(username: String, count: Int, offset: Int) async throws -> FollowingPinsPage {
        requestedOffsets.append(offset)
        let index = calls; calls += 1
        switch results.indices.contains(index) ? results[index] : results.last ?? .failure {
        case let .success(value): return value
        case .failure: throw FollowingPinsFixtureError.failed
        }
    }
    func callCount() -> Int { calls }
    func offsets() -> [Int] { requestedOffsets }
}

private actor FollowingPinsTransportFixture {
    struct Request: Hashable {
        let user: String
        let count: Int
        let offset: Int
    }

    let response: LBFollowingPinsPage
    var calls = 0
    var recordedRequests: [Request] = []
    init(response: LBFollowingPinsPage) { self.response = response }
    func value(user: String, count: Int, offset: Int) async throws -> LBFollowingPinsPage {
        calls += 1
        recordedRequests.append(.init(user: user, count: count, offset: offset))
        try await ContinuousClock().sleep(for: .milliseconds(25))
        return response
    }
    func callCount() -> Int { calls }
    func requests() -> [Request] { recordedRequests }
}

private actor ControlledFollowingPinsProvider: FollowingPinsProviding {
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<FollowingPinsPage, Never>] = [:]

    func page(username: String, count: Int, offset: Int) async throws -> FollowingPinsPage {
        let call = calls
        calls += 1
        return await withCheckedContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func callCount() -> Int { calls }

    func resolve(call: Int, with page: FollowingPinsPage) {
        continuations.removeValue(forKey: call)?.resume(returning: page)
    }
}

private enum FollowingPinsFixtureError: LocalizedError {
    case failed
    var errorDescription: String? { "Fixture request failed." }
}

private func pin(_ id: Int, _ owner: String) -> PinnedRecording {
    .init(rowID: id, created: .now, pinnedUntil: nil, blurb: nil, username: owner, recording: .init(identity: .init(mbid: nil, msid: nil), title: "Track", artistName: "Artist", artistMBIDs: [], releaseTitle: nil, releaseMBID: nil, releaseGroupMBID: nil, artworkReleaseMBID: nil, durationMilliseconds: nil, source: nil), isCurrent: true)
}

private func page(offset: Int, count: Int) -> FollowingPinsPage {
    .init(username: "viewer", pins: [pin(1, "owner")], serverCount: count, offset: offset)
}

private func rawPage() -> LBFollowingPinsPage {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .secondsSince1970
    return try! decoder.decode(LBFollowingPinsPage.self, from: Data("""
    {"pinned_recordings":[{"row_id":1,"created":1700000000,"user_name":"owner","track_metadata":{"artist_name":"Artist","track_name":"Track"}}],"count":1,"offset":0,"user_name":"viewer"}
    """.utf8))
}
