import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class ProfileFeedbackModelTests: XCTestCase {
    func testSelectedCategoryLoadsWithoutPreloadingTheOtherCategory() async {
        let provider = ProfileFeedbackFixtureProvider(results: [
            .success(page(.loved, offset: 0, serverCount: 1, totalCount: 1, items: [item(1, .loved)])),
            .success(page(.hated, offset: 0, serverCount: 1, totalCount: 1, items: [item(2, .hated)])),
        ])
        let model = ProfileFeedbackModel(
            username: "listener",
            provider: provider,
            cache: EntityDetailCache()
        )

        await model.load(category: .loved)

        XCTAssertEqual(model.state(for: .loved).items.map(\.category), [.loved])
        XCTAssertEqual(model.state(for: .hated).phase, .idle)
        let categoriesAfterLoved = await provider.categories()
        XCTAssertEqual(categoriesAfterLoved, [.loved])

        await model.load(category: .hated)

        XCTAssertEqual(model.state(for: .hated).items.map(\.category), [.hated])
        let categoriesAfterHated = await provider.categories()
        XCTAssertEqual(categoriesAfterHated, [.loved, .hated])
    }

    func testFreshPageCacheAvoidsASecondRead() async {
        let cache = EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage>()
        let provider = ProfileFeedbackFixtureProvider(results: [
            .success(page(.loved, offset: 0, serverCount: 1, totalCount: 1, items: [item(1, .loved)])),
        ])
        let first = ProfileFeedbackModel(username: "listener", provider: provider, cache: cache)
        let second = ProfileFeedbackModel(username: "listener", provider: provider, cache: cache)

        await first.load(category: .loved)
        await second.load(category: .loved)

        XCTAssertEqual(second.state(for: .loved).items.count, 1)
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testPaginationUsesServerCountAndDeduplicatesEitherIdentifier() async {
        let sharedMSID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let first = page(
            .loved,
            offset: 0,
            serverCount: 3,
            totalCount: 5,
            items: [
                item(1, .loved),
                item(2, .loved, msid: sharedMSID),
                item(20, .loved, msid: sharedMSID),
            ]
        )
        let second = page(
            .loved,
            offset: 3,
            serverCount: 2,
            totalCount: 5,
            items: [
                item(21, .loved, msid: sharedMSID),
                item(3, .loved),
            ]
        )
        let provider = ProfileFeedbackFixtureProvider(results: [.success(first), .success(second)])
        let model = ProfileFeedbackModel(
            username: "listener",
            provider: provider,
            cache: EntityDetailCache(),
            pageSize: 3
        )

        await model.load(category: .loved)
        XCTAssertEqual(model.state(for: .loved).items.count, 2)
        XCTAssertTrue(model.state(for: .loved).hasMore)

        await model.loadMore(category: .loved)

        let state = model.state(for: .loved)
        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.nextOffset, 5)
        XCTAssertEqual(state.totalCount, 5)
        XCTAssertFalse(state.hasMore)
        let offsets = await provider.offsets()
        XCTAssertEqual(offsets, [0, 3])
    }

    func testEmptyFirstPageBecomesReadyEmptyState() async {
        let model = ProfileFeedbackModel(
            username: "listener",
            provider: ProfileFeedbackFixtureProvider(results: [
                .success(page(.loved, offset: 0, serverCount: 0, totalCount: 0, items: [])),
            ]),
            cache: EntityDetailCache()
        )

        await model.load(category: .loved)

        XCTAssertEqual(model.state(for: .loved).phase, .ready)
        XCTAssertTrue(model.state(for: .loved).items.isEmpty)
        XCTAssertFalse(model.state(for: .loved).hasMore)
    }

    func testLoadMoreFailureKeepsLoadedRowsAndOffersTheSameOffsetAgain() async {
        let provider = ProfileFeedbackFixtureProvider(results: [
            .success(page(.loved, offset: 0, serverCount: 1, totalCount: 2, items: [item(1, .loved)])),
            .failure,
            .success(page(.loved, offset: 1, serverCount: 1, totalCount: 2, items: [item(2, .loved)])),
        ])
        let model = ProfileFeedbackModel(
            username: "listener",
            provider: provider,
            cache: EntityDetailCache(),
            pageSize: 1
        )

        await model.load(category: .loved)
        await model.loadMore(category: .loved)

        XCTAssertEqual(model.state(for: .loved).items.count, 1)
        XCTAssertNotNil(model.state(for: .loved).loadMoreError)
        XCTAssertTrue(model.state(for: .loved).hasMore)

        await model.loadMore(category: .loved)

        XCTAssertEqual(model.state(for: .loved).items.count, 2)
        XCTAssertNil(model.state(for: .loved).loadMoreError)
        let offsets = await provider.offsets()
        XCTAssertEqual(offsets, [0, 1, 1])
    }

    func testStaleCachedRowsSurviveRefreshFailure() async {
        let cache = EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage>(timeToLive: -1)
        let cached = page(.loved, offset: 0, serverCount: 1, totalCount: 1, items: [item(1, .loved)])
        await cache.save(
            cached,
            for: .init(username: "listener", category: .loved, offset: 0, count: 25)
        )
        let model = ProfileFeedbackModel(
            username: "listener",
            provider: ProfileFeedbackFixtureProvider(results: [.failure]),
            cache: cache
        )

        await model.load(category: .loved)

        let state = model.state(for: .loved)
        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.refreshMessage, "Couldn’t refresh. Showing saved ratings.")
    }

    func testStaleCachedRowsStayVisibleWhileRefreshing() async {
        let cache = EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage>(timeToLive: -1)
        await cache.save(
            page(.loved, offset: 0, serverCount: 1, totalCount: 1, items: [item(1, .loved)]),
            for: .init(username: "listener", category: .loved, offset: 0, count: 25)
        )
        let provider = ControlledProfileFeedbackProvider()
        let model = ProfileFeedbackModel(
            username: "listener",
            provider: provider,
            cache: cache
        )

        let load = Task { await model.load(category: .loved) }
        while await provider.callCount() < 1 { await Task.yield() }

        XCTAssertEqual(model.state(for: .loved).items.map(\.recording.title), ["Track 1"])
        XCTAssertEqual(model.state(for: .loved).phase, .refreshing)

        await provider.resolve(
            call: 0,
            with: page(.loved, offset: 0, serverCount: 1, totalCount: 1, items: [item(2, .loved)])
        )
        await load.value
        XCTAssertEqual(model.state(for: .loved).items.map(\.recording.title), ["Track 2"])
        XCTAssertEqual(model.state(for: .loved).phase, .ready)
    }

    func testCancelledLoadCanRestartAndLateResultCannotReplaceNewPage() async {
        let provider = ControlledProfileFeedbackProvider()
        let model = ProfileFeedbackModel(
            username: "listener",
            provider: provider,
            cache: EntityDetailCache()
        )

        let first = Task { await model.load(category: .loved) }
        while await provider.callCount() < 1 { await Task.yield() }
        model.cancel(category: .loved)

        let second = Task { await model.load(category: .loved) }
        while await provider.callCount() < 2 { await Task.yield() }
        await provider.resolve(
            call: 1,
            with: page(.loved, offset: 0, serverCount: 1, totalCount: 1, items: [item(2, .loved)])
        )
        await second.value
        XCTAssertEqual(model.state(for: .loved).items.map(\.recording.title), ["Track 2"])

        await provider.resolve(
            call: 0,
            with: page(.loved, offset: 0, serverCount: 1, totalCount: 1, items: [item(1, .loved)])
        )
        await first.value
        XCTAssertEqual(model.state(for: .loved).items.map(\.recording.title), ["Track 2"])
    }
}

