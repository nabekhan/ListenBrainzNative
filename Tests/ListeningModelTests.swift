import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class ListeningModelTests: XCTestCase {
    func testLoadBuildsARealSnapshotFromProviderData() async {
        let provider = FixtureProvider()
        let username = "fixture-\(UUID().uuidString)"
        let model = ListeningModel(
            account: Account(username: username, token: ""),
            provider: provider
        )

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.snapshot.recentListens.count, 2)
        XCTAssertEqual(model.snapshot.playingNow?.recording.title, "Playing Now")
        XCTAssertEqual(model.snapshot.listenCount, 42)
        XCTAssertEqual(model.snapshot.topArtists.first?.name, "Fixture Artist")
        XCTAssertEqual(model.snapshot.topReleases.first?.name, "Fixture Album")
        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Fixture Track")
    }

    func testArtistFilteringUsesMBIDsBeforeDisplayNames() async {
        let provider = FixtureProvider()
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        await model.load()

        let artist = RankedArtist(
            mbid: FixtureProvider.artistMBID,
            name: "A different localized display name",
            listenCount: 2
        )

        XCTAssertEqual(model.listens(for: artist).count, 2)
        XCTAssertEqual(model.recordings(for: artist).count, 1)
    }

    func testRecordingIdentityPrefersMusicBrainzIDAndFallsBackToMSID() {
        let mbid = UUID()
        let msid = UUID()

        XCTAssertEqual(recording(mbid: mbid, msid: msid).id, "mbid:\(mbid.uuidString)")
        XCTAssertEqual(recording(mbid: nil, msid: msid).id, "msid:\(msid.uuidString)")
    }

    func testPaginationKeepsListensSharingTheBoundarySecond() async {
        let provider = BoundaryProvider()
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.load()
        await model.loadMore()

        XCTAssertEqual(model.snapshot.recentListens.count, 42)
        XCTAssertTrue(model.snapshot.recentListens.contains { $0.recording.title == "Boundary sibling" })
        XCTAssertTrue(model.snapshot.recentListens.contains { $0.recording.title == "Older listen" })
        XCTAssertFalse(model.canLoadMore)
        let requestedCount = await provider.requestedCount()
        XCTAssertEqual(requestedCount, 100)
        let requestedBefore = await provider.requestedBefore()
        XCTAssertEqual(requestedBefore?.timeIntervalSince1970, 1_901)
    }

    func testHistoryDayBoundsUseLocalCalendarArithmeticAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12))!
        let bounds = HistoryDayBounds(day: day, calendar: calendar)

        XCTAssertEqual(bounds.day, calendar.startOfDay(for: day))
        XCTAssertEqual(bounds.earliest.timeIntervalSince(bounds.day), -1)
        XCTAssertEqual(bounds.latest.timeIntervalSince(bounds.day), 23 * 60 * 60)
    }

    func testSelectedDayForwardsStrictDayBoundsWithoutChangingSnapshot() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let provider = DayHistoryProvider(mode: .singleDay)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        let listensBefore = model.snapshot.recentListens
        let savedAtBefore = model.snapshot.savedAt

        await model.selectHistoryDay(day, calendar: calendar)

        let request = await provider.requests().first
        XCTAssertEqual(request?.before, HistoryDayBounds(day: day, calendar: calendar).latest)
        XCTAssertEqual(request?.after, HistoryDayBounds(day: day, calendar: calendar).earliest)
        XCTAssertEqual(model.selectedDayListens.count, 1)
        XCTAssertEqual(model.snapshot.recentListens, listensBefore)
        XCTAssertEqual(model.snapshot.savedAt, savedAtBefore)
    }

    func testSelectedDayRefreshPreservesOriginalCalendarBounds() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let day = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let provider = DayHistoryProvider(mode: .singleDay)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)

        await model.selectHistoryDay(day, calendar: calendar)
        await model.refreshSelectedHistoryDay()

        let requests = await provider.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].before, requests[1].before)
        XCTAssertEqual(requests[0].after, requests[1].after)
    }

    func testCancellingCurrentDayLoadClearsLoadingWithoutShowingAnError() async throws {
        let provider = DayHistoryProvider(mode: .staleSelection)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        let task = Task { await model.selectHistoryDay(.now) }
        let clock = ContinuousClock()
        while await provider.requests().isEmpty {
            try await clock.sleep(for: .milliseconds(1))
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.isLoadingSelectedDay)
        XCTAssertNil(model.selectedDayError)
    }

    func testCancelledDayLoadThatReturnsNormallyStillClearsLoading() async throws {
        let provider = DayHistoryProvider(mode: .returnsAfterCancellation)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        let task = Task { await model.selectHistoryDay(.now) }
        let clock = ContinuousClock()
        while await provider.requests().isEmpty {
            try await clock.sleep(for: .milliseconds(1))
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.isLoadingSelectedDay)
        XCTAssertTrue(model.selectedDayListens.isEmpty)
        XCTAssertNil(model.selectedDayError)
    }

    func testCancelledDayLoadReportedAsURLErrorDoesNotBecomeFailure() async throws {
        let provider = DayHistoryProvider(mode: .urlCancellation)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        let task = Task { await model.selectHistoryDay(.now) }
        let clock = ContinuousClock()
        while await provider.requests().isEmpty {
            try await clock.sleep(for: .milliseconds(1))
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.isLoadingSelectedDay)
        XCTAssertNil(model.selectedDayError)
    }

    func testNewerDaySelectionSupersedesOlderResult() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let provider = DayHistoryProvider(mode: .staleSelection)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)

        async let first: Void = model.selectHistoryDay(firstDay)
        try? await ContinuousClock().sleep(for: .milliseconds(5))
        await model.selectHistoryDay(secondDay)
        await first

        XCTAssertEqual(model.selectedHistoryDay?.day, HistoryDayBounds(day: secondDay).day)
        XCTAssertEqual(model.selectedDayListens.first?.recording.title, "Newer day")
    }

    func testSelectedDayPaginationKeepsLowerBoundAndDistinctMSIDs() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let provider = DayHistoryProvider(mode: .boundarySiblings)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)

        await model.selectHistoryDay(day, calendar: calendar)
        await model.loadMoreSelectedHistoryDay()

        let bounds = HistoryDayBounds(day: day, calendar: calendar)
        let requests = await provider.requests()
        XCTAssertEqual(requests.last?.after, bounds.earliest)
        XCTAssertEqual(model.selectedDayListens.count, 102)
        XCTAssertEqual(Set(model.selectedDayListens.map(\.id)).count, 102)
        XCTAssertTrue(model.selectedDayListens.contains { $0.recording.identity.msid != nil })
    }

    func testSelectedDayStopsWhenAPageCannotAdvanceCursor() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let provider = DayHistoryProvider(mode: .repeatedCursor)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)

        await model.selectHistoryDay(day, calendar: calendar)
        await model.loadMoreSelectedHistoryDay()

        XCTAssertFalse(model.canLoadMoreSelectedDay)
    }

    func testSelectingAnotherDayResetsSupersededPaginationState() async throws {
        let provider = DayHistoryProvider(mode: .stalePagination)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        await model.selectHistoryDay(.now.addingTimeInterval(-86_400))
        let pagination = Task { await model.loadMoreSelectedHistoryDay() }
        let clock = ContinuousClock()
        while await provider.requests().count < 2 {
            try await clock.sleep(for: .milliseconds(1))
        }

        await model.selectHistoryDay(.now)
        await pagination.value

        XCTAssertFalse(model.isLoadingSelectedDay)
        XCTAssertFalse(model.isLoadingMoreSelectedDay)
        XCTAssertEqual(model.selectedDayListens.first?.recording.title, "Replacement day")
    }

    func testRecentHistoryStopsWhenAFullPageCannotAdvanceCursor() async {
        let provider = DayHistoryProvider(mode: .repeatedCursor)
        let model = ListeningModel(
            account: Account(username: "recent-repeat-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.load()
        await model.loadMore()

        XCTAssertFalse(model.canLoadMore)
        XCTAssertEqual(model.snapshot.recentListens.count, 100)
    }

    func testInvalidatedCacheLeaseRejectsLateWrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BrainzCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SnapshotCache(rootDirectory: root)
        let username = "lease-fixture"
        let firstLease = await cache.beginSession(username: username)

        await cache.save(.empty, username: username, lease: firstLease)
        let initialValue = await cache.load(username: username, lease: firstLease)
        XCTAssertNotNil(initialValue)

        try await cache.invalidate(username: username)
        await cache.save(.empty, username: username, lease: firstLease)
        let secondLease = await cache.beginSession(username: username)
        let valueAfterInvalidation = await cache.load(username: username, lease: secondLease)
        XCTAssertNil(valueAfterInvalidation)
    }

    func testListeningActivityUsesServerBucketsAndCachesEachPeriod() async {
        let provider = FixtureProvider()
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.loadListeningActivity(for: .thisMonth)
        await model.loadListeningActivity(for: .lastMonth)
        await model.loadListeningActivity(for: .thisMonth)

        guard case let .loaded(activity) = model.activityState(for: .thisMonth) else {
            return XCTFail("Expected This Month activity to load")
        }
        XCTAssertEqual(activity.totalListens, 15)
        XCTAssertEqual(activity.busiestBucket?.label, "Tuesday")
        XCTAssertEqual(activity.busiestBucket?.listenCount, 9)
        let thisMonthRequests = await provider.activityRequestCount(for: .thisMonth)
        let lastMonthRequests = await provider.activityRequestCount(for: .lastMonth)
        XCTAssertEqual(thisMonthRequests, 1)
        XCTAssertEqual(lastMonthRequests, 1)
    }

    func testListeningActivityPeriodMapsToListenBrainzRanges() {
        XCTAssertEqual(ListenBrainzProvider.range(for: .thisWeek).rawValue, "this_week")
        XCTAssertEqual(ListenBrainzProvider.range(for: .thisMonth).rawValue, "this_month")
        XCTAssertEqual(ListenBrainzProvider.range(for: .thisYear).rawValue, "this_year")
        XCTAssertEqual(ListenBrainzProvider.range(for: .lastWeek).rawValue, "week")
        XCTAssertEqual(ListenBrainzProvider.range(for: .lastMonth).rawValue, "month")
        XCTAssertEqual(ListenBrainzProvider.range(for: .lastYear).rawValue, "year")
        XCTAssertEqual(ListenBrainzProvider.range(for: .allTime).rawValue, "all_time")
    }

    func testCancelledActivityLoadReturnsToIdle() async throws {
        let provider = FixtureProvider(activityDelay: .seconds(1))
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let task = Task { await model.loadListeningActivity(for: .thisWeek) }
        let clock = ContinuousClock()
        while await provider.activityRequestCount(for: .thisWeek) == 0 {
            try await clock.sleep(for: .milliseconds(1))
        }

        task.cancel()
        await task.value

        XCTAssertEqual(model.activityState(for: .thisWeek), .idle)
    }

    func testReplacementActivityLoadSurvivesOlderCancellation() async throws {
        let provider = FixtureProvider(activityDelay: .milliseconds(80))
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let first = Task { await model.loadListeningActivity(for: .thisWeek) }
        let clock = ContinuousClock()
        while await provider.activityRequestCount(for: .thisWeek) < 1 {
            try await clock.sleep(for: .milliseconds(1))
        }

        let replacement = Task { await model.loadListeningActivity(for: .thisWeek) }
        while await provider.activityRequestCount(for: .thisWeek) < 2 {
            try await clock.sleep(for: .milliseconds(1))
        }
        first.cancel()

        await first.value
        await replacement.value

        guard case .loaded = model.activityState(for: .thisWeek) else {
            return XCTFail("Expected the replacement request to remain loaded")
        }
        let requestCount = await provider.activityRequestCount(for: .thisWeek)
        XCTAssertEqual(requestCount, 2)
    }

    func testRetryingLoadedActivityStartsANewRequest() async {
        let provider = FixtureProvider()
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.loadListeningActivity(for: .thisWeek)
        await model.loadListeningActivity(for: .thisWeek)
        let initialRequestCount = await provider.activityRequestCount(for: .thisWeek)
        XCTAssertEqual(initialRequestCount, 1)

        await model.loadListeningActivity(for: .thisWeek, retrying: true)
        let retryRequestCount = await provider.activityRequestCount(for: .thisWeek)
        XCTAssertEqual(retryRequestCount, 2)
    }

    func testDailyActivityNormalizesToACompleteUTCWeek() {
        let activity = DailyActivity(
            period: .thisWeek,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            dailyActivity: [
                "Monday": [
                    .init(hour: 0, listenCount: 2),
                    .init(hour: 0, listenCount: 3),
                    .init(hour: 24, listenCount: 99),
                    .init(hour: -1, listenCount: 99),
                    .init(hour: 3, listenCount: -8),
                ],
                "Sunday": [.init(hour: 23, listenCount: 7)],
            ]
        )

        XCTAssertEqual(activity.cells.count, 168)
        XCTAssertEqual(activity.cell(weekday: .monday, hour: 0)?.listenCount, 5)
        XCTAssertEqual(activity.cell(weekday: .monday, hour: 3)?.listenCount, 0)
        XCTAssertEqual(activity.cell(weekday: .tuesday, hour: 12)?.listenCount, 0)
        XCTAssertEqual(activity.cell(weekday: .sunday, hour: 23)?.listenCount, 7)
        XCTAssertNil(activity.cell(weekday: .monday, hour: 24))
    }

    func testDailyActivityDateRangeIsFormattedInUTC() {
        let activity = DailyActivity(
            period: .thisWeek,
            from: Date(timeIntervalSince1970: 1_735_689_600), // 2025-01-01 00:00 UTC
            to: Date(timeIntervalSince1970: 1_735_776_000),   // 2025-01-02 00:00 UTC
            lastUpdated: .distantPast,
            dailyActivity: [:]
        )

        XCTAssertEqual(
            TasteView.dailyActivityDateRange(activity, locale: Locale(identifier: "en_US_POSIX")),
            "Jan 1, 2025 – Jan 2, 2025 · UTC"
        )
    }

    func testDailyActivityCachesOneFreshRequestPerNormalizedUserAndPeriod() async {
        let cache = EntityDetailCache<DailyActivityCacheKey, DailyActivity>()
        let provider = DailyActivityProvider(result: .activity(listenCount: 4))
        let first = ListeningModel(
            account: Account(username: " Listener ", token: ""),
            provider: provider,
            dailyActivityCache: cache
        )

        await first.loadDailyActivity(for: .thisWeek)
        await first.loadDailyActivity(for: .thisWeek)
        let firstRequestCount = await provider.requestCount()
        XCTAssertEqual(firstRequestCount, 1)

        let sameUser = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            dailyActivityCache: cache
        )
        await sameUser.loadDailyActivity(for: .thisWeek)
        let sameUserRequestCount = await provider.requestCount()
        XCTAssertEqual(sameUserRequestCount, 1)

        let otherUser = ListeningModel(
            account: Account(username: "someone-else", token: ""),
            provider: provider,
            dailyActivityCache: cache
        )
        await otherUser.loadDailyActivity(for: .thisWeek)
        await otherUser.loadDailyActivity(for: .thisMonth)
        let isolatedRequestCount = await provider.requestCount()
        XCTAssertEqual(isolatedRequestCount, 3)
    }

    func testStaleDailyActivityStaysVisibleDuringRefreshAndOnFailure() async throws {
        let cache = EntityDetailCache<DailyActivityCacheKey, DailyActivity>(timeToLive: -1)
        let stale = DailyActivity.fixture(period: .thisWeek, listenCount: 3)
        await cache.save(stale, for: .init(username: "listener", period: .thisWeek))
        let provider = DailyActivityProvider(result: .failure, delay: .seconds(1))
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            dailyActivityCache: cache
        )

        let task = Task { await model.loadDailyActivity(for: .thisWeek) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        guard case let .loaded(visible) = model.dailyActivityState(for: .thisWeek) else {
            return XCTFail("Stale data should remain visible while refreshing")
        }
        XCTAssertEqual(visible.totalListens, stale.totalListens)

        await task.value
        guard case let .loaded(retained) = model.dailyActivityState(for: .thisWeek) else {
            return XCTFail("A refresh failure must not discard stale data")
        }
        XCTAssertEqual(retained.totalListens, stale.totalListens)
        XCTAssertNotNil(model.dailyActivityRefreshMessage(for: .thisWeek))
    }

    func testDailyActivityReplacementCannotBeOverwrittenByOlderRequest() async throws {
        let provider = DailyActivityProvider(
            results: [.activity(listenCount: 2), .activity(listenCount: 9)],
            delays: [.milliseconds(80), .milliseconds(1)],
            ignoresCancellation: true
        )
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            dailyActivityCache: EntityDetailCache()
        )

        let first = Task { await model.loadDailyActivity(for: .thisWeek) }
        while await provider.requestCount() < 1 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        let replacement = Task { await model.loadDailyActivity(for: .thisWeek, retrying: true) }
        await first.value
        await replacement.value

        guard case let .loaded(activity) = model.dailyActivityState(for: .thisWeek) else {
            return XCTFail("Expected replacement result")
        }
        XCTAssertEqual(activity.totalListens, 9)
    }

    func testDailyActivityNilAndAllZeroResponsesAreHonest() async {
        let noContent = DailyActivityProvider(result: .noContent)
        let noContentModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: noContent,
            dailyActivityCache: EntityDetailCache()
        )
        await noContentModel.loadDailyActivity(for: .thisWeek)
        XCTAssertEqual(noContentModel.dailyActivityState(for: .thisWeek), .unavailable)

        let zeros = DailyActivityProvider(result: .activity(listenCount: 0))
        let zeroModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: zeros,
            dailyActivityCache: EntityDetailCache()
        )
        await zeroModel.loadDailyActivity(for: .thisWeek)
        guard case let .loaded(activity) = zeroModel.dailyActivityState(for: .thisWeek) else {
            return XCTFail("Expected a loaded all-zero matrix")
        }
        XCTAssertTrue(activity.isEmpty)
    }

    func testEraActivityNormalizesYearsAndBuildsCompleteDecades() {
        let activity = EraActivity(
            period: .thisYear,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            years: [
                .init(year: 1997, listenCount: 4),
                .init(year: 1997, listenCount: 5),
                .init(year: 2011, listenCount: 7),
                .init(year: 2024, listenCount: 3),
                .init(year: 2025, listenCount: -8),
                .init(year: -1, listenCount: 99),
            ]
        )

        XCTAssertEqual(activity.years.map(\.year), [1997, 2011, 2024, 2025])
        XCTAssertEqual(activity.years.map(\.listenCount), [9, 7, 3, 0])
        XCTAssertEqual(activity.decades.map(\.year), [1990, 2000, 2010, 2020])
        XCTAssertEqual(activity.decades.map(\.listenCount), [9, 0, 7, 3])
        XCTAssertEqual(activity.leadingDecade?.year, 1990)
        XCTAssertEqual(activity.years(in: 1990).map(\.year), Array(1990 ... 1999))
        XCTAssertEqual(activity.years(in: 1990).first(where: { $0.year == 1997 })?.listenCount, 9)
        XCTAssertEqual(activity.totalListens, 19)
    }

    func testEraActivityRejectsUnboundedYearsAndBoundsSparseGapFilling() {
        let activity = EraActivity(
            period: .allTime,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            years: [
                .init(year: Int.min, listenCount: 1),
                .init(year: 0, listenCount: 2),
                .init(year: 1000, listenCount: 3),
                .init(year: 2024, listenCount: 4),
                .init(year: 9999, listenCount: 5),
                .init(year: Int.max, listenCount: 6),
            ]
        )

        XCTAssertEqual(activity.years.map(\.year), [1000, 2024, 9999])
        XCTAssertEqual(activity.decades.map(\.year), [1000, 2020, 9990])
        XCTAssertEqual(activity.decades.map(\.listenCount), [3, 4, 5])
        XCTAssertTrue(activity.years(in: Int.min).isEmpty)
        XCTAssertTrue(activity.years(in: Int.max).isEmpty)
    }

    func testEraActivityCachesOneFreshRequestPerNormalizedUserAndPeriod() async {
        let cache = EntityDetailCache<EraActivityCacheKey, EraActivity>()
        let provider = EraActivityProvider(result: .activity(year: 1997, listenCount: 4))
        let first = ListeningModel(
            account: Account(username: " Listener ", token: ""),
            provider: provider,
            eraActivityCache: cache
        )

        await first.loadEraActivity(for: .thisYear)
        await first.loadEraActivity(for: .thisYear)
        let firstRequestCount = await provider.requestCount()
        XCTAssertEqual(firstRequestCount, 1)

        let sameUser = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            eraActivityCache: cache
        )
        await sameUser.loadEraActivity(for: .thisYear)
        let sameUserRequestCount = await provider.requestCount()
        XCTAssertEqual(sameUserRequestCount, 1)

        let otherUser = ListeningModel(
            account: Account(username: "someone-else", token: ""),
            provider: provider,
            eraActivityCache: cache
        )
        await otherUser.loadEraActivity(for: .thisYear)
        await otherUser.loadEraActivity(for: .allTime)
        let isolatedRequestCount = await provider.requestCount()
        XCTAssertEqual(isolatedRequestCount, 3)
    }

    func testStaleEraActivityStaysVisibleDuringRefreshAndOnFailure() async throws {
        let cache = EntityDetailCache<EraActivityCacheKey, EraActivity>(timeToLive: -1)
        let stale = EraActivity.fixture(period: .thisYear, year: 1997, listenCount: 3)
        await cache.save(stale, for: .init(username: "listener", period: .thisYear))
        let provider = EraActivityProvider(result: .failure, delay: .seconds(1))
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            eraActivityCache: cache
        )

        let task = Task { await model.loadEraActivity(for: .thisYear) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        guard case let .loaded(visible) = model.eraActivityState(for: .thisYear) else {
            return XCTFail("Stale era data should remain visible while refreshing")
        }
        XCTAssertEqual(visible.totalListens, stale.totalListens)

        await task.value
        guard case let .loaded(retained) = model.eraActivityState(for: .thisYear) else {
            return XCTFail("A refresh failure must not discard stale era data")
        }
        XCTAssertEqual(retained.totalListens, stale.totalListens)
        XCTAssertNotNil(model.eraActivityRefreshMessage(for: .thisYear))
    }

    func testEraActivityNilAndEmptyResponsesAreHonest() async {
        let unavailableProvider = EraActivityProvider(result: .noContent)
        let unavailableModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: unavailableProvider,
            eraActivityCache: EntityDetailCache()
        )
        await unavailableModel.loadEraActivity(for: .thisYear)
        XCTAssertEqual(unavailableModel.eraActivityState(for: .thisYear), .unavailable)

        let emptyProvider = EraActivityProvider(result: .activity(year: 2025, listenCount: 0))
        let emptyModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: emptyProvider,
            eraActivityCache: EntityDetailCache()
        )
        await emptyModel.loadEraActivity(for: .thisYear)
        guard case let .loaded(activity) = emptyModel.eraActivityState(for: .thisYear) else {
            return XCTFail("Expected a loaded zero-count release year")
        }
        XCTAssertTrue(activity.isEmpty)
    }

    func testCancellingEraActivityLoadReturnsToIdle() async throws {
        let provider = EraActivityProvider(
            result: .activity(year: 2024, listenCount: 3),
            delay: .seconds(1)
        )
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            eraActivityCache: EntityDetailCache()
        )

        let task = Task { await model.loadEraActivity(for: .thisYear) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        task.cancel()
        await task.value

        XCTAssertEqual(model.eraActivityState(for: .thisYear), .idle)
    }

    func testFreshReleasesKeepPersonalizedAndSitewideRequestsSeparate() async {
        let provider = FixtureProvider()
        let model = FreshReleasesModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.load(scope: .forYou)
        guard case let .loaded(personalized) = model.state(for: .forYou) else {
            return XCTFail("Expected personalized releases")
        }
        XCTAssertTrue(personalized.isEmpty)
        let personalizedRequests = await provider.freshReleaseRequestCount(for: .forYou)
        let sitewideRequestsBeforeSelection = await provider.freshReleaseRequestCount(for: .all)
        XCTAssertEqual(personalizedRequests, 1)
        XCTAssertEqual(sitewideRequestsBeforeSelection, 0)

        await model.load(scope: .all)
        guard case let .loaded(sitewide) = model.state(for: .all) else {
            return XCTFail("Expected sitewide releases")
        }
        XCTAssertEqual(sitewide.count, 1)
        let sitewideRequests = await provider.freshReleaseRequestCount(for: .all)
        XCTAssertEqual(sitewideRequests, 1)
    }

    func testReplacementFreshReleaseLoadSurvivesOlderCancellation() async throws {
        let provider = FixtureProvider(freshReleaseDelay: .milliseconds(80))
        let model = FreshReleasesModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let first = Task { await model.load(scope: .forYou) }
        let clock = ContinuousClock()
        while await provider.freshReleaseRequestCount(for: .forYou) < 1 {
            try await clock.sleep(for: .milliseconds(1))
        }

        let replacement = Task { await model.load(scope: .forYou) }
        while await provider.freshReleaseRequestCount(for: .forYou) < 2 {
            try await clock.sleep(for: .milliseconds(1))
        }
        first.cancel()

        await first.value
        await replacement.value

        guard case .loaded = model.state(for: .forYou) else {
            return XCTFail("Expected the replacement Fresh Releases request to remain loaded")
        }
    }

    func testFreshReleaseRefreshCoalescesWhileLoading() async throws {
        let provider = FixtureProvider(freshReleaseDelay: .milliseconds(80))
        let model = FreshReleasesModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let load = Task { await model.load(scope: .all) }
        let clock = ContinuousClock()
        while await provider.freshReleaseRequestCount(for: .all) < 1 {
            try await clock.sleep(for: .milliseconds(1))
        }

        await model.refresh(scope: .all)

        let requestCount = await provider.freshReleaseRequestCount(for: .all)
        XCTAssertEqual(requestCount, 1)
        await load.value
    }

    func testFreshReleaseDateKeepsCalendarDayWestOfUTC() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Edmonton"))
        let release = FreshRelease(
            releaseMBID: FixtureProvider.releaseMBID,
            releaseGroupMBID: nil,
            title: "Dated Fixture",
            artistName: "Fixture Artist",
            artistMBIDs: [FixtureProvider.artistMBID],
            releaseDate: "2026-9-7",
            primaryType: "Album",
            secondaryType: nil,
            tags: [],
            confidence: nil,
            listenCount: nil,
            artworkReleaseMBID: FixtureProvider.releaseMBID,
            sourcePosition: 0
        )

        let date = try XCTUnwrap(release.releaseDateValue(in: timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 7)
    }

    func testFreshReleaseIdentityDistinguishesDuplicateUnmappedRows() {
        func release(at sourcePosition: Int) -> FreshRelease {
            FreshRelease(
                releaseMBID: nil,
                releaseGroupMBID: nil,
                title: "Same title",
                artistName: "Same artist",
                artistMBIDs: [],
                releaseDate: "2026-9-7",
                primaryType: nil,
                secondaryType: nil,
                tags: [],
                confidence: nil,
                listenCount: nil,
                artworkReleaseMBID: nil,
                sourcePosition: sourcePosition
            )
        }

        XCTAssertNotEqual(release(at: 0).id, release(at: 1).id)
    }

    func testFreshReleasesArePresentedNewestFirst() {
        func release(date: String?, sourcePosition: Int) -> FreshRelease {
            FreshRelease(
                releaseMBID: nil,
                releaseGroupMBID: nil,
                title: date ?? "Unknown date",
                artistName: "Fixture Artist",
                artistMBIDs: [],
                releaseDate: date,
                primaryType: nil,
                secondaryType: nil,
                tags: [],
                confidence: nil,
                listenCount: nil,
                artworkReleaseMBID: nil,
                sourcePosition: sourcePosition
            )
        }
        let releases = [
            release(date: "2026-09-10", sourcePosition: 0),
            release(date: nil, sourcePosition: 1),
            release(date: "2026-09-20", sourcePosition: 2),
        ]

        let sorted = releases.sorted(by: ListenBrainzProvider.freshReleaseComesFirst)

        XCTAssertEqual(sorted.map(\.releaseDate), ["2026-09-20", "2026-09-10", nil])
    }

    func testSearchTrimsCachesPerScopeAndAvoidsEmptyRequests() async {
        let provider = SearchFixtureProvider()
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider
        )

        await model.searchImmediatelyForTesting()
        let emptyRequestCount = await provider.requestCount()
        XCTAssertEqual(emptyRequestCount, 0)

        model.update(query: "  Björk  ")
        await model.searchImmediatelyForTesting()
        XCTAssertEqual(model.results.first?.title, "Björk")
        let firstQueries = await provider.queries()
        XCTAssertEqual(firstQueries, ["Björk"])

        model.update(query: "BJÖRK")
        await model.searchImmediatelyForTesting()
        let cachedRequestCount = await provider.requestCount()
        XCTAssertEqual(cachedRequestCount, 1)

        model.update(scope: .recordings)
        await model.searchImmediatelyForTesting()
        let scopedRequestCount = await provider.requestCount()
        XCTAssertEqual(scopedRequestCount, 2)
    }

    func testInitialSearchConfigurationStartsOnlyOnce() async throws {
        let provider = SearchFixtureProvider()
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider,
            debounceDuration: .milliseconds(1),
            initialQuery: "listener",
            initialScope: .users
        )

        model.startInitialSearchIfNeeded()
        model.startInitialSearchIfNeeded()
        try await ContinuousClock().sleep(for: .milliseconds(20))

        XCTAssertEqual(model.scope, .users)
        XCTAssertEqual(model.state, .loaded)
        let requestCount = await provider.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testPlaylistSearchRequiresThreeCharactersBeforeCallingProvider() async {
        let provider = SearchFixtureProvider()
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider
        )
        model.update(scope: .playlists)
        model.update(query: "ab")

        await model.searchImmediatelyForTesting()

        XCTAssertEqual(model.state, .idle)
        let requestCount = await provider.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testSupersededSearchCannotOverwriteNewerResults() async throws {
        let provider = SearchFixtureProvider(delay: .milliseconds(40))
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider
        )
        model.update(query: "older")
        let older = Task { await model.searchImmediatelyForTesting() }
        try await ContinuousClock().sleep(for: .milliseconds(5))
        model.update(query: "newer")
        await model.searchImmediatelyForTesting()
        await older.value

        XCTAssertEqual(model.results.first?.title, "newer")
    }

    func testMusicBrainzSearchUsesLiteralQueryAndClampedLimit() throws {
        let request = try MusicBrainzSearchClient.makeRequest(
            query: "A/B + C && D || E",
            scope: .artists,
            limit: 999,
            userAgent: "Brainz test"
        )
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["query"], "\"A\\/B \\+ C \\&\\& D \\|\\| E\"")
        XCTAssertEqual(values["limit"], "25")
        XCTAssertEqual(values["fmt"], "json")
        XCTAssertTrue(components.path.hasSuffix("/artist/"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Brainz test")
    }

    func testMusicBrainzSearchNeutralizesLuceneWordOperators() {
        XCTAssertEqual(
            MusicBrainzSearchClient.escapeLuceneLiteral("Björk OR Prince NOT remix"),
            "\"Björk OR Prince NOT remix\""
        )
    }

    func testMusicBrainzRetryAfterSupportsHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://musicbrainz.org")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": formatter.string(from: now.addingTimeInterval(12))]
        ))

        XCTAssertEqual(MusicBrainzSearchClient.retryAfter(response, now: now), 12)
    }

    func testMusicBrainzRecordingDecodeToleratesSparseMetadataAndKeepsCreditJoinPhrases() throws {
        let data = Data(#"""
        {
          "recordings": [{
            "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "title": "A sparse recording",
            "artist-credit": [
              {"name": "One", "joinphrase": " feat. ", "artist": {"id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "name": "One"}},
              {"name": "Two", "artist": {"id": "cccccccc-cccc-cccc-cccc-cccccccccccc", "name": "Two"}}
            ]
          }]
        }
        """#.utf8)

        let result = try XCTUnwrap(MusicBrainzSearchClient.decode(data: data, scope: .recordings).first)
        guard case let .recording(recording) = result else {
            return XCTFail("Expected a recording result")
        }
        XCTAssertEqual(recording.artistName, "One feat. Two")
        XCTAssertEqual(recording.releaseTitle, nil)
        XCTAssertEqual(recording.artistMBIDs.count, 2)
    }

    func testClosingSearchCancelsAnInFlightProviderRequest() async throws {
        let provider = SearchFixtureProvider(delay: .seconds(2))
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider,
            debounceDuration: .milliseconds(1)
        )
        model.update(query: "abandoned")
        try await ContinuousClock().sleep(for: .milliseconds(20))

        model.cancel()
        try await ContinuousClock().sleep(for: .milliseconds(20))

        XCTAssertEqual(model.state, .idle)
        let cancellationCount = await provider.cancellationCount()
        XCTAssertEqual(cancellationCount, 1)
    }

    nonisolated func testRequestGateSpacesActualOperationStarts() async throws {
        let gate = RequestGate(minimumInterval: .milliseconds(40))
        let clock = ContinuousClock()
        let start = clock.now

        let elapsed = try await withThrowingTaskGroup(of: Duration.self) { group in
            for _ in 0 ..< 3 {
                group.addTask {
                    try await gate.perform {
                        start.duration(to: clock.now)
                    }
                }
            }
            var values: [Duration] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }
        let milliseconds = elapsed.map(Self.milliseconds).sorted()

        XCTAssertGreaterThanOrEqual(milliseconds[1] - milliseconds[0], 30)
        XCTAssertGreaterThanOrEqual(milliseconds[2] - milliseconds[1], 30)
    }

    nonisolated func testRequestGateHonorsServerDeferral() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let clock = ContinuousClock()
        await gate.deferRequests(for: .milliseconds(50))
        let start = clock.now

        let elapsed = try await gate.perform {
            start.duration(to: clock.now)
        }

        XCTAssertGreaterThanOrEqual(Self.milliseconds(elapsed), 40)
    }

    nonisolated func testServerDeferralReschedulesAlreadyQueuedCallers() async throws {
        let gate = RequestGate(minimumInterval: .milliseconds(20))
        let clock = ContinuousClock()
        try await gate.perform {}
        let start = clock.now

        let first = Task {
            try await gate.perform {
                start.duration(to: clock.now)
            }
        }
        let second = Task {
            try await gate.perform {
                start.duration(to: clock.now)
            }
        }
        try await clock.sleep(for: .milliseconds(5))
        await gate.deferRequests(for: .milliseconds(70))

        let firstElapsed = try await first.value
        let secondElapsed = try await second.value
        let elapsed = [firstElapsed, secondElapsed].map(Self.milliseconds).sorted()
        XCTAssertGreaterThanOrEqual(elapsed[0], 60)
        XCTAssertGreaterThanOrEqual(elapsed[1] - elapsed[0], 15)
    }

    nonisolated func testRateLimitDeferralIsInstalledBeforeQueuedOperationStarts() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = GateProbe()
        let clock = ContinuousClock()

        let limited = Task {
            try await gate.perform({
                await probe.markStarted()
                try await clock.sleep(for: .milliseconds(10))
                throw GateTestError.rateLimited
            }, deferralForError: { error in
                error is GateTestError ? .milliseconds(60) : nil
            })
        }

        while !(await probe.hasStarted()) {
            try await clock.sleep(for: .milliseconds(1))
        }
        let queuedAt = clock.now
        let queued = Task {
            try await gate.perform {
                queuedAt.duration(to: clock.now)
            }
        }

        do {
            try await limited.value
            XCTFail("The first operation should surface its rate-limit error")
        } catch GateTestError.rateLimited {}

        let elapsed = try await queued.value
        XCTAssertGreaterThanOrEqual(Self.milliseconds(elapsed), 60)
    }

    nonisolated func testCancellingQueuedOperationTransfersOwnership() async throws {
        let gate = RequestGate(minimumInterval: .milliseconds(100))
        let probe = GateProbe()
        let clock = ContinuousClock()

        let active = Task {
            try await gate.perform {
                await probe.markStarted()
                try await clock.sleep(for: .milliseconds(40))
            }
        }
        while !(await probe.hasStarted()) {
            try await clock.sleep(for: .milliseconds(1))
        }

        let cancelled = Task {
            try await gate.perform { 2 }
        }
        let successor = Task {
            try await gate.perform { 3 }
        }
        while await gate.queuedRequestCountForTesting() < 2 {
            try await clock.sleep(for: .milliseconds(1))
        }

        try await active.value
        // Completion has transferred ownership to the first waiter. Cancelling
        // in that handoff window must still release the next queued caller.
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled queued operation should not start")
        } catch is CancellationError {}
        let successorValue = try await successor.value
        XCTAssertEqual(successorValue, 3)
    }

    private func recording(mbid: UUID?, msid: UUID?) -> Recording {
        Recording(
            identity: .init(mbid: mbid, msid: msid),
            title: "Fixture Track",
            artistName: "Fixture Artist",
            artistMBIDs: [FixtureProvider.artistMBID],
            releaseTitle: "Fixture Album",
            releaseMBID: FixtureProvider.releaseMBID,
            releaseGroupMBID: nil,
            artworkReleaseMBID: FixtureProvider.releaseMBID,
            durationMilliseconds: 180_000,
            source: "Fixture"
        )
    }

    nonisolated private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private enum GateTestError: Error {
    case rateLimited
}

private actor GateProbe {
    private var started = false

    func markStarted() { started = true }
    func hasStarted() -> Bool { started }
}

private actor SearchFixtureProvider: SearchProviding {
    private let delay: Duration?
    private var calls: [(String, SearchScope)] = []
    private var cancellations = 0

    init(delay: Duration? = nil) { self.delay = delay }

    func search(query: String, scope: SearchScope) async throws -> [SearchResult] {
        calls.append((query, scope))
        if let delay {
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch {
                cancellations += 1
                throw error
            }
        }
        return [.user(.init(username: query))]
    }

    func requestCount() -> Int { calls.count }
    func queries() -> [String] { calls.map(\.0) }
    func cancellationCount() -> Int { cancellations }
}

private extension DailyActivity {
    static func fixture(period: ListeningActivityPeriod, listenCount: Int) -> DailyActivity {
        DailyActivity(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            dailyActivity: ["Monday": [.init(hour: 20, listenCount: listenCount)]]
        )
    }
}

private actor DailyActivityProvider: ListeningProvider {
    enum Result: Sendable {
        case activity(listenCount: Int)
        case noContent
        case failure
    }

    private var results: [Result]
    private var delays: [Duration]
    private let ignoresCancellation: Bool
    private var requests = 0

    init(
        result: Result,
        delay: Duration = .zero,
        ignoresCancellation: Bool = false
    ) {
        self.results = [result]
        self.delays = [delay]
        self.ignoresCancellation = ignoresCancellation
    }

    init(results: [Result], delays: [Duration], ignoresCancellation: Bool) {
        self.results = results
        self.delays = delays
        self.ignoresCancellation = ignoresCancellation
    }

    func validateToken() async throws -> String { "fixture" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func dailyActivity(username: String, period: ListeningActivityPeriod) async throws -> DailyActivity? {
        let index = requests
        requests += 1
        let delay = delays[min(index, delays.count - 1)]
        if delay > .zero {
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch where !ignoresCancellation {
                throw CancellationError()
            } catch {
                // Deliberately behave like a provider that returns late after
                // cancellation, to prove the model's request ID protection.
            }
        }
        switch results[min(index, results.count - 1)] {
        case let .activity(listenCount):
            return .fixture(period: period, listenCount: listenCount)
        case .noContent:
            return nil
        case .failure:
            throw URLError(.cannotConnectToHost)
        }
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    func requestCount() -> Int { requests }
}

private extension EraActivity {
    static func fixture(
        period: ListeningActivityPeriod,
        year: Int,
        listenCount: Int
    ) -> EraActivity {
        EraActivity(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            years: [.init(year: year, listenCount: listenCount)]
        )
    }
}

private actor EraActivityProvider: ListeningProvider {
    enum Result: Sendable {
        case activity(year: Int, listenCount: Int)
        case noContent
        case failure
    }

    private let result: Result
    private let delay: Duration
    private var requests = 0

    init(result: Result, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }

    func validateToken() async throws -> String { "fixture" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func eraActivity(username: String, period: ListeningActivityPeriod) async throws -> EraActivity? {
        requests += 1
        if delay > .zero {
            try await ContinuousClock().sleep(for: delay)
        }
        switch result {
        case let .activity(year, listenCount):
            return .fixture(period: period, year: year, listenCount: listenCount)
        case .noContent:
            return nil
        case .failure:
            throw URLError(.cannotConnectToHost)
        }
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    func requestCount() -> Int { requests }
}

private actor FixtureProvider: ListeningProvider {
    static let artistMBID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let releaseMBID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let recordingMBID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let activityDelay: Duration?
    private let freshReleaseDelay: Duration?
    private var activityRequests: [ListeningActivityPeriod: Int] = [:]
    private var freshReleaseRequests: [FreshReleaseScope: Int] = [:]

    init(activityDelay: Duration? = nil, freshReleaseDelay: Duration? = nil) {
        self.activityDelay = activityDelay
        self.freshReleaseDelay = freshReleaseDelay
    }

    func validateToken() async throws -> String { "fixture-user" }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        [
            listen(title: "Fixture Track", timestamp: 1_700_000_000),
            listen(title: "Earlier Track", timestamp: 1_699_999_000),
        ]
    }

    func playingNow(username: String) async throws -> Listen? {
        listen(title: "Playing Now", timestamp: 1_700_000_500, isPlayingNow: true)
    }

    func listenCount(username: String) async throws -> Int { 42 }

    func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
        [RankedArtist(mbid: Self.artistMBID, name: "Fixture Artist", listenCount: 42)]
    }

    func topReleases(username: String, count: Int) async throws -> [RankedRelease] {
        [
            RankedRelease(
                mbid: Self.releaseMBID,
                name: "Fixture Album",
                artistName: "Fixture Artist",
                artistMBIDs: [Self.artistMBID],
                listenCount: 21
            ),
        ]
    }

    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
        [
            RankedRecording(
                mbid: Self.recordingMBID,
                releaseMBID: Self.releaseMBID,
                title: "Fixture Track",
                artistName: "Fixture Artist",
                artistMBIDs: [Self.artistMBID],
                releaseTitle: "Fixture Album",
                listenCount: 12
            ),
        ]
    }

    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        activityRequests[period, default: 0] += 1
        if let activityDelay {
            try await ContinuousClock().sleep(for: activityDelay)
        }
        return ListeningActivity(
            period: period,
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_086_400),
            lastUpdated: Date(timeIntervalSince1970: 1_700_100_000),
            buckets: [
                .init(
                    label: "Monday",
                    from: Date(timeIntervalSince1970: 1_700_000_000),
                    to: Date(timeIntervalSince1970: 1_700_043_200),
                    listenCount: 6
                ),
                .init(
                    label: "Tuesday",
                    from: Date(timeIntervalSince1970: 1_700_043_200),
                    to: Date(timeIntervalSince1970: 1_700_086_400),
                    listenCount: 9
                ),
            ]
        )
    }

    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] {
        freshReleaseRequests[scope, default: 0] += 1
        if let freshReleaseDelay {
            try await ContinuousClock().sleep(for: freshReleaseDelay)
        }
        guard scope == .all else { return [] }
        return [
            FreshRelease(
                releaseMBID: Self.releaseMBID,
                releaseGroupMBID: nil,
                title: "Fresh Fixture",
                artistName: "Fixture Artist",
                artistMBIDs: [Self.artistMBID],
                releaseDate: "2026-9-7",
                primaryType: "Album",
                secondaryType: nil,
                tags: ["fixture"],
                confidence: nil,
                listenCount: 1,
                artworkReleaseMBID: Self.releaseMBID,
                sourcePosition: 0
            ),
        ]
    }

    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    func activityRequestCount(for period: ListeningActivityPeriod) -> Int {
        activityRequests[period, default: 0]
    }

    func freshReleaseRequestCount(for scope: FreshReleaseScope) -> Int {
        freshReleaseRequests[scope, default: 0]
    }

    private func listen(title: String, timestamp: TimeInterval, isPlayingNow: Bool = false) -> Listen {
        Listen(
            recording: Recording(
                identity: .init(mbid: Self.recordingMBID, msid: nil),
                title: title,
                artistName: "Fixture Artist",
                artistMBIDs: [Self.artistMBID],
                releaseTitle: "Fixture Album",
                releaseMBID: Self.releaseMBID,
                releaseGroupMBID: nil,
                artworkReleaseMBID: Self.releaseMBID,
                durationMilliseconds: 180_000,
                source: "Fixture"
            ),
            listenedAt: Date(timeIntervalSince1970: timestamp),
            insertedAt: nil,
            isPlayingNow: isPlayingNow
        )
    }
}

private actor BoundaryProvider: ListeningProvider {
    private var lastBefore: Date?
    private var lastCount = 0

    func validateToken() async throws -> String { "fixture-user" }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        lastBefore = before
        lastCount = count
        if before == nil {
            return (0 ..< 39).map { index in
                listen(title: "Recent \(index)", timestamp: 2_000 - Double(index))
            } + [listen(title: "Boundary original", timestamp: 1_900)]
        }
        return [
            listen(title: "Boundary original", timestamp: 1_900),
            listen(title: "Boundary sibling", timestamp: 1_900),
            listen(title: "Older listen", timestamp: 1_899),
        ]
    }

    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 42 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        ListeningActivity(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            buckets: []
        )
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    func requestedBefore() -> Date? { lastBefore }
    func requestedCount() -> Int { lastCount }

    private func listen(title: String, timestamp: TimeInterval) -> Listen {
        Listen(
            recording: Recording(
                identity: .init(mbid: nil, msid: nil),
                title: title,
                artistName: "Boundary Artist",
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: "Fixture"
            ),
            listenedAt: Date(timeIntervalSince1970: timestamp),
            insertedAt: nil,
            isPlayingNow: false
        )
    }
}

private actor DayHistoryProvider: ListeningProvider {
    enum Mode {
        case singleDay
        case staleSelection
        case boundarySiblings
        case repeatedCursor
        case returnsAfterCancellation
        case urlCancellation
        case stalePagination
    }
    struct Request: Sendable { let before: Date?; let after: Date? }

    private let mode: Mode
    private var requestsMade: [Request] = []
    private var requestNumber = 0
    private let recordingMBID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    init(mode: Mode) { self.mode = mode }

    func validateToken() async throws -> String { "fixture-user" }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        requestsMade.append(.init(before: before, after: after))
        requestNumber += 1
        switch mode {
        case .singleDay:
            return [listen(title: "Day listen", timestamp: 1_700_000_000, msid: nil)]
        case .staleSelection:
            if requestNumber == 1 {
                try await ContinuousClock().sleep(for: .milliseconds(60))
                return [listen(title: "Older day", timestamp: 1_700_000_000, msid: nil)]
            }
            return [listen(title: "Newer day", timestamp: 1_700_086_400, msid: nil)]
        case .boundarySiblings:
            if requestNumber == 1 {
                return (0 ..< 100).map { index in
                    listen(title: "Initial \(index)", timestamp: 2_000 - Double(index), msid: index == 99 ? UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")! : nil)
                }
            }
            return [
                listen(title: "Initial 99", timestamp: 1_901, msid: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!),
                listen(title: "Boundary sibling", timestamp: 1_901, msid: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!),
                listen(title: "Older", timestamp: 1_900, msid: nil),
            ]
        case .repeatedCursor:
            return (0 ..< 100).map { index in
                listen(title: "Repeated \(index)", timestamp: 2_000 - Double(index), msid: nil)
            }
        case .returnsAfterCancellation:
            try? await ContinuousClock().sleep(for: .seconds(1))
            return [listen(title: "Cancelled result", timestamp: 1_700_000_000, msid: nil)]
        case .urlCancellation:
            do {
                try await ContinuousClock().sleep(for: .seconds(1))
            } catch {
                throw URLError(.cancelled)
            }
            return []
        case .stalePagination:
            if requestNumber == 1 {
                return (0 ..< 100).map { index in
                    listen(title: "Initial \(index)", timestamp: 2_000 - Double(index), msid: nil)
                }
            }
            if requestNumber == 2 {
                try? await ContinuousClock().sleep(for: .milliseconds(60))
                return [listen(title: "Stale page", timestamp: 1_899, msid: nil)]
            }
            return [listen(title: "Replacement day", timestamp: 1_800, msid: nil)]
        }
    }

    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    func requests() -> [Request] { requestsMade }

    private func listen(title: String, timestamp: TimeInterval, msid: UUID?) -> Listen {
        Listen(
            recording: Recording(
                identity: .init(mbid: recordingMBID, msid: msid),
                title: title,
                artistName: "Fixture Artist",
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: Date(timeIntervalSince1970: timestamp),
            insertedAt: nil,
            isPlayingNow: false
        )
    }
}
