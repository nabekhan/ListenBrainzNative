import Foundation
import XCTest
@testable import Brainz

@MainActor
final class UserDetailModelTests: XCTestCase {
    func testOverviewLoadsUsefulDataBeforeLazyTopArtists() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: UserProfileCache()
        )

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.snapshot.recentListens.count, 1)
        XCTAssertEqual(model.snapshot.playingNow?.recording.title, "Playing track")
        XCTAssertEqual(model.snapshot.listenCount, 42)
        XCTAssertTrue(model.snapshot.topArtists.isEmpty)
        XCTAssertTrue(model.snapshot.topReleases.isEmpty)
        let overviewCalls = await provider.callNames
        XCTAssertEqual(overviewCalls, ["recent:target-user", "playing:target-user", "count:target-user"])

        await model.loadTopArtists()

        XCTAssertEqual(model.snapshot.topArtists.first?.name, "Fixture artist")
        let allCalls = await provider.callNames
        XCTAssertEqual(allCalls.last, "artists:target-user")

        await model.loadTopReleases()

        XCTAssertEqual(model.snapshot.topReleases.first?.name, "Fixture album")
        let callsAfterAlbums = await provider.callNames
        XCTAssertEqual(callsAfterAlbums, [
            "recent:target-user", "playing:target-user", "count:target-user",
            "artists:target-user", "releases:target-user",
        ])
    }

    func testArtistDestinationsRequireCanonicalIdentityWithoutHydration() async throws {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: UserProfileCache()
        )

        await model.loadTopArtists()

        let mapped = try XCTUnwrap(model.snapshot.topArtists.first)
        let unmapped = try XCTUnwrap(model.snapshot.topArtists.last)
        let ownDestination = mapped.detailDestination()
        let otherListenerDestination = mapped.detailDestination(includingListenCount: false)

        XCTAssertEqual(ownDestination?.mbid, UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab"))
        XCTAssertEqual(ownDestination?.listenCount, 12)
        XCTAssertEqual(otherListenerDestination?.listenCount, 0)
        XCTAssertNil(unmapped.detailDestination())
        XCTAssertTrue(SearchUser(username: "  TARGET-user ").isSameListener(
            as: Account(username: "target-USER", token: "")
        ))
        let calls = await provider.callNames
        XCTAssertEqual(calls, ["artists:target-user"])
    }

    func testAlbumDestinationsRequireCanonicalIdentityWithoutHydration() async throws {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: UserProfileCache()
        )

        await model.loadTopReleases()

        let mapped = try XCTUnwrap(model.snapshot.topReleases.first)
        let unmapped = try XCTUnwrap(model.snapshot.topReleases.last)
        XCTAssertEqual(mapped.releaseSeed?.mbid, UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"))
        XCTAssertNil(unmapped.releaseSeed)
        let calls = await provider.callNames
        XCTAssertEqual(calls, ["releases:target-user"])
    }

    func testFreshCacheUsesNormalizedUsernameWithoutNetworkCalls() async {
        let cache = UserProfileCache()
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Cached track")]
        cached.listenCount = 99
        cached.hasLoadedOverview = true
        cached.savedAt = .now
        await cache.save(
            cached,
            for: "  MixedCase  ",
            scope: .authenticated(token: "")
        )
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "mixedcase"),
            token: "",
            provider: provider,
            cache: cache
        )

        await model.load()

        XCTAssertEqual(model.snapshot.recentListens.first?.recording.title, "Cached track")
        XCTAssertEqual(model.snapshot.listenCount, 99)
        let calls = await provider.callNames
        XCTAssertTrue(calls.isEmpty)
    }

    func testFreshCachedTopReleasesDoNotMakeANetworkCall() async {
        let cache = UserProfileCache()
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Cached track")]
        cached.topReleases = [UserDetailFixtureProvider.release(name: "Cached album")]
        cached.hasLoadedOverview = true
        cached.hasLoadedTopReleases = true
        cached.savedAt = .now
        await cache.save(
            cached,
            for: "target-user",
            scope: .authenticated(token: "")
        )
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: cache
        )

        await model.load()
        await model.loadTopReleases()

        XCTAssertEqual(model.snapshot.topReleases.first?.name, "Cached album")
        let calls = await provider.callNames
        XCTAssertTrue(calls.isEmpty)
    }

    func testOptionalOverviewFailuresKeepLoadedHistory() async {
        let provider = UserDetailFixtureProvider(failPlayingNow: true, failListenCount: true)
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: UserProfileCache()
        )

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.snapshot.recentListens.count, 1)
        XCTAssertNil(model.snapshot.playingNow)
        XCTAssertNil(model.snapshot.listenCount)
        XCTAssertTrue(model.snapshot.hasLoadedOverview)
    }

    func testRepeatedAppearancesDoNotDuplicateRequests() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: UserProfileCache()
        )

        await model.load()
        await model.load()
        await model.loadTopArtists()
        await model.loadTopArtists()
        await model.loadTopReleases()
        await model.loadTopReleases()

        let calls = await provider.callNames
        XCTAssertEqual(calls.count, 5)
        XCTAssertEqual(calls.filter { $0 == "releases:target-user" }.count, 1)
    }

    func testCacheFreshnessExpiresWithoutLosingStaleValue() async {
        let cache = UserProfileCache(timeToLive: 300)
        var snapshot = UserProfileSnapshot.empty
        snapshot.hasLoadedOverview = true
        let savedAt = Date(timeIntervalSince1970: 1_000)
        await cache.save(snapshot, for: "Listener", scope: .authenticated(token: ""), now: savedAt)

        let fresh = await cache.value(for: "listener", scope: .authenticated(token: ""), now: savedAt.addingTimeInterval(299))
        let stale = await cache.value(for: "LISTENER", scope: .authenticated(token: ""), now: savedAt.addingTimeInterval(301))

        XCTAssertEqual(fresh?.isFresh, true)
        XCTAssertEqual(stale?.isFresh, false)
        XCTAssertNotNil(stale?.snapshot)
    }

    func testStaleTopArtistsRefreshWithoutReloadingFreshOverview() async {
        let cache = UserProfileCache(timeToLive: 300)
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Cached track")]
        cached.listenCount = 99
        cached.topArtists = [RankedArtist(mbid: nil, name: "Old artist", listenCount: 3)]
        cached.hasLoadedOverview = true
        cached.hasLoadedTopArtists = true
        let now = Date.now
        await cache.save(
            cached,
            for: "target-user",
            scope: .authenticated(token: ""),
            now: now.addingTimeInterval(-301)
        )
        await cache.saveOverview(
            cached,
            for: "target-user",
            scope: .authenticated(token: ""),
            now: now
        )
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: cache
        )

        await model.load()
        XCTAssertEqual(model.snapshot.topArtists.first?.name, "Old artist")
        await model.loadTopArtists()

        XCTAssertEqual(model.snapshot.topArtists.first?.name, "Fixture artist")
        let calls = await provider.callNames
        XCTAssertEqual(calls, ["artists:target-user"])
    }

    func testManualRefreshAlsoRefreshesPreviouslyLoadedTopArtists() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: UserProfileCache()
        )

        await model.load()
        await model.loadTopArtists()
        await model.refresh()

        let calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "artists:target-user" }.count, 2)
        XCTAssertEqual(calls.count, 8)
    }

    func testStaleTopReleasesRefreshWithoutReloadingFreshOverview() async {
        let cache = UserProfileCache(timeToLive: 300)
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Cached track")]
        cached.listenCount = 99
        cached.topReleases = [UserDetailFixtureProvider.release(name: "Old album")]
        cached.hasLoadedOverview = true
        cached.hasLoadedTopReleases = true
        let now = Date.now
        await cache.save(
            cached,
            for: "target-user",
            scope: .authenticated(token: ""),
            now: now.addingTimeInterval(-301)
        )
        await cache.saveOverview(
            cached,
            for: "target-user",
            scope: .authenticated(token: ""),
            now: now
        )
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: cache
        )

        await model.load()
        XCTAssertEqual(model.snapshot.topReleases.first?.name, "Old album")
        XCTAssertEqual(model.topReleasesPhase, .ready)
        await model.loadTopReleases()

        XCTAssertEqual(model.snapshot.topReleases.first?.name, "Fixture album")
        let calls = await provider.callNames
        XCTAssertEqual(calls, ["releases:target-user"])
    }

    func testManualRefreshOnlyReloadsAlbumsAfterAlbumsWereLoaded() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: UserProfileCache()
        )

        await model.load()
        await model.refresh()
        var calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "releases:target-user" }.count, 0)

        await model.loadTopReleases()
        await model.refresh()
        calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "releases:target-user" }.count, 2)
    }

    func testRefreshDuringInitialAlbumLoadDoesNotDuplicateOrDiscardIt() async {
        let albumGate = UserDetailAlbumGate()
        let provider = UserDetailFixtureProvider(albumGate: albumGate)
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: UserProfileCache()
        )
        await model.load()

        let initialLoad = Task { await model.loadTopReleases() }
        await albumGate.waitUntilRequestArrives()
        await model.refresh()
        await albumGate.releaseRequest()
        await initialLoad.value

        XCTAssertEqual(model.snapshot.topReleases.first?.name, "Fixture album")
        let calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "releases:target-user" }.count, 1)
    }

    func testAlbumCacheSurvivesOverviewAndArtistSaves() async {
        let cache = UserProfileCache()
        var albumSnapshot = UserProfileSnapshot.empty
        albumSnapshot.topReleases = [UserDetailFixtureProvider.release(name: "Preserved album")]
        albumSnapshot.hasLoadedTopReleases = true
        albumSnapshot.savedAt = .now
        await cache.saveTopReleases(
            albumSnapshot,
            for: "target-user",
            scope: .authenticated(token: "")
        )

        var overviewSnapshot = UserProfileSnapshot.empty
        overviewSnapshot.recentListens = [UserDetailFixtureProvider.listen(title: "Fresh history")]
        overviewSnapshot.hasLoadedOverview = true
        overviewSnapshot.savedAt = .now
        await cache.saveOverview(
            overviewSnapshot,
            for: "target-user",
            scope: .authenticated(token: "")
        )

        var artistSnapshot = UserProfileSnapshot.empty
        artistSnapshot.topArtists = [RankedArtist(mbid: nil, name: "Fresh artist", listenCount: 9)]
        artistSnapshot.hasLoadedTopArtists = true
        artistSnapshot.savedAt = .now
        await cache.saveTopArtists(
            artistSnapshot,
            for: "target-user",
            scope: .authenticated(token: "")
        )

        let cached = await cache.value(
            for: "target-user",
            scope: .authenticated(token: "")
        )
        XCTAssertEqual(cached?.snapshot.topReleases.first?.name, "Preserved album")
        XCTAssertEqual(cached?.isTopReleasesFresh, true)
    }

    func testCacheEvictsLeastRecentlyUsedEntryAtCapacity() async {
        let cache = UserProfileCache(maximumEntryCount: 2)
        let start = Date(timeIntervalSince1970: 1_000)
        await cache.save(.empty, for: "first", scope: .authenticated(token: ""), now: start)
        await cache.save(.empty, for: "second", scope: .authenticated(token: ""), now: start.addingTimeInterval(1))
        await cache.save(.empty, for: "third", scope: .authenticated(token: ""), now: start.addingTimeInterval(2))

        let first = await cache.value(for: "first", scope: .authenticated(token: ""), now: start.addingTimeInterval(3))
        let second = await cache.value(for: "second", scope: .authenticated(token: ""), now: start.addingTimeInterval(3))
        let third = await cache.value(for: "third", scope: .authenticated(token: ""), now: start.addingTimeInterval(3))

        XCTAssertNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
    }

    func testSameUserDifferentCredentialsDoNotReuseCachedProfile() async {
        let cache = UserProfileCache()
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "First credential")]
        cached.hasLoadedOverview = true
        await cache.save(
            cached,
            for: "listener",
            scope: .authenticated(token: "first-token")
        )

        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "LISTENER"),
            token: "second-token",
            provider: provider,
            cache: cache
        )
        await model.load()

        XCTAssertEqual(model.snapshot.recentListens.first?.recording.title, "Recent track")
        let calls = await provider.callNames
        XCTAssertEqual(calls, ["recent:LISTENER", "playing:LISTENER", "count:LISTENER"])
    }
}