@MainActor
final class ProfileFeedbackProviderTests: XCTestCase {
    func testIdenticalPublicPagesCoalesceWithoutAViewerToken() async throws {
        let transport = ProfileFeedbackTransportFixture(response: rawFeedbackPage())
        let gate = RequestGate(minimumInterval: .zero)
        let first = ListenBrainzProfileFeedbackProvider(
            transport: transport,
            gate: gate,
            readScope: .anonymous
        )
        let second = ListenBrainzProfileFeedbackProvider(
            transport: transport,
            gate: gate,
            readScope: .anonymous
        )

        async let one = first.page(username: "Listener", category: .loved, offset: 0, count: 25)
        async let two = second.page(username: "Listener", category: .loved, offset: 0, count: 25)
        let pages = try await [one, two]

        XCTAssertEqual(pages.map(\.items.count), [2, 2])
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testScoreOffsetAndBoundsShapeDistinctRequests() async throws {
        let transport = ProfileFeedbackTransportFixture(response: rawFeedbackPage())
        let provider = ListenBrainzProfileFeedbackProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            readScope: .anonymous
        )

        async let loved = provider.page(username: "Listener", category: .loved, offset: -4, count: 2_000)
        async let hated = provider.page(username: "Listener", category: .hated, offset: 25, count: 25)
        _ = try await [loved, hated]

        let requests = await transport.requests()
        XCTAssertEqual(Set(requests), Set([
            .init(username: "Listener", score: .love, offset: 0, count: 1_000),
            .init(username: "Listener", score: .hate, offset: 25, count: 25),
        ]))
    }

