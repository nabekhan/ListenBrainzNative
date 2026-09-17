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

private actor FixtureProvider: ListeningProvider {
    static let artistMBID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let releaseMBID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let recordingMBID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let activityDelay: Duration?
    private var activityRequests: [ListeningActivityPeriod: Int] = [:]

    init(activityDelay: Duration? = nil) {
        self.activityDelay = activityDelay
    }

    func validateToken() async throws -> String { "fixture-user" }

    func recentListens(username: String, before: Date?, count: Int) async throws -> [Listen] {
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

    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    func activityRequestCount(for period: ListeningActivityPeriod) -> Int {
        activityRequests[period, default: 0]
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

    func recentListens(username: String, before: Date?, count: Int) async throws -> [Listen] {
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
