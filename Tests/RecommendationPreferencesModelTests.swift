import Foundation
import XCTest
import ListenBrainzKit
@testable import Brainz

@MainActor
final class RecommendationPreferencesModelTests: XCTestCase {
    func testUsesRawServerCountForOffsetAndDeduplicatesByEntityAndMBID() async throws {
        let shared = testUUID(1)
        let second = testUUID(2)
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [
            0: [.page(page(
                offset: 0,
                total: 30,
                items: [preference(.recording, shared), preference(.recording, shared), preference(.artist, second)]
            ))],
            3: [.page(page(offset: 3, total: 30, items: [preference(.release, shared)]))],
        ])
        let model = makeModel(provider: provider)

        await model.load()
        XCTAssertEqual(model.state.items.count, 2)
        XCTAssertEqual(model.state.nextOffset, 3)
        XCTAssertTrue(model.state.hasMore)

        await model.loadMore()
        XCTAssertEqual(model.state.items.count, 3)
        XCTAssertEqual(model.state.nextOffset, 4)
        let offsets = await provider.offsets
        XCTAssertEqual(offsets, [0, 3])
    }

    func testFreshCacheSuppressesASecondRead() async {
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>(
            timeToLive: 600,
            maximumEntryCount: 10
        )
        let cachedPage = page(offset: 0, total: 1, items: [preference(.artist, testUUID(1))])
        let key = RecommendationPreferencesPageKey(username: "listener", offset: 0, count: 25)
        await cache.save(cachedPage, for: key)
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [:])
        let model = makeModel(provider: provider, cache: cache)

        await model.load()

        XCTAssertEqual(model.state.items, cachedPage.items)
        XCTAssertEqual(model.state.phase, .ready)
        let offsets = await provider.offsets
        XCTAssertEqual(offsets, [])
    }

    func testStaleCacheRemainsVisibleWhenRefreshFails() async {
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>(
            timeToLive: -1,
            maximumEntryCount: 10
        )
        let cachedPage = page(offset: 0, total: 1, items: [preference(.recording, testUUID(1))])
        let key = RecommendationPreferencesPageKey(username: "listener", offset: 0, count: 25)
        await cache.save(cachedPage, for: key)
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [
            0: [.failure(.readUnavailable)],
        ])
        let model = makeModel(provider: provider, cache: cache)

        await model.load()

        XCTAssertEqual(model.state.items, cachedPage.items)
        XCTAssertEqual(model.state.phase, .ready)
        XCTAssertEqual(model.state.refreshMessage, "Couldn’t refresh. Showing saved preferences.")
        let offsets = await provider.offsets
        XCTAssertEqual(offsets, [0])
    }

    func testLoadMoreFailureKeepsRowsAndExplicitRetryAdvances() async {
        let first = page(
            offset: 0,
            total: 3,
            items: [preference(.artist, testUUID(1)), preference(.recording, testUUID(2))]
        )
        let final = page(offset: 2, total: 3, items: [preference(.releaseGroup, testUUID(3))])
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [
            0: [.page(first)],
            2: [.failure(.readUnavailable), .page(final)],
        ])
        let model = makeModel(provider: provider)

        await model.load()
        await model.loadMore()
        XCTAssertEqual(model.state.items.count, 2)
        XCTAssertNotNil(model.state.loadMoreError)
        XCTAssertTrue(model.state.hasMore)

        await model.loadMore()
        XCTAssertEqual(model.state.items.count, 3)
        XCTAssertNil(model.state.loadMoreError)
        XCTAssertFalse(model.state.hasMore)
        let offsets = await provider.offsets
        XCTAssertEqual(offsets, [0, 2, 2])
    }

    func testDuplicatePagesStopAtTenServerPages() async {
        let duplicate = preference(.recording, testUUID(1))
        var results: [Int: [RecommendationPreferencesFixtureProvider.ReadResult]] = [:]
        for index in 0..<RecommendationPreferencesModel.maximumPageCount {
            let offset = index * 25
            results[offset] = [.page(page(
                offset: offset,
                total: 275,
                items: Array(repeating: duplicate, count: 25)
            ))]
        }
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: results)
        let model = makeModel(provider: provider)

        await model.load()
        for _ in 1..<RecommendationPreferencesModel.maximumPageCount { await model.loadMore() }
        await model.loadMore()

        XCTAssertEqual(model.state.items, [duplicate])
        XCTAssertFalse(model.state.hasMore)
        let offsets = await provider.offsets
        XCTAssertEqual(offsets, Array(stride(from: 0, to: 250, by: 25)))
    }

    func testUniquePagesStopAtTwoHundredVisibleRows() async {
        var results: [Int: [RecommendationPreferencesFixtureProvider.ReadResult]] = [:]
        for pageIndex in 0..<8 {
            let offset = pageIndex * 25
            let items = (offset..<(offset + 25)).map { preference(.recording, testUUID($0 + 1)) }
            results[offset] = [.page(page(offset: offset, total: 225, items: items))]
        }
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: results)
        let model = makeModel(provider: provider)

        await model.load()
        for _ in 1..<8 { await model.loadMore() }
        await model.loadMore()

        XCTAssertEqual(model.state.items.count, RecommendationPreferencesModel.maximumVisibleCount)
        XCTAssertFalse(model.state.hasMore)
        let requestCount = await provider.offsets.count
        XCTAssertEqual(requestCount, 8)
    }

    func testRemovalUsesEntityAndIDThenInvalidatesLocalRowsWithoutRefresh() async throws {
        let id = testUUID(1)
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [
            0: [.page(page(offset: 0, total: 1, items: [preference(.releaseGroup, id)]))],
        ])
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let changes = RecommendationPreferenceChanges()
        let model = makeModel(provider: provider, cache: cache, changes: changes)
        await model.load()
        let item = try XCTUnwrap(model.state.items.first)

        let didRemove = await model.remove(item)

        XCTAssertTrue(didRemove)
        XCTAssertTrue(model.state.items.isEmpty)
        XCTAssertEqual(model.state.totalCount, 0)
        let removals = await provider.removals
        let offsets = await provider.offsets
        XCTAssertEqual(removals, [.init(entity: .releaseGroup, id: id)])
        XCTAssertEqual(offsets, [0])
        let cached = await cache.value(for: .init(username: "listener", offset: 0, count: 25))
        XCTAssertNil(cached)
        XCTAssertEqual(changes.event(for: "listener")?.revision, 2)
    }

    func testSecondRemovalCannotCancelOrOverlapFirstRemoval() async throws {
        let first = preference(.artist, testUUID(1))
        let second = preference(.recording, testUUID(2))
        let provider = RecommendationPreferencesFixtureProvider(
            resultsByOffset: [0: [.page(page(offset: 0, total: 2, items: [first, second]))]],
            blockedRemovals: true
        )
        let model = makeModel(provider: provider)
        await model.load()

        let firstTask = Task { await model.remove(first) }
        await provider.waitUntilRemovalCount(1)
        let secondResult = await model.remove(second)

        XCTAssertFalse(secondResult)
        let removalCount = await provider.removals.count
        let maximumConcurrentRemovals = await provider.maximumConcurrentRemovals
        XCTAssertEqual(removalCount, 1)
        XCTAssertEqual(maximumConcurrentRemovals, 1)

        await provider.releaseRemoval(1)
        let firstResult = await firstTask.value
        XCTAssertTrue(firstResult)
        XCTAssertEqual(model.state.items, [second])
        let removals = await provider.removals
        XCTAssertEqual(removals, [.init(entity: .artist, id: first.entityMBID)])
    }

    func testRefreshStartedBeforeRemovalCannotRestoreOrCacheRemovedRow() async throws {
        let item = preference(.recording, testUUID(1))
        let stalePage = page(offset: 0, total: 1, items: [item])
        let provider = RecommendationPreferencesFixtureProvider(
            resultsByOffset: [0: [.page(stalePage), .page(stalePage)]],
            blockedReadCalls: [2]
        )
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let model = makeModel(provider: provider, cache: cache)
        await model.load()

        let refreshTask = Task { await model.refresh() }
        await provider.waitUntilReadCount(2)
        let didRemove = await model.remove(item)
        XCTAssertTrue(didRemove)
        await provider.releaseRead(2)
        await refreshTask.value

        XCTAssertTrue(model.state.items.isEmpty)
        XCTAssertEqual(model.state.phase, .ready)
        let cached = await cache.value(for: .init(username: "listener", offset: 0, count: 25))
        XCTAssertNil(cached)
    }

    func testCancelledGenerationIgnoresLateInitialReadAndDoesNotCacheIt() async {
        let provider = RecommendationPreferencesFixtureProvider(
            resultsByOffset: [0: [.page(page(offset: 0, total: 1, items: [preference(.artist, testUUID(1))]))]],
            blockedReadCalls: [1]
        )
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let model = makeModel(provider: provider, cache: cache)

        let loadTask = Task { await model.load() }
        await provider.waitUntilReadCount(1)
        model.cancel()
        await provider.releaseRead(1)
        await loadTask.value

        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertTrue(model.state.items.isEmpty)
        let cached = await cache.value(for: .init(username: "listener", offset: 0, count: 25))
        XCTAssertNil(cached)
    }

    func testCancellationAfterConditionalCacheSaveRemovesOnlyItsOwnWrite() async {
        let item = preference(.artist, testUUID(1))
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [
            0: [.page(page(offset: 0, total: 1, items: [item]))],
        ])
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let barrier = RecommendationPreferencesPostSaveBarrier()
        let model = makeModel(
            provider: provider,
            cache: cache,
            afterConditionalCacheSave: { await barrier.suspend() }
        )

        let loadTask = Task { await model.load() }
        await barrier.waitUntilSuspended()
        model.cancel()
        await barrier.release()
        await loadTask.value

        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertTrue(model.state.items.isEmpty)
        let cached = await cache.value(for: .init(username: "listener", offset: 0, count: 25))
        XCTAssertNil(cached)
    }

    func testTaskCancellationAfterConditionalCacheSaveSettlesLoadingState() async {
        let item = preference(.artist, testUUID(1))
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [
            0: [.page(page(offset: 0, total: 1, items: [item]))],
        ])
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let barrier = RecommendationPreferencesPostSaveBarrier()
        let model = makeModel(
            provider: provider,
            cache: cache,
            afterConditionalCacheSave: { await barrier.suspend() }
        )

        let loadTask = Task { await model.load() }
        await barrier.waitUntilSuspended()
        loadTask.cancel()
        await barrier.release()
        await loadTask.value

        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertTrue(model.state.items.isEmpty)
        let cached = await cache.value(for: .init(username: "listener", offset: 0, count: 25))
        XCTAssertNil(cached)
    }

    func testReceiptCleanupDoesNotInvalidateAnotherModelsConcurrentRead() async {
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let firstProvider = RecommendationPreferencesFixtureProvider(resultsByOffset: [
            0: [.page(page(offset: 0, total: 1, items: [preference(.artist, testUUID(1))]))],
        ])
        let secondItem = preference(.recording, testUUID(2))
        let secondProvider = RecommendationPreferencesFixtureProvider(
            resultsByOffset: [
                0: [.page(page(offset: 0, total: 1, items: [secondItem]))],
            ],
            blockedReadCalls: [1]
        )
        let postSaveBarrier = RecommendationPreferencesPostSaveBarrier()
        let firstModel = makeModel(
            provider: firstProvider,
            cache: cache,
            pageSize: 25,
            afterConditionalCacheSave: { await postSaveBarrier.suspend() }
        )
        let secondModel = makeModel(
            provider: secondProvider,
            cache: cache,
            pageSize: 24
        )

        let secondLoad = Task { await secondModel.load() }
        await secondProvider.waitUntilReadCount(1)

        let firstLoad = Task { await firstModel.load() }
        await postSaveBarrier.waitUntilSuspended()
        firstModel.cancel()
        await postSaveBarrier.release()
        await firstLoad.value

        await secondProvider.releaseRead(1)
        await secondLoad.value

        XCTAssertEqual(firstModel.state.phase, .idle)
        XCTAssertEqual(secondModel.state.phase, .ready)
        XCTAssertEqual(secondModel.state.items, [secondItem])
        XCTAssertNil(secondModel.state.refreshMessage)
        let cached = await cache.value(for: .init(username: "listener", offset: 0, count: 24))
        XCTAssertEqual(cached?.value.items, [secondItem])
    }

    func testConfirmedMutationMarksAnotherLoadedModelStale() async throws {
        let item = preference(.recording, testUUID(1))
        let stalePage = page(offset: 0, total: 1, items: [item])
        let provider = RecommendationPreferencesFixtureProvider(
            resultsByOffset: [0: [.page(stalePage), .page(stalePage)]],
            blockedRemovals: true
        )
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let changes = RecommendationPreferenceChanges()
        let listModel = makeModel(provider: provider, cache: cache, changes: changes)
        await listModel.load()

        let recordingModel = DoNotRecommendModel(
            account: Account(username: "listener", token: "token"),
            recordingMBID: item.entityMBID,
            provider: provider,
            preferenceCache: cache,
            changes: changes
        )
        let removalTask = Task { await recordingModel.removePreference() }
        await provider.waitUntilRemovalCount(1)

        let attemptEvent = try XCTUnwrap(changes.event(for: "listener"))
        listModel.observeExternalChange(attemptEvent)
        XCTAssertEqual(
            listModel.state.refreshMessage,
            "A preference update may have changed this list. Refresh to check."
        )

        await listModel.refresh()
        XCTAssertEqual(listModel.state.items, [item])
        XCTAssertNil(listModel.state.refreshMessage)

        await provider.releaseRemoval(1)
        let didRemove = await removalTask.value
        XCTAssertTrue(didRemove)
        let confirmedEvent = try XCTUnwrap(changes.event(for: "listener"))
        XCTAssertGreaterThan(confirmedEvent.revision, attemptEvent.revision)
        listModel.observeExternalChange(confirmedEvent)

        XCTAssertEqual(listModel.state.items, [item])
        XCTAssertEqual(listModel.state.phase, .ready)
        XCTAssertEqual(
            listModel.state.refreshMessage,
            "A preference update may have changed this list. Refresh to check."
        )
        let cached = await cache.value(for: .init(username: "listener", offset: 0, count: 25))
        XCTAssertNil(cached)
    }

    func testCancelledMutationAttemptMarksAnotherLoadedModelStale() async throws {
        let item = preference(.recording, testUUID(1))
        let page = page(offset: 0, total: 1, items: [item])
        let provider = RecommendationPreferencesFixtureProvider(
            resultsByOffset: [0: [.page(page)]],
            blockedRemovals: true
        )
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let changes = RecommendationPreferenceChanges()
        let staleModel = makeModel(provider: provider, cache: cache, changes: changes)
        let mutatingModel = makeModel(provider: provider, cache: cache, changes: changes)
        await staleModel.load()

        let removalTask = Task { await mutatingModel.remove(item) }
        await provider.waitUntilRemovalCount(1)

        let event = try XCTUnwrap(changes.event(for: "listener"))
        staleModel.observeExternalChange(event)
        XCTAssertEqual(staleModel.state.items, [item])
        XCTAssertEqual(staleModel.state.phase, .ready)
        XCTAssertEqual(
            staleModel.state.refreshMessage,
            "A preference update may have changed this list. Refresh to check."
        )

        removalTask.cancel()
        await provider.releaseRemoval(1)
        let didRemove = await removalTask.value

        XCTAssertFalse(didRemove)
        XCTAssertEqual(staleModel.state.items, [item])
        let cached = await cache.value(for: .init(username: "listener", offset: 0, count: 25))
        XCTAssertNil(cached)
    }

    func testRecordingWritesInvalidateFreshPreferencePages() async {
        let cache = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>()
        let key = RecommendationPreferencesPageKey(username: "listener", offset: 0, count: 25)
        let cachedPage = page(offset: 0, total: 1, items: [preference(.recording, testUUID(1))])
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [:])
        let model = DoNotRecommendModel(
            account: Account(username: "listener", token: "token"),
            recordingMBID: testUUID(2),
            provider: provider,
            preferenceCache: cache,
            changes: RecommendationPreferenceChanges()
        )

        await cache.save(cachedPage, for: key)
        let didSave = await model.savePreference()
        XCTAssertTrue(didSave)
        let afterSave = await cache.value(for: key)
        XCTAssertNil(afterSave)

        await cache.save(cachedPage, for: key)
        let didRemove = await model.removePreference()
        XCTAssertTrue(didRemove)
        let afterRemove = await cache.value(for: key)
        XCTAssertNil(afterRemove)
    }

    func testDurationComputesExactUTCSecondIntervals() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(RecommendationPreferenceDuration.permanent.expiration(from: start))
        XCTAssertEqual(RecommendationPreferenceDuration.sevenDays.expiration(from: start), start.addingTimeInterval(604_800))
        XCTAssertEqual(RecommendationPreferenceDuration.thirtyDays.expiration(from: start), start.addingTimeInterval(2_592_000))
    }

    func testRecordingSavePassesChosenExpiry() async {
        let provider = RecommendationPreferencesFixtureProvider(resultsByOffset: [:])
        let model = DoNotRecommendModel(
            account: Account(username: "listener", token: "token"),
            recordingMBID: testUUID(1),
            provider: provider,
            preferenceCache: EntityDetailCache(),
            changes: RecommendationPreferenceChanges()
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let didSave = await model.savePreference(duration: .sevenDays, now: now)
        let expiration = await provider.additions.first?.until
        XCTAssertTrue(didSave)
        XCTAssertEqual(expiration, now.addingTimeInterval(604_800))
    }

    func testProviderRejectsOverflowingOrMismatchedReadEnvelopes() {
        let row = LBDoNotRecommendEntry(
            entity: .recording,
            entityMBID: testUUID(1),
            until: nil,
            created: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let overflow = LBDoNotRecommendPage(
            entries: [row], totalCount: Int.max, count: 1, offset: Int.max, userID: "listener"
        )
        XCTAssertThrowsError(try ListenBrainzDoNotRecommendProvider.validatedPage(
            overflow,
            requestedUsername: "listener",
            requestedOffset: Int.max,
            requestedCount: 25
        )) { error in
            XCTAssertEqual(error as? DoNotRecommendProviderError, .invalidReadResponse)
        }

        let wrongUser = LBDoNotRecommendPage(
            entries: [row], totalCount: 1, count: 1, offset: 0, userID: "another-user"
        )
        XCTAssertThrowsError(try ListenBrainzDoNotRecommendProvider.validatedPage(
            wrongUser,
            requestedUsername: "listener",
            requestedOffset: 0,
            requestedCount: 25
        ))

        let wrongCount = LBDoNotRecommendPage(
            entries: [row], totalCount: 1, count: 2, offset: 0, userID: "listener"
        )
        XCTAssertThrowsError(try ListenBrainzDoNotRecommendProvider.validatedPage(
            wrongCount,
            requestedUsername: "listener",
            requestedOffset: 0,
            requestedCount: 25
        ))

        let contradictoryTotal = LBDoNotRecommendPage(
            entries: [row], totalCount: 0, count: 1, offset: 0, userID: "listener"
        )
        XCTAssertThrowsError(try ListenBrainzDoNotRecommendProvider.validatedPage(
            contradictoryTotal,
            requestedUsername: "listener",
            requestedOffset: 0,
            requestedCount: 25
        )) { error in
            XCTAssertEqual(error as? DoNotRecommendProviderError, .invalidReadResponse)
        }
    }

    private func makeModel(
        provider: RecommendationPreferencesFixtureProvider,
        cache: EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage> = EntityDetailCache(),
        pageSize: Int = 25,
        changes: RecommendationPreferenceChanges = RecommendationPreferenceChanges(),
        afterConditionalCacheSave: (@Sendable () async -> Void)? = nil
    ) -> RecommendationPreferencesModel {
        RecommendationPreferencesModel(
            account: Account(username: "listener", token: "token"),
            provider: provider,
            cache: cache,
            pageSize: pageSize,
            changes: changes,
            afterConditionalCacheSave: afterConditionalCacheSave
        )
    }
}

private actor RecommendationPreferencesPostSaveBarrier {
    private var isSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        isSuspended = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilSuspended() async {
        while !isSuspended { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor RecommendationPreferencesFixtureProvider: DoNotRecommendProviding {
    enum ReadResult: Sendable {
        case page(RecommendationPreferencePage)
        case failure(DoNotRecommendProviderError)
    }

    struct Removal: Equatable, Sendable {
        let entity: RecommendationPreferenceEntity
        let id: UUID
    }

    private var resultsByOffset: [Int: [ReadResult]]
    private let blockedReadCalls: Set<Int>
    private let blockedRemovals: Bool
    private var readContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var removalContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var activeRemovals = 0

    private(set) var offsets: [Int] = []
    private(set) var removals: [Removal] = []
    private(set) var maximumConcurrentRemovals = 0
    private(set) var additions: [(entity: RecommendationPreferenceEntity, id: UUID, until: Date?)] = []

    init(
        resultsByOffset: [Int: [ReadResult]],
        blockedReadCalls: Set<Int> = [],
        blockedRemovals: Bool = false
    ) {
        self.resultsByOffset = resultsByOffset
        self.blockedReadCalls = blockedReadCalls
        self.blockedRemovals = blockedRemovals
    }

    func entries(username: String, offset: Int, count: Int) async throws -> RecommendationPreferencePage {
        offsets.append(offset)
        let call = offsets.count
        if blockedReadCalls.contains(call) {
            await withCheckedContinuation { readContinuations[call] = $0 }
        }
        try Task.checkCancellation()

        var results = resultsByOffset[offset] ?? []
        let result = results.isEmpty
            ? ReadResult.page(.init(username: username, items: [], serverCount: 0, offset: offset, totalCount: 0))
            : results.removeFirst()
        resultsByOffset[offset] = results
        switch result {
        case let .page(page): return page
        case let .failure(error): throw error
        }
    }

    func add(entity: RecommendationPreferenceEntity, entityMBID: UUID, until: Date?) async throws {
        additions.append((entity, entityMBID, until))
    }

    func remove(entity: RecommendationPreferenceEntity, entityMBID: UUID) async throws {
        removals.append(.init(entity: entity, id: entityMBID))
        let sequence = removals.count
        activeRemovals += 1
        maximumConcurrentRemovals = max(maximumConcurrentRemovals, activeRemovals)
        defer { activeRemovals -= 1 }
        if blockedRemovals {
            await withCheckedContinuation { removalContinuations[sequence] = $0 }
        }
        try Task.checkCancellation()
    }

    func waitUntilReadCount(_ count: Int) async {
        while offsets.count < count { await Task.yield() }
    }

    func releaseRead(_ call: Int) {
        readContinuations.removeValue(forKey: call)?.resume()
    }

    func waitUntilRemovalCount(_ count: Int) async {
        while removals.count < count { await Task.yield() }
    }

    func releaseRemoval(_ sequence: Int) {
        removalContinuations.removeValue(forKey: sequence)?.resume()
    }
}

private func preference(
    _ entity: RecommendationPreferenceEntity,
    _ id: UUID,
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    expiresAt: Date? = nil
) -> RecommendationPreference {
    .init(entity: entity, entityMBID: id, createdAt: createdAt, expiresAt: expiresAt)
}

private func page(
    username: String = "listener",
    offset: Int,
    total: Int,
    items: [RecommendationPreference]
) -> RecommendationPreferencePage {
    .init(username: username, items: items, serverCount: items.count, offset: offset, totalCount: total)
}

private func testUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
}