private actor UserDetailFixtureProvider: ListeningProvider {
    private(set) var callNames: [String] = []
    private let failPlayingNow: Bool
    private let failListenCount: Bool
    private let albumGate: UserDetailAlbumGate?

    init(
        failPlayingNow: Bool = false,
        failListenCount: Bool = false,
        albumGate: UserDetailAlbumGate? = nil
    ) {
        self.failPlayingNow = failPlayingNow
        self.failListenCount = failListenCount
        self.albumGate = albumGate
    }

    func validateToken() async throws -> String { "fixture" }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        callNames.append("recent:\(username)")
        return [Self.listen(title: "Recent track")]
    }

    func playingNow(username: String) async throws -> Listen? {
        callNames.append("playing:\(username)")
        if failPlayingNow { throw UserDetailFixtureError.failed }
        let listen = Self.listen(title: "Playing track")
        return Listen(recording: listen.recording, listenedAt: .now, insertedAt: nil, isPlayingNow: true)
    }

    func listenCount(username: String) async throws -> Int {
        callNames.append("count:\(username)")
        if failListenCount { throw UserDetailFixtureError.failed }
        return 42
    }

    func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
        callNames.append("artists:\(username)")
        return [
            RankedArtist(
                mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab"),
                name: "Fixture artist",
                listenCount: 12
            ),
            RankedArtist(mbid: nil, name: "Unmapped artist", listenCount: 4),
        ]
    }

    func topReleases(username: String, count: Int) async throws -> [RankedRelease] {
        callNames.append("releases:\(username)")
        if let albumGate {
            await albumGate.waitForRelease()
        }
        return [
            Self.release(),
            RankedRelease(
                mbid: nil,
                name: "Unmapped album",
                artistName: "Fixture artist",
                artistMBIDs: [],
                listenCount: 5
            ),
        ]
    }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        ListeningActivity(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    static func listen(title: String) -> Listen {
        Listen(
            recording: Recording(
                identity: .init(mbid: UUID(), msid: nil),
                title: title,
                artistName: "Fixture artist",
                artistMBIDs: [],
                releaseTitle: "Fixture album",
                releaseMBID: UUID(),
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: .now,
            insertedAt: nil,
            isPlayingNow: false
        )
    }

    static func release(name: String = "Fixture album") -> RankedRelease {
        RankedRelease(
            mbid: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"),
            name: name,
            artistName: "Fixture artist",
            artistMBIDs: [UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!],
            listenCount: 24
        )
    }
}

private actor UserDetailAlbumGate {
    private var requestHasArrived = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        requestHasArrived = true
        let waiters = arrivalWaiters
        arrivalWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
    }

    func waitUntilRequestArrives() async {
        guard !requestHasArrived else { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append(continuation)
        }
    }

    func releaseRequest() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private enum UserDetailFixtureError: Error { case failed }