    func testProviderKeepsMSIDOnlyRowsAndTopLevelMBIDWinsOverMetadata() async throws {
        let provider = ListenBrainzProfileFeedbackProvider(
            transport: ProfileFeedbackTransportFixture(response: rawFeedbackPage()),
            gate: RequestGate(minimumInterval: .zero)
        )

        let page = try await provider.page(
            username: "Listener",
            category: .loved,
            offset: 0,
            count: 25
        )

        let expectedTopLevel = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        XCTAssertEqual(page.serverCount, 3)
        XCTAssertEqual(page.totalCount, 3)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items.first?.recording.identity.mbid, expectedTopLevel)
        XCTAssertEqual(page.items.last?.recording.title, "Unknown recording")
        XCTAssertEqual(page.items.last?.recording.artistName, "Unknown artist")
        XCTAssertNil(page.items.last?.recording.identity.mbid)
        XCTAssertNotNil(page.items.last?.recording.identity.msid)
    }
}

private actor ProfileFeedbackFixtureProvider: ProfileFeedbackProviding {
    enum Result: Sendable {
        case success(ProfileFeedbackPage)
        case failure
    }

    private let results: [Result]
    private var calls: [(ProfileFeedbackCategory, Int)] = []

    init(results: [Result]) {
        self.results = results
    }

    func page(
        username: String,
        category: ProfileFeedbackCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfileFeedbackPage {
        let index = calls.count
        calls.append((category, offset))
        switch results.indices.contains(index) ? results[index] : results.last ?? .failure {
        case let .success(page): return page
        case .failure: throw ProfileFeedbackFixtureError.unavailable
        }
    }

    func callCount() -> Int { calls.count }
    func categories() -> [ProfileFeedbackCategory] { calls.map(\.0) }
    func offsets() -> [Int] { calls.map(\.1) }
}

private actor ControlledProfileFeedbackProvider: ProfileFeedbackProviding {
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<ProfileFeedbackPage, Never>] = [:]

    func page(
        username: String,
        category: ProfileFeedbackCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfileFeedbackPage {
        let call = calls
        calls += 1
        return await withCheckedContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func callCount() -> Int { calls }

    func resolve(call: Int, with page: ProfileFeedbackPage) {
        continuations.removeValue(forKey: call)?.resume(returning: page)
    }
}

private actor ProfileFeedbackTransportFixture: ProfileFeedbackTransport {
    struct Request: Hashable, Sendable {
        let username: String
        let score: LBScore
        let offset: Int
        let count: Int
    }

    private let response: LBFeedbackPage
    private var recordedRequests: [Request] = []

    init(response: LBFeedbackPage) {
        self.response = response
    }

    func page(
        username: String,
        score: LBScore,
        offset: Int,
        count: Int
    ) async throws -> LBFeedbackPage {
        recordedRequests.append(.init(username: username, score: score, offset: offset, count: count))
        try await ContinuousClock().sleep(for: .milliseconds(25))
        return response
    }

    func callCount() -> Int { recordedRequests.count }
    func requests() -> [Request] { recordedRequests }
}

private enum ProfileFeedbackFixtureError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Fixture request failed."
    }
}

private func page(
    _ category: ProfileFeedbackCategory,
    offset: Int,
    serverCount: Int,
    totalCount: Int,
    items: [ProfileFeedbackItem]
) -> ProfileFeedbackPage {
    .init(
        username: "listener",
        category: category,
        items: items,
        serverCount: serverCount,
        offset: offset,
        totalCount: totalCount
    )
}

private func item(
    _ seed: Int,
    _ category: ProfileFeedbackCategory,
    msid: UUID? = nil
) -> ProfileFeedbackItem {
    let suffix = String(format: "%012d", seed)
    let mbid = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    return ProfileFeedbackItem(
        id: .mbid(mbid),
        recording: Recording(
            identity: .init(mbid: mbid, msid: msid),
            title: "Track \(seed)",
            artistName: "Artist \(seed)",
            artistMBIDs: [],
            releaseTitle: nil,
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: nil,
            source: nil
        ),
        createdAt: .now,
        category: category
    )
}

private func rawFeedbackPage() -> LBFeedbackPage {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .secondsSince1970
    return try! decoder.decode(
        LBFeedbackPage.self,
        from: Data(
            """
            {
              "count": 3,
              "offset": 0,
              "total_count": 3,
              "feedback": [
                {
                  "created": 1736100000,
                  "recording_mbid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                  "recording_msid": "11111111-1111-1111-1111-111111111111",
                  "score": 1,
                  "user_id": "Listener",
                  "track_metadata": {
                    "artist_name": "Mapped Artist",
                    "track_name": "Mapped Track",
                    "mbid_mapping": {
                      "recording_mbid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                      "recording_name": "Mapped Track"
                    }
                  }
                },
                {
                  "created": 1736000000,
                  "recording_msid": "22222222-2222-2222-2222-222222222222",
                  "score": 1,
                  "user_id": "Listener"
                },
                {
                  "created": 1735900000,
                  "recording_mbid": "cccccccc-cccc-cccc-cccc-cccccccccccc",
                  "score": -1,
                  "user_id": "Listener"
                }
              ]
            }
            """.utf8
        )
    )
}
