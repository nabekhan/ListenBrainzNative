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
            cache: makeIsolatedCache()
        )

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.snapshot.recentListens.count, 1)
        XCTAssertEqual(model.snapshot.playingNow?.recording.title, "Playing track")
        XCTAssertEqual(model.snapshot.listenCount, 42)
        XCTAssertTrue(model.snapshot.topArtists.isEmpty)
        XCTAssertTrue(model.snapshot.topReleases.isEmpty)
        XCTAssertTrue(model.snapshot.topRecordings.isEmpty)
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

        await model.loadTopRecordings()

        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Fixture track")
        let callsAfterTracks = await provider.callNames
        XCTAssertEqual(callsAfterTracks.last, "recordings:target-user")
        let recordingCounts = await provider.topRecordingCounts
        XCTAssertEqual(recordingCounts, [6])
    }

    func testArtistDestinationsRequireCanonicalIdentityWithoutHydration() async throws {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: makeIsolatedCache()
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
            cache: makeIsolatedCache()
        )

        await model.loadTopReleases()

        let mapped = try XCTUnwrap(model.snapshot.topReleases.first)
        let unmapped = try XCTUnwrap(model.snapshot.topReleases.last)
        XCTAssertEqual(mapped.releaseSeed?.mbid, UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"))
        XCTAssertNil(unmapped.releaseSeed)
        let calls = await provider.callNames
        XCTAssertEqual(calls, ["releases:target-user"])
    }

    func testTrackDestinationsRequireRecordingMBIDWithoutHydration() async throws {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: makeIsolatedCache()
        )

        await model.loadTopRecordings()

        let mapped = try XCTUnwrap(model.snapshot.topRecordings.first)
        let unmapped = try XCTUnwrap(model.snapshot.topRecordings.last)
        XCTAssertEqual(mapped.detailDestination?.identity.mbid, UUID(uuidString: "1bf70850-1a66-4e77-b751-51410977ff04"))
        XCTAssertNil(unmapped.detailDestination)
        XCTAssertNotNil(unmapped.releaseMBID)
        let calls = await provider.callNames
        XCTAssertEqual(calls, ["recordings:target-user"])
    }

    func testFreshCacheUsesNormalizedUsernameWithoutNetworkCalls() async {
        let cache = makeIsolatedCache()
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
        let cache = makeIsolatedCache()
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Cached track")]
        cached.topReleases = [UserDetailFixtureProvider.release(name: "Cached album")]
        cached.hasLoadedOverview = true
        cached.hasLoadedTopReleases = true
        cached.savedAt = .now
        await cache.save(
            cached,
            for: "  TARGET-USER  ",
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

    func testFreshCachedTopRecordingsDoNotMakeANetworkCall() async {
        let cache = makeIsolatedCache()
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Cached track")]
        cached.topRecordings = [UserDetailFixtureProvider.recording(title: "Cached ranked track")]
        cached.hasLoadedOverview = true
        cached.hasLoadedTopRecordings = true
        cached.savedAt = .now
        await cache.save(
            cached,
            for: "  TARGET-USER  ",
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
        await model.loadTopRecordings()

        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Cached ranked track")
        let calls = await provider.callNames
        XCTAssertTrue(calls.isEmpty)
    }

    func testOptionalOverviewFailuresKeepLoadedHistory() async {
        let provider = UserDetailFixtureProvider(failPlayingNow: true, failListenCount: true)
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: makeIsolatedCache()
        )

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.snapshot.recentListens.count, 1)
        XCTAssertNil(model.snapshot.playingNow)
        XCTAssertNil(model.snapshot.listenCount)
        XCTAssertTrue(model.snapshot.hasLoadedOverview)
    }

    func testFailedPlayingNowRefreshDoesNotKeepEarlierLiveState() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            provider: provider,
            cache: makeIsolatedCache()
        )
        await model.load()
        XCTAssertNotNil(model.snapshot.playingNow)

        await provider.setPlayingNowFailure(true)
        await model.refresh()

        XCTAssertNil(model.snapshot.playingNow)
        XCTAssertEqual(model.snapshot.recentListens.first?.recording.title, "Recent track")
    }

    func testFailedHistoryRefreshDoesNotKeepEarlierLiveState() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            provider: provider,
            cache: makeIsolatedCache()
        )
        await model.load()
        XCTAssertNotNil(model.snapshot.playingNow)

        await provider.failNextRecentRequest()
        await model.refresh()

        XCTAssertNil(model.snapshot.playingNow)
        XCTAssertTrue(model.isShowingSavedProfile)
        XCTAssertEqual(model.snapshot.recentListens.first?.recording.title, "Recent track")
    }

    func testRepeatedAppearancesDoNotDuplicateRequests() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: makeIsolatedCache()
        )

        await model.load()
        await model.load()
        await model.loadTopArtists()
        await model.loadTopArtists()
        await model.loadTopReleases()
        await model.loadTopReleases()
        await model.loadTopRecordings()
        await model.loadTopRecordings()

        let calls = await provider.callNames
        XCTAssertEqual(calls.count, 6)
        XCTAssertEqual(calls.filter { $0 == "releases:target-user" }.count, 1)
        XCTAssertEqual(calls.filter { $0 == "recordings:target-user" }.count, 1)
    }

    func testCacheFreshnessExpiresWithoutLosingStaleValue() async {
        let cache = makeIsolatedCache(timeToLive: 300)
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
        let cache = makeIsolatedCache(timeToLive: 300)
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
            cache: makeIsolatedCache()
        )

        await model.load()
        await model.loadTopArtists()
        await model.refresh()

        let calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "artists:target-user" }.count, 2)
        XCTAssertEqual(calls.count, 8)
    }

    func testStaleTopReleasesRefreshWithoutReloadingFreshOverview() async {
        let cache = makeIsolatedCache(timeToLive: 300)
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

    func testStaleTopRecordingsRefreshWithoutReloadingFreshOverview() async {
        let cache = makeIsolatedCache(timeToLive: 300)
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Cached track")]
        cached.listenCount = 99
        cached.topRecordings = [UserDetailFixtureProvider.recording(title: "Old track")]
        cached.hasLoadedOverview = true
        cached.hasLoadedTopRecordings = true
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
        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Old track")
        XCTAssertEqual(model.topRecordingsPhase, .ready)
        await model.loadTopRecordings()

        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Fixture track")
        let calls = await provider.callNames
        XCTAssertEqual(calls, ["recordings:target-user"])
    }

    func testFailedStaleTrackRefreshKeepsRowsAndAllowsExplicitRetry() async {
        let cache = makeIsolatedCache(timeToLive: 300)
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Cached track")]
        cached.topRecordings = [UserDetailFixtureProvider.recording(title: "Saved track")]
        cached.hasLoadedOverview = true
        cached.hasLoadedTopRecordings = true
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
        let provider = UserDetailFixtureProvider(recordingFailures: 1)
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: cache
        )

        await model.load()
        await model.loadTopRecordings()

        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Saved track")
        XCTAssertEqual(model.topRecordingsPhase, .ready)
        XCTAssertNotNil(model.topRecordingsErrorMessage)

        await model.loadTopRecordings()
        var calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "recordings:target-user" }.count, 1)

        await model.loadTopRecordings(retrying: true)

        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Fixture track")
        XCTAssertNil(model.topRecordingsErrorMessage)
        calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "recordings:target-user" }.count, 2)
        let counts = await provider.topRecordingCounts
        XCTAssertEqual(counts, [6, 6])
    }

    func testManualRefreshOnlyReloadsAlbumsAfterAlbumsWereLoaded() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: makeIsolatedCache()
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

    func testManualRefreshOnlyReloadsTracksAfterTracksWereLoaded() async {
        let provider = UserDetailFixtureProvider()
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: makeIsolatedCache()
        )

        await model.load()
        await model.refresh()
        var calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "recordings:target-user" }.count, 0)

        await model.loadTopRecordings()
        await model.refresh()
        calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "recordings:target-user" }.count, 2)
    }

    func testRefreshDuringInitialAlbumLoadDoesNotDuplicateOrDiscardIt() async {
        let albumGate = UserDetailAlbumGate()
        let provider = UserDetailFixtureProvider(albumGate: albumGate)
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: makeIsolatedCache()
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

    func testRefreshDuringInitialTrackLoadDoesNotDuplicateOrDiscardIt() async {
        let recordingGate = UserDetailAlbumGate()
        let provider = UserDetailFixtureProvider(recordingGate: recordingGate)
        let model = UserDetailModel(
            user: SearchUser(username: "target-user"),
            token: "",
            provider: provider,
            cache: makeIsolatedCache()
        )
        await model.load()

        let initialLoad = Task { await model.loadTopRecordings() }
        await recordingGate.waitUntilRequestArrives()
        await model.refresh()
        await recordingGate.releaseRequest()
        await initialLoad.value

        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Fixture track")
        let calls = await provider.callNames
        XCTAssertEqual(calls.filter { $0 == "recordings:target-user" }.count, 1)
    }

    func testAlbumCacheSurvivesOverviewAndArtistSaves() async {
        let cache = makeIsolatedCache()
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

    func testTrackCacheSurvivesOverviewArtistAndAlbumSaves() async {
        let cache = makeIsolatedCache()
        var trackSnapshot = UserProfileSnapshot.empty
        trackSnapshot.topRecordings = [UserDetailFixtureProvider.recording(title: "Preserved track")]
        trackSnapshot.hasLoadedTopRecordings = true
        trackSnapshot.savedAt = .now
        await cache.saveTopRecordings(
            trackSnapshot,
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

        var albumSnapshot = UserProfileSnapshot.empty
        albumSnapshot.topReleases = [UserDetailFixtureProvider.release(name: "Fresh album")]
        albumSnapshot.hasLoadedTopReleases = true
        albumSnapshot.savedAt = .now
        await cache.saveTopReleases(
            albumSnapshot,
            for: "target-user",
            scope: .authenticated(token: "")
        )

        let cached = await cache.value(
            for: "target-user",
            scope: .authenticated(token: "")
        )
        XCTAssertEqual(cached?.snapshot.topRecordings.first?.title, "Preserved track")
        XCTAssertEqual(cached?.isTopRecordingsFresh, true)
    }

    func testCacheEvictsLeastRecentlyUsedEntryAtCapacity() async {
        let cache = makeIsolatedCache(maximumEntryCount: 2)
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

    func testPublicProfileCacheIsSharedAcrossAnonymousAndAuthenticatedCallers() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UserProfileCache(rootDirectory: root)
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "First credential")]
        cached.topRecordings = [UserDetailFixtureProvider.recording(title: "First credential track")]
        cached.hasLoadedOverview = true
        cached.hasLoadedTopRecordings = true
        await cache.save(
            cached,
            for: "listener",
            scope: .authenticated(token: "first-token")
        )

        let cachedValue = await cache.value(for: "  LISTENER  ", scope: .authenticated(token: "second-token"))

        XCTAssertEqual(cachedValue?.snapshot.recentListens.first?.recording.title, "First credential")
        XCTAssertEqual(cachedValue?.snapshot.topRecordings.first?.title, "First credential track")
    }

    func testPublicProfileCacheRestoresStaleSectionsAfterRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let savedAt = Date(timeIntervalSince1970: 10_000)
        let now = savedAt.addingTimeInterval(301)
        var snapshot = UserProfileSnapshot.empty
        snapshot.recentListens = [UserDetailFixtureProvider.listen(title: "Saved history")]
        snapshot.topArtists = [RankedArtist(mbid: nil, name: "Saved artist", listenCount: 3)]
        snapshot.hasLoadedOverview = true
        snapshot.hasLoadedTopArtists = true
        snapshot.savedAt = savedAt

        let initialCache = UserProfileCache(timeToLive: 300, rootDirectory: root)
        await initialCache.save(snapshot, for: "  PUBLIC-LISTENER ", now: savedAt)
        await initialCache.saveOverview(snapshot, for: "public-listener", now: now)

        let relaunchedCache = UserProfileCache(timeToLive: 300, rootDirectory: root)
        let restored = await relaunchedCache.value(for: "Public-Listener", now: now)
        XCTAssertEqual(restored?.snapshot.recentListens.first?.recording.title, "Saved history")
        XCTAssertEqual(restored?.snapshot.topArtists.first?.name, "Saved artist")
        XCTAssertTrue(restored?.isOverviewFresh == true)
        XCTAssertTrue(restored?.isTopArtistsFresh == false)
    }

    func testPublicProfileCacheNeverPersistsPlayingNow() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var snapshot = UserProfileSnapshot.empty
        snapshot.recentListens = [UserDetailFixtureProvider.listen(title: "Saved history")]
        let liveListen = UserDetailFixtureProvider.listen(title: "Live-only title")
        snapshot.playingNow = Listen(
            recording: liveListen.recording,
            listenedAt: .now,
            insertedAt: nil,
            isPlayingNow: true
        )
        snapshot.hasLoadedOverview = true
        let initialCache = UserProfileCache(rootDirectory: root)
        await initialCache.save(snapshot, for: "listener")

        let inMemory = await initialCache.value(for: "listener")
        XCTAssertNil(inMemory?.snapshot.playingNow)
        let cacheFileValue = await initialCache.fileURL(for: "listener")
        let cacheFile = try XCTUnwrap(cacheFileValue)
        XCTAssertFalse(String(decoding: try Data(contentsOf: cacheFile), as: UTF8.self).contains("Live-only title"))

        let relaunchedCache = UserProfileCache(rootDirectory: root)
        let restored = await relaunchedCache.value(for: "listener")
        XCTAssertNil(restored?.snapshot.playingNow)
        XCTAssertEqual(restored?.snapshot.recentListens.first?.recording.title, "Saved history")
    }

    func testPublicProfileCacheUsesCanonicalFixedSafeFilename() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UserProfileCache(rootDirectory: root)
        let firstURL = await cache.fileURL(for: "  MixedCase.Listener  ")
        let secondURL = await cache.fileURL(for: "mixedcase.listener")
        let first = try XCTUnwrap(firstURL)
        let second = try XCTUnwrap(secondURL)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.pathExtension, "json")
        XCTAssertFalse(first.lastPathComponent.localizedCaseInsensitiveContains("mixedcase"))
        XCTAssertTrue(first.lastPathComponent.range(of: "^v1-[a-f0-9]{64}\\.json$", options: .regularExpression) != nil)
    }

    func testPublicProfileCacheNormalizesEquivalentUnicodeUsernames() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UserProfileCache(rootDirectory: root)
        let composedURL = await cache.fileURL(for: "Caf\u{00E9}")
        let decomposedURL = await cache.fileURL(for: "Cafe\u{0301}")

        XCTAssertEqual(try XCTUnwrap(composedURL), try XCTUnwrap(decomposedURL))
    }

    func testCorruptPublicProfileCacheIsDiscarded() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let initialCache = UserProfileCache(rootDirectory: root)
        var snapshot = UserProfileSnapshot.empty
        snapshot.hasLoadedOverview = true
        await initialCache.save(snapshot, for: "listener")
        let cachedURL = await initialCache.fileURL(for: "listener")
        let url = try XCTUnwrap(cachedURL)
        try Data("not a profile cache".utf8).write(to: url, options: .atomic)

        let relaunchedCache = UserProfileCache(rootDirectory: root)
        let restored = await relaunchedCache.value(for: "listener")
        XCTAssertNil(restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path()))
    }

    func testOversizedPublicProfileCacheIsDiscarded() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UserProfileCache(rootDirectory: root)
        let cachedURL = await cache.fileURL(for: "listener")
        let url = try XCTUnwrap(cachedURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4 * 1_024 * 1_024 + 1).write(to: url, options: .atomic)

        let relaunchedCache = UserProfileCache(rootDirectory: root)
        let restored = await relaunchedCache.value(for: "listener")
        XCTAssertNil(restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path()))
    }

    func testPublicProfileCacheEvictsDiskEntriesAtConfiguredBounds() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UserProfileCache(maximumEntryCount: 2, rootDirectory: root)
        for username in ["one", "two", "three"] {
            var snapshot = UserProfileSnapshot.empty
            snapshot.hasLoadedOverview = true
            await cache.save(snapshot, for: username)
        }
        let firstURL = await cache.fileURL(for: "one")
        let directory = try XCTUnwrap(firstURL?.deletingLastPathComponent())
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let totalBytes = try files.reduce(0) { result, url in
            result + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertLessThanOrEqual(files.count, 2)
        XCTAssertLessThanOrEqual(totalBytes, 16 * 1_024 * 1_024)
    }

    func testPublicProfileCacheAccessDoesNotExtendHardRetention() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let savedAt = Date(timeIntervalSince1970: 20_000)
        var snapshot = UserProfileSnapshot.empty
        snapshot.recentListens = [UserDetailFixtureProvider.listen(title: "Saved history")]
        snapshot.hasLoadedOverview = true
        snapshot.savedAt = savedAt
        let cache = UserProfileCache(rootDirectory: root, hardRetention: 10)
        await cache.save(snapshot, for: "listener", now: savedAt)

        let recentlyAccessed = await cache.value(for: "listener", now: savedAt.addingTimeInterval(9))
        XCTAssertNotNil(recentlyAccessed)

        let relaunchedCache = UserProfileCache(rootDirectory: root, hardRetention: 10)
        let expired = await relaunchedCache.value(for: "listener", now: savedAt.addingTimeInterval(10))
        XCTAssertNil(expired)
    }

    func testRefreshingOverviewDoesNotExtendExpiredRankings() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let savedAt = Date(timeIntervalSince1970: 30_000)
        var snapshot = UserProfileSnapshot.empty
        snapshot.recentListens = [UserDetailFixtureProvider.listen(title: "Initial history")]
        snapshot.topArtists = [RankedArtist(mbid: nil, name: "Expired artist", listenCount: 3)]
        snapshot.hasLoadedOverview = true
        snapshot.hasLoadedTopArtists = true
        snapshot.savedAt = savedAt
        let cache = UserProfileCache(rootDirectory: root, hardRetention: 10)
        await cache.save(snapshot, for: "listener", now: savedAt)
        await cache.saveOverview(snapshot, for: "listener", now: savedAt.addingTimeInterval(5))

        var refreshedOverview = snapshot
        refreshedOverview.recentListens = [UserDetailFixtureProvider.listen(title: "Fresh history")]
        await cache.saveOverview(refreshedOverview, for: "listener", now: savedAt.addingTimeInterval(11))

        let relaunchedCache = UserProfileCache(rootDirectory: root, hardRetention: 10)
        let restored = await relaunchedCache.value(for: "listener", now: savedAt.addingTimeInterval(11))
        XCTAssertEqual(restored?.snapshot.recentListens.first?.recording.title, "Fresh history")
        XCTAssertTrue(restored?.snapshot.topArtists.isEmpty == true)
        XCTAssertFalse(restored?.snapshot.hasLoadedTopArtists == true)
        XCTAssertFalse(restored?.isTopArtistsFresh == true)
        let cacheFileValue = await relaunchedCache.fileURL(for: "listener")
        let cacheFile = try XCTUnwrap(cacheFileValue)
        XCTAssertFalse(String(decoding: try Data(contentsOf: cacheFile), as: UTF8.self).contains("Expired artist"))
    }

    func testOversizedSavePreservesPreviousValidDiskSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UserProfileCache(rootDirectory: root, maximumEntryBytes: 4_096)
        var previous = UserProfileSnapshot.empty
        previous.recentListens = [UserDetailFixtureProvider.listen(title: "Previous history")]
        previous.hasLoadedOverview = true
        await cache.save(previous, for: "listener")

        var oversized = previous
        oversized.recentListens = [
            UserDetailFixtureProvider.listen(title: String(repeating: "x", count: 8_192)),
        ]
        await cache.save(oversized, for: "listener")

        let relaunchedCache = UserProfileCache(rootDirectory: root, maximumEntryBytes: 4_096)
        let restored = await relaunchedCache.value(for: "listener")
        XCTAssertEqual(restored?.snapshot.recentListens.first?.recording.title, "Previous history")
    }

    func testRemoveAllRecreatesUsableExcludedCacheDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UserProfileCache(rootDirectory: root)
        await cache.save(.empty, for: "before")

        await cache.removeAll()
        await cache.save(.empty, for: "after")

        let savedFileURL = await cache.fileURL(for: "after")
        let fileURL = try XCTUnwrap(savedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path()))
        let directoryValues = try fileURL.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(directoryValues.isExcludedFromBackup, true)
    }

    func testStalePublicProfileSurvivesRefreshFailureAndRetries() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UserProfileCache(timeToLive: 0, rootDirectory: root)
        var cached = UserProfileSnapshot.empty
        cached.recentListens = [UserDetailFixtureProvider.listen(title: "Saved track")]
        cached.hasLoadedOverview = true
        await cache.save(cached, for: "target-user")
        let provider = UserDetailFixtureProvider(recentFailures: 1)
        let model = UserDetailModel(user: SearchUser(username: "target-user"), provider: provider, cache: cache)

        await model.load()

        XCTAssertEqual(model.snapshot.recentListens.first?.recording.title, "Saved track")
        XCTAssertTrue(model.isShowingSavedProfile)
        XCTAssertNotNil(model.profileRefreshErrorMessage)

        await model.refresh()
        XCTAssertEqual(model.snapshot.recentListens.first?.recording.title, "Recent track")
        XCTAssertFalse(model.isShowingSavedProfile)
        XCTAssertNil(model.profileRefreshErrorMessage)
    }

    private func makeIsolatedCache(
        timeToLive: TimeInterval = 5 * 60,
        maximumEntryCount: Int = 100
    ) -> UserProfileCache {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return UserProfileCache(
            timeToLive: timeToLive,
            maximumEntryCount: maximumEntryCount,
            rootDirectory: root
        )
    }
}

