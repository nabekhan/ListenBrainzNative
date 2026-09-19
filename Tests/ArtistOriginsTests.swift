import Foundation
import XCTest

@testable import Brainz

@MainActor
final class ArtistOriginsTests: XCTestCase {
    func testArtistOriginsNormalizesAndMergesDuplicateCountriesAndArtists() {
        let sharedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let origins = ArtistOrigins(
            period: .allTime,
            from: .distantPast,
            to: .now,
            lastUpdated: .now,
            rows: [
                .init(
                    countryCode: " usa ",
                    artistCount: 2,
                    listenCount: 5,
                    artists: [
                        .init(mbid: sharedID, name: "The Artist", listenCount: 3),
                        .init(mbid: nil, name: "Unmapped", listenCount: 2),
                    ]
                ),
                .init(
                    countryCode: "USA",
                    artistCount: 1,
                    listenCount: 4,
                    artists: [
                        .init(mbid: sharedID, name: "the artist", listenCount: 4),
                        .init(mbid: nil, name: "  Unmapped ", listenCount: 1),
                    ]
                ),
                .init(
                    countryCode: "?",
                    artistCount: 3,
                    listenCount: 2,
                    artists: [.init(mbid: nil, name: "Unknown-country artist", listenCount: 2)]
                ),
            ]
        )

        XCTAssertEqual(origins.countries.count, 2)
        let usa = try! XCTUnwrap(origins.countries.first { $0.code == "USA" })
        XCTAssertEqual(usa.artistCount, 3)
        XCTAssertEqual(usa.listenCount, 9)
        XCTAssertEqual(usa.artists.map(\.listenCount), [7, 3])
        XCTAssertEqual(usa.artists.first?.mbid, sharedID)
        XCTAssertEqual(origins.countries.last?.code, nil)
        XCTAssertFalse(origins.countries.last?.isKnownCode ?? true)
    }

    func testOnDemandLoadUsesFreshCacheAndPreservesNestedArtists() async throws {
        let provider = ArtistOriginsFixtureProvider(result: .success(Self.origins()))
        let cache = EntityDetailCache<ArtistOriginsCacheKey, ArtistOrigins>()
        let model = ListeningModel(
            account: Account(username: "listener", token: "origins-token"),
            provider: provider,
            artistOriginsCache: cache
        )

        await model.loadArtistOrigins(for: .thisYear)
        await model.loadArtistOrigins(for: .thisYear)

        let calls = await provider.callCount()
        XCTAssertEqual(calls, 1)
        guard case .loaded(let origins) = model.artistOriginsState(for: .thisYear) else {
            return XCTFail("Expected loaded Artist Origins")
        }
        XCTAssertEqual(origins.countries.first?.artists.first?.name, "Fixture Artist")
    }

    func testCancelledLoadCanBeReplacedWithoutOlderResultOverwritingIt() async throws {
        let provider = ArtistOriginsFixtureProvider(result: .success(Self.origins()), delay: .milliseconds(200))
        let model = ListeningModel(
            account: Account(username: "listener", token: "origins-token"),
            provider: provider,
            artistOriginsCache: EntityDetailCache()
        )

        let first = Task { @MainActor in
            await model.loadArtistOrigins(for: .thisMonth)
        }
        await provider.waitForCalls(1)
        first.cancel()
        await model.loadArtistOrigins(for: .thisMonth, retrying: true)
        _ = await first.result

        let calls = await provider.callCount()
        XCTAssertEqual(calls, 2)
        guard case .loaded = model.artistOriginsState(for: .thisMonth) else {
            return XCTFail("Expected replacement request to load Artist Origins")
        }
    }

    func testStaleCachedOriginsStayVisibleWhenRefreshFails() async throws {
        let cache = EntityDetailCache<ArtistOriginsCacheKey, ArtistOrigins>(timeToLive: -1)
        let account = Account(username: "listener", token: "origins-token")
        let key = ArtistOriginsCacheKey(
            username: account.username,
            scope: .authenticated(token: account.token),
            period: .thisWeek
        )
        await cache.save(Self.origins(), for: key)
        let provider = ArtistOriginsFixtureProvider(result: .failure(OriginFixtureError.offline))
        let model = ListeningModel(account: account, provider: provider, artistOriginsCache: cache)

        await model.loadArtistOrigins(for: .thisWeek)

        let calls = await provider.callCount()
        XCTAssertEqual(calls, 1)
        guard case .loaded(let origins) = model.artistOriginsState(for: .thisWeek) else {
            return XCTFail("Expected stale Artist Origins to remain visible")
        }
        XCTAssertEqual(origins.totalListenCount, 8)
        XCTAssertEqual(
            model.artistOriginsRefreshMessage(for: .thisWeek), OriginFixtureError.offline.localizedDescription)
    }

    private static func origins() -> ArtistOrigins {
        ArtistOrigins(
            period: .thisYear,
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_730_000_000),
            lastUpdated: Date(timeIntervalSince1970: 1_730_000_100),
            rows: [
                .init(
                    countryCode: "CAN",
                    artistCount: 1,
                    listenCount: 8,
                    artists: [.init(mbid: UUID(), name: "Fixture Artist", listenCount: 8)]
                )
            ]
        )
    }
}

private enum OriginFixtureError: LocalizedError {
    case offline

    var errorDescription: String? { "Offline" }
}

private actor ArtistOriginsFixtureProvider: ListeningProvider {
    private let result: Result<ArtistOrigins?, Error>
    private let delay: Duration?
    private var calls = 0

    init(result: Result<ArtistOrigins?, Error>, delay: Duration? = nil) {
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
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    func artistOrigins(username: String, period: ListeningActivityPeriod) async throws -> ArtistOrigins? {
        calls += 1
        if let delay { try await Task.sleep(for: delay) }
        return try result.get()
    }

    func callCount() -> Int { calls }

    func waitForCalls(_ expected: Int) async {
        while calls < expected {
            await Task.yield()
        }
    }
}
