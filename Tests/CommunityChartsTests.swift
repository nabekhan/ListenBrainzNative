import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class CommunityChartsProviderTests: XCTestCase {
    func testExactSitewideQueryPreservesValidatedPagingMetadata() async throws {
        let response = transportPage(
            names: ["First", "Second"],
            requestedCount: 2,
            offset: 25,
            range: LBStatRange.month.rawValue,
            total: 30
        )
        let transport = CommunityChartsTransportFixture(outcomes: [.success(response)])
        let provider = ListenBrainzCommunityChartsProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )

        let page = try await provider.page(
            query: .init(kind: .artists, period: .lastMonth),
            offset: 25,
            limit: 2
        )

        XCTAssertEqual(page.items.map(\.title), ["First", "Second"])
        XCTAssertEqual(page.offset, 25)
        XCTAssertEqual(page.rawResultCount, 2)
        XCTAssertEqual(page.totalResultCount, 30)
        XCTAssertEqual(page.nextOffset, 27)
        let requests = await transport.requests()
        XCTAssertEqual(requests, [
            .init(kind: .artists, range: .month, offset: 25, count: 2),
        ])
    }

    func testNoContentBecomesAnEmptyTerminalPage() async throws {
        let transport = CommunityChartsTransportFixture(outcomes: [.success(.noContent())])
        let provider = ListenBrainzCommunityChartsProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )

        let page = try await provider.page(
            query: .init(kind: .recordings, period: .thisWeek),
            offset: 0,
            limit: 25
        )

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.totalResultCount, 0)
        XCTAssertNil(page.nextOffset)
    }

    func testIncompleteMetadataKeepsUsefulRowsButDisablesPagination() async throws {
        let response = transportPage(
            names: ["First"],
            requestedCount: nil,
            offset: 0,
            range: LBStatRange.thisWeek.rawValue,
            total: 10
        )
        let transport = CommunityChartsTransportFixture(outcomes: [.success(response)])
        let provider = ListenBrainzCommunityChartsProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )

        let page = try await provider.page(
            query: .init(kind: .artists, period: .thisWeek),
            offset: 0,
            limit: 1
        )

        XCTAssertEqual(page.items.map(\.title), ["First"])
        XCTAssertNil(page.nextOffset)
    }

    func testMismatchedRangeIsRejectedWithoutRetry() async {
        let response = transportPage(
            names: ["First"],
            requestedCount: 1,
            offset: 0,
            range: LBStatRange.year.rawValue,
            total: 1
        )
        let transport = CommunityChartsTransportFixture(outcomes: [.success(response)])
        let provider = ListenBrainzCommunityChartsProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )

        do {
            _ = try await provider.page(
                query: .init(kind: .artists, period: .thisWeek),
                offset: 0,
                limit: 1
            )
            XCTFail("Expected invalid metadata to fail")
        } catch CommunityChartsProviderError.invalidResponse {
            let callCount = await transport.callCount()
            XCTAssertEqual(callCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testZeroRowsCannotContradictAPositiveRemainingTotal() async {
        let response = transportPage(
            names: [],
            requestedCount: 25,
            offset: 0,
            range: LBStatRange.thisWeek.rawValue,
            total: 10
        )
        let transport = CommunityChartsTransportFixture(outcomes: [.success(response)])
        let provider = ListenBrainzCommunityChartsProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )

        do {
            _ = try await provider.page(
                query: .init(kind: .artists, period: .thisWeek),
                offset: 0,
                limit: 25
            )
            XCTFail("Expected contradictory pagination metadata to fail")
        } catch CommunityChartsProviderError.invalidResponse {
            let callCount = await transport.callCount()
            XCTAssertEqual(callCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExactConcurrentReadCoalescesThroughTheSharedGate() async throws {
        let response = transportPage(
            names: ["First"],
            requestedCount: 1,
            offset: 0,
            range: LBStatRange.thisWeek.rawValue,
            total: 1
        )
        let transport = CommunityChartsTransportFixture(
            outcomes: [.success(response)],
            delay: .milliseconds(30)
        )
        let provider = ListenBrainzCommunityChartsProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )
        let query = CommunityChartQuery(kind: .artists, period: .thisWeek)

        async let first = provider.page(query: query, offset: 0, limit: 1)
        async let duplicate = provider.page(query: query, offset: 0, limit: 1)
        _ = try await [first, duplicate]

        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }
}

@MainActor
final class CommunityChartsModelTests: XCTestCase {
    func testInitializationDoesNotRequestAnything() async {
        let provider = CommunityChartsFixtureProvider(outcomes: [])
        _ = CommunityChartsModel(provider: provider)

        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testOnlySelectedPageLoadsAndPagingRequiresExplicitAction() async {
        let provider = CommunityChartsFixtureProvider(outcomes: [
            .success(chartPage(names: ["First", "Second"], offset: 0, total: 4)),
            .success(chartPage(names: ["Third", "Fourth"], offset: 2, total: 4)),
        ])
        let model = CommunityChartsModel(provider: provider, pageSize: 2)

        await model.loadSelectedIfNeeded()

        XCTAssertEqual(model.items.map(\.title), ["First", "Second"])
        XCTAssertTrue(model.canLoadMore)
        var requests = await provider.requests()
        XCTAssertEqual(requests.map(\.offset), [0])

        await model.loadMore()

        XCTAssertEqual(model.items.map(\.title), ["First", "Second", "Third", "Fourth"])
        XCTAssertFalse(model.canLoadMore)
        requests = await provider.requests()
        XCTAssertEqual(requests.map(\.offset), [0, 2])
    }

    func testRawCursorAdvancesEvenWhenRowsAreDeduplicated() async {
        let provider = CommunityChartsFixtureProvider(outcomes: [
            .success(chartPage(names: ["First", "Second"], offset: 0, total: 4)),
            .success(chartPage(names: ["Second", "Third"], offset: 2, total: 4)),
        ])
        let model = CommunityChartsModel(provider: provider, pageSize: 2)

        await model.loadSelectedIfNeeded()
        await model.loadMore()

        XCTAssertEqual(model.items.map(\.title), ["First", "Second", "Third"])
        let requests = await provider.requests()
        XCTAssertEqual(requests.map(\.offset), [0, 2])
    }

    func testAppendFailureKeepsRowsAndRetriesTheExactPage() async {
        let provider = CommunityChartsFixtureProvider(outcomes: [
            .success(chartPage(names: ["First", "Second"], offset: 0, total: 4)),
            .failure,
            .success(chartPage(names: ["Third", "Fourth"], offset: 2, total: 4)),
        ])
        let model = CommunityChartsModel(provider: provider, pageSize: 2)

        await model.loadSelectedIfNeeded()
        await model.loadMore()

        XCTAssertEqual(model.items.map(\.title), ["First", "Second"])
        XCTAssertEqual(model.loadMoreError, "Fixture request failed.")
        XCTAssertTrue(model.canLoadMore)

        await model.loadMore()

        XCTAssertEqual(model.items.map(\.title), ["First", "Second", "Third", "Fourth"])
        XCTAssertNil(model.loadMoreError)
        let requests = await provider.requests()
        XCTAssertEqual(requests.map(\.offset), [0, 2, 2])
    }

    func testRetryRecoversAnInitialFailure() async {
        let provider = CommunityChartsFixtureProvider(outcomes: [
            .failure,
            .success(chartPage(names: ["Recovered"], offset: 0, total: 1)),
        ])
        let model = CommunityChartsModel(provider: provider, pageSize: 1)

        await model.loadSelectedIfNeeded()
        XCTAssertEqual(model.state, .failed("Fixture request failed."))

        await model.retry()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.items.map(\.title), ["Recovered"])
    }

    func testChangingKindLoadsOnlyTheNewSelection() async {
        let provider = CommunityChartsFixtureProvider(outcomes: [
            .success(chartPage(names: ["Artist"], offset: 0, total: 1)),
            .success(chartPage(
                items: [.releaseGroup(.init(
                    mbid: nil,
                    name: "Album",
                    artistName: "Artist",
                    artistMBIDs: [],
                    listenCount: 90
                ))],
                offset: 0,
                total: 1
            )),
        ])
        let model = CommunityChartsModel(provider: provider, pageSize: 1)

        await model.loadSelectedIfNeeded()
        model.select(kind: .releaseGroups)
        await model.loadSelectedIfNeeded()

        XCTAssertEqual(model.items.map(\.title), ["Album"])
        let requests = await provider.requests()
        XCTAssertEqual(requests.map(\.query.kind), [.artists, .releaseGroups])
    }

    func testFreshExactCacheAvoidsASecondProviderRead() async {
        let provider = CommunityChartsFixtureProvider(outcomes: [
            .success(chartPage(names: ["Cached"], offset: 0, total: 1)),
        ])
        let cache = EntityDetailCache<CommunityChartPageCacheKey, CommunityChartPage>()
        let first = CommunityChartsModel(provider: provider, cache: cache, pageSize: 1)
        let second = CommunityChartsModel(provider: provider, cache: cache, pageSize: 1)

        await first.loadSelectedIfNeeded()
        await second.loadSelectedIfNeeded()

        XCTAssertEqual(second.items.map(\.title), ["Cached"])
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testVisibleLimitStopsFurtherRequestsWithoutLosingTheRawCursor() async {
        let provider = CommunityChartsFixtureProvider(outcomes: [
            .success(chartPage(names: ["First", "Second"], offset: 0, total: 6)),
            .success(chartPage(names: ["Third", "Fourth"], offset: 2, total: 6)),
        ])
        let model = CommunityChartsModel(
            provider: provider,
            pageSize: 2,
            visibleLimit: 3
        )

        await model.loadSelectedIfNeeded()
        await model.loadMore()
        await model.loadMore()

        XCTAssertEqual(model.items.map(\.title), ["First", "Second", "Third"])
        XCTAssertTrue(model.hasReachedVisibleLimit)
        XCTAssertFalse(model.canLoadMore)
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testSelectionChangeCancelsTheOldResultBeforeItCanReplaceTheNewChart() async {
        let provider = DelayedCommunityChartsFixtureProvider()
        let model = CommunityChartsModel(provider: provider, pageSize: 1)

        let oldLoad = Task { await model.loadSelectedIfNeeded() }
        await provider.waitUntilArtistStarted()
        model.select(kind: .releaseGroups)
        await model.loadSelectedIfNeeded()
        await oldLoad.value

        XCTAssertEqual(model.kind, .releaseGroups)
        XCTAssertEqual(model.items.map(\.title), ["New album"])
        let requests = await provider.requests()
        XCTAssertEqual(Set(requests), Set([.artists, .releaseGroups]))
    }
}

private actor CommunityChartsTransportFixture: CommunityChartsTransport {
    struct Request: Equatable, Sendable {
        let kind: CommunityChartKind
        let range: LBStatRange
        let offset: Int
        let count: Int
    }

    enum Outcome: Sendable {
        case success(CommunityChartTransportPage)
        case failure
    }

    private let outcomes: [Outcome]
    private let delay: Duration
    private var recordedRequests: [Request] = []

    init(outcomes: [Outcome], delay: Duration = .zero) {
        self.outcomes = outcomes
        self.delay = delay
    }

    func page(
        kind: CommunityChartKind,
        range: LBStatRange,
        offset: Int,
        count: Int
    ) async throws -> CommunityChartTransportPage {
        let index = recordedRequests.count
        recordedRequests.append(.init(kind: kind, range: range, offset: offset, count: count))
        if delay > .zero {
            try await ContinuousClock().sleep(for: delay)
        }
        switch outcomes.indices.contains(index) ? outcomes[index] : outcomes.last ?? .failure {
        case let .success(value): return value
        case .failure: throw CommunityChartsFixtureError.failed
        }
    }

    func requests() -> [Request] { recordedRequests }
    func callCount() -> Int { recordedRequests.count }
}

private actor CommunityChartsFixtureProvider: CommunityChartsProviding {
    struct Request: Equatable, Sendable {
        let query: CommunityChartQuery
        let offset: Int
        let limit: Int
    }

    enum Outcome: Sendable {
        case success(CommunityChartPage)
        case failure
    }

    private let outcomes: [Outcome]
    private var recordedRequests: [Request] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func page(
        query: CommunityChartQuery,
        offset: Int,
        limit: Int
    ) async throws -> CommunityChartPage {
        let index = recordedRequests.count
        recordedRequests.append(.init(query: query, offset: offset, limit: limit))
        switch outcomes.indices.contains(index) ? outcomes[index] : outcomes.last ?? .failure {
        case let .success(value): return value
        case .failure: throw CommunityChartsFixtureError.failed
        }
    }

    func requests() -> [Request] { recordedRequests }
    func callCount() -> Int { recordedRequests.count }
}

private actor DelayedCommunityChartsFixtureProvider: CommunityChartsProviding {
    private var requestedKinds: [CommunityChartKind] = []
    private var artistStarted = false
    private var artistStartWaiters: [CheckedContinuation<Void, Never>] = []

    func page(
        query: CommunityChartQuery,
        offset: Int,
        limit _: Int
    ) async throws -> CommunityChartPage {
        requestedKinds.append(query.kind)
        switch query.kind {
        case .artists:
            artistStarted = true
            let waiters = artistStartWaiters
            artistStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            try await ContinuousClock().sleep(for: .milliseconds(100))
            return chartPage(names: ["Old artist"], offset: offset, total: 1)
        case .releaseGroups:
            return chartPage(
                items: [.releaseGroup(.init(
                    mbid: nil,
                    name: "New album",
                    artistName: "Current artist",
                    artistMBIDs: [],
                    listenCount: 20
                ))],
                offset: offset,
                total: 1
            )
        case .recordings:
            return chartPage(names: [], offset: offset, total: 0)
        }
    }

    func waitUntilArtistStarted() async {
        guard !artistStarted else { return }
        await withCheckedContinuation { continuation in
            artistStartWaiters.append(continuation)
        }
    }

    func requests() -> [CommunityChartKind] { requestedKinds }
}

private enum CommunityChartsFixtureError: LocalizedError {
    case failed
    var errorDescription: String? { "Fixture request failed." }
}

private func transportPage(
    names: [String],
    requestedCount: Int?,
    offset: Int?,
    range: String?,
    total: Int?
) -> CommunityChartTransportPage {
    .init(
        items: names.enumerated().map { index, name in
            .artist(.init(mbid: nil, name: name, listenCount: 100 - index))
        },
        rawResultCount: names.count,
        requestedCount: requestedCount,
        offset: offset,
        range: range,
        totalResultCount: total,
        lastUpdated: Date(timeIntervalSince1970: 100),
        isNoContent: false
    )
}

private func chartPage(
    names: [String],
    offset: Int,
    total: Int
) -> CommunityChartPage {
    chartPage(
        items: names.enumerated().map { index, name in
            .artist(.init(mbid: nil, name: name, listenCount: total * 100 - offset - index))
        },
        offset: offset,
        total: total
    )
}

private func chartPage(
    items: [CommunityChartItem],
    offset: Int,
    total: Int
) -> CommunityChartPage {
    .init(
        items: items,
        offset: offset,
        rawResultCount: items.count,
        totalResultCount: total,
        lastUpdated: Date(timeIntervalSince1970: 100),
        allowsPagination: true
    )
}