private actor UserDetailFixtureProvider: ListeningProvider {
    private(set) var callNames: [String] = []
    private(set) var topRecordingCounts: [Int] = []
    private var failPlayingNow: Bool
    private let failListenCount: Bool
    private let albumGate: UserDetailAlbumGate?
    private let recordingGate: UserDetailAlbumGate?
    private var recordingFailuresRemaining: Int
    private var recentFailuresRemaining: Int

    init(
        failPlayingNow: Bool = false,
        failListenCount: Bool = false,
        albumGate: UserDetailAlbumGate? = nil,
        recordingGate: UserDetailAlbumGate? = nil,
        recordingFailures: Int = 0,
        recentFailures: Int = 0
    ) {
        self.failPlayingNow = failPlayingNow
        self.failListenCount = failListenCount
        self.albumGate = albumGate
        self.recordingGate = recordingGate
        self.recordingFailuresRemaining = recordingFailures
        self.recentFailuresRemaining = recentFailures
    }

    func validateToken() async throws -> String { "fixture" }

    func setPlayingNowFailure(_ shouldFail: Bool) {
        failPlayingNow = shouldFail
    }

    func failNextRecentRequest() {
        recentFailuresRemaining = 1
    }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        callNames.append("recent:\(username)")
        if recentFailuresRemaining > 0 {
            recentFailuresRemaining -= 1
            throw UserDetailFixtureError.failed
        }
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
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
        callNames.append("recordings:\(username)")
        topRecordingCounts.append(count)
        if let recordingGate {
            await recordingGate.waitForRelease()
        }
        if recordingFailuresRemaining > 0 {
            recordingFailuresRemaining -= 1
            throw UserDetailFixtureError.failed
        }
        return [
            Self.recording(),
            RankedRecording(
                mbid: nil,
                releaseMBID: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"),
                title: "Unmapped track",
                artistName: "Fixture artist",
                artistMBIDs: [],
                releaseTitle: "Fixture album",
                listenCount: 5
            ),
        ]
    }
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

    static func recording(name: String = "Fixture track", title: String? = nil) -> RankedRecording {
        RankedRecording(
            mbid: UUID(uuidString: "1bf70850-1a66-4e77-b751-51410977ff04"),
            releaseMBID: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"),
            title: title ?? name,
            artistName: "Fixture artist",
            artistMBIDs: [UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!],
            releaseTitle: "Fixture album",
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
