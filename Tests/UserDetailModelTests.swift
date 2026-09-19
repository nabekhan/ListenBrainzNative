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
        let overviewCalls = await provider.callNames
        XCTAssertEqual(overviewCalls, ["recent:target-user", "playing:target-user", "count:target-user"])

        await model.loadTopArtists()

        XCTAssertEqual(model.snapshot.topArtists.first?.name, "Fixture artist")
        let allCalls = await provider.callNames
        XCTAssertEqual(allCalls.last, "artists:target-user")
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

        let calls = await provider.callNames
        XCTAssertEqual(calls.count, 4)
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

    init(failPlayingNow: Bool = false, failListenCount: Bool = false) {
        self.failPlayingNow = failPlayingNow
        self.failListenCount = failListenCount
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
        return [RankedArtist(mbid: nil, name: "Fixture artist", listenCount: 12)]
    }

    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
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
}

private enum UserDetailFixtureError: Error { case failed }
