import Foundation
import XCTest

@testable import Brainz

@MainActor
final class ArtistActivityTests: XCTestCase {
    func testFreshCacheIsReusedAcrossModelInstancesAndNoContentIsUnavailable() async {
        let provider = ArtistActivityFixtureProvider(result: .success(Self.fixture))
        let cache = EntityDetailCache<ArtistActivityCacheKey, ArtistActivity>()
        let account = Account(username: "listener", token: "activity-token")
        let first = ListeningModel(account: account, provider: provider, artistActivityCache: cache)
        let second = ListeningModel(account: account, provider: provider, artistActivityCache: cache)

        await first.loadArtistActivity(for: .thisYear)
        await second.loadArtistActivity(for: .thisYear)

        let freshCalls = await provider.callCount()
        XCTAssertEqual(freshCalls, 1)
        guard case .loaded = second.artistActivityState(for: .thisYear) else {
            return XCTFail("Expected cached Artist Activity")
        }

        let unavailable = ListeningModel(
            account: account,
            provider: ArtistActivityFixtureProvider(result: .success(nil)),
            artistActivityCache: EntityDetailCache()
        )
        await unavailable.loadArtistActivity(for: .thisMonth)
        XCTAssertEqual(unavailable.artistActivityState(for: .thisMonth), .unavailable)
    }

    func testCancelledConsumerRejoinsOneFlightWhenViewReopens() async {
        let provider = ArtistActivityFixtureProvider(
            result: .success(Self.fixture),
            delay: .milliseconds(200)
        )
        let model = ListeningModel(
            account: Account(username: "listener", token: "activity-token"),
            provider: provider,
            artistActivityCache: EntityDetailCache()
        )

        let firstConsumer = Task { @MainActor in
            await model.loadArtistActivity(for: .thisMonth)
        }
        await provider.waitForCalls(1)
        firstConsumer.cancel()

        let replacementConsumer = Task { @MainActor in
            await model.loadArtistActivity(for: .thisMonth)
        }
        await replacementConsumer.value
        await firstConsumer.value

        let joinedCalls = await provider.callCount()
        XCTAssertEqual(joinedCalls, 1)
        guard case .loaded = model.artistActivityState(for: .thisMonth) else {
            return XCTFail("Expected the replacement consumer to receive the shared flight")
        }
    }

    func testSessionTeardownCancelsTheInFlightRead() async {
        let provider = ArtistActivityFixtureProvider(
            result: .success(Self.fixture),
            delay: .seconds(30)
        )
        let model = ListeningModel(
            account: Account(username: "listener", token: "activity-token"),
            provider: provider,
            artistActivityCache: EntityDetailCache()
        )

        let consumer = Task { @MainActor in
            await model.loadArtistActivity(for: .thisMonth)
        }
        await provider.waitForCalls(1)
        model.cancelArtistActivityLoads()
        await consumer.value

        let calls = await provider.callCount()
        let cancellations = await provider.cancellationCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(model.artistActivityState(for: .thisMonth), .idle)
    }

    func testStaleCachedActivityStaysVisibleWhenRefreshFails() async {
        let cache = EntityDetailCache<ArtistActivityCacheKey, ArtistActivity>(timeToLive: -1)
        let account = Account(username: "listener", token: "activity-token")
        let key = ArtistActivityCacheKey(
            username: account.username,
            scope: .authenticated(token: account.token),
            period: .thisWeek
        )
        await cache.save(Self.fixture, for: key)
        let provider = ArtistActivityFixtureProvider(result: .failure(ArtistActivityFixtureError.offline))
        let model = ListeningModel(account: account, provider: provider, artistActivityCache: cache)

        await model.loadArtistActivity(for: .thisWeek)

        let staleCalls = await provider.callCount()
        XCTAssertEqual(staleCalls, 1)
        guard case let .loaded(activity) = model.artistActivityState(for: .thisWeek) else {
            return XCTFail("Expected stale Artist Activity to remain visible")
        }
        XCTAssertEqual(activity.artists.first?.name, "Fixture Artist")
        XCTAssertEqual(
            model.artistActivityRefreshMessage(for: .thisWeek),
            ArtistActivityFixtureError.offline.localizedDescription
        )
    }

    func testNormalizesNamesKeepsDistinctMBIDsAndMergesAlbumsByIdentity() throws {
        let first = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let group = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let activity = ArtistActivity(
            period: .thisYear,
            from: .distantPast,
            to: .now,
            lastUpdated: .now,
            rows: [
                .init(
                    creditedName: "  Same Name ",
                    canonicalName: "Canonical",
                    artistMBID: first,
                    listenCount: 4,
                    albums: [.init(name: " Album ", releaseGroupMBID: group, listenCount: 2)]
                ),
                .init(
                    creditedName: "Same Name",
                    canonicalName: "Canonical",
                    artistMBID: first,
                    listenCount: 3,
                    albums: [.init(name: "Album", releaseGroupMBID: group, listenCount: 5)]
                ),
                .init(
                    creditedName: "Same Name",
                    canonicalName: nil,
                    artistMBID: second,
                    listenCount: -2,
                    albums: []
                ),
                .init(
                    creditedName: "  unmapped  ",
                    canonicalName: nil,
                    artistMBID: nil,
                    listenCount: 2,
                    albums: []
                ),
                .init(
                    creditedName: "Unmapped",
                    canonicalName: nil,
                    artistMBID: nil,
                    listenCount: 1,
                    albums: []
                ),
            ]
        )

        XCTAssertEqual(activity.artists.count, 3)
        XCTAssertEqual(activity.artists.first?.mbid, first)
        XCTAssertEqual(activity.artists.first?.name, "Canonical")
        XCTAssertEqual(activity.artists.first?.listenCount, 7)
        XCTAssertEqual(activity.artists.first?.albums.first?.listenCount, 7)
        XCTAssertEqual(activity.artists[1].name, "unmapped")
        XCTAssertEqual(activity.artists[1].listenCount, 3)
        XCTAssertEqual(activity.totalListenCount, 10)
        XCTAssertEqual(activity.albumEntryCount, 1)

        let destination = try XCTUnwrap(activity.artists.first?.albums.first?.releaseGroup(artistName: "Canonical"))
        XCTAssertEqual(destination.artistName, "Canonical")
        XCTAssertEqual(destination.mbid, group)
    }

    func testPresentationOrdersByListensAndClampsFractions() {
        let activity = ArtistActivity(
            period: .thisMonth,
            from: .distantPast,
            to: .now,
            lastUpdated: .now,
            rows: [
                .init(creditedName: "B", canonicalName: nil, artistMBID: nil, listenCount: 4, albums: []),
                .init(creditedName: "A", canonicalName: nil, artistMBID: nil, listenCount: 4, albums: []),
            ]
        )
        let presentation = ArtistActivityPresentation(activity)
        XCTAssertEqual(presentation.artists.map(\.name), ["A", "B"])
        XCTAssertEqual(presentation.fraction(2), 0.5)
        XCTAssertEqual(presentation.fraction(-1), 0)
        XCTAssertEqual(presentation.fraction(8), 1)

        let empty = ArtistActivity(
            period: .thisMonth,
            from: .distantPast,
            to: .now,
            lastUpdated: .now,
            rows: []
        )
        XCTAssertEqual(ArtistActivityPresentation(empty).fraction(1), 0)
    }

    private static let fixture = ArtistActivity(
        period: .thisYear,
        from: Date(timeIntervalSince1970: 1_700_000_000),
        to: Date(timeIntervalSince1970: 1_730_000_000),
        lastUpdated: Date(timeIntervalSince1970: 1_730_000_100),
        rows: [
            .init(
                creditedName: "Fixture Artist",
                canonicalName: nil,
                artistMBID: nil,
                listenCount: 3,
                albums: [.init(name: "Fixture Album", releaseGroupMBID: nil, listenCount: 3)]
            )
        ]
    )
}

private enum ArtistActivityFixtureError: LocalizedError {
    case offline

    var errorDescription: String? { "Offline" }
}

private actor ArtistActivityFixtureProvider: ListeningProvider {
    private let result: Result<ArtistActivity?, Error>
    private let delay: Duration?
    private var calls = 0
    private var cancellations = 0

    init(result: Result<ArtistActivity?, Error>, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func validateToken() async throws -> String { "listener" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            buckets: []
        )
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    func artistActivity(username: String, period: ListeningActivityPeriod) async throws -> ArtistActivity? {
        calls += 1
        do {
            if let delay { try await Task.sleep(for: delay) }
            return try result.get()
        } catch is CancellationError {
            cancellations += 1
            throw CancellationError()
        }
    }

    func callCount() -> Int { calls }
    func cancellationCount() -> Int { cancellations }

    func waitForCalls(_ expected: Int) async {
        while calls < expected {
            await Task.yield()
        }
    }
}
