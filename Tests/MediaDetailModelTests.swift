import Foundation
import XCTest
@testable import Brainz

@MainActor
final class MediaDetailModelTests: XCTestCase {
    func testCoverArtURLsUseCanonicalLowercaseMBIDs() {
        let mbid = UUID(uuidString: "1a33443c-3fff-450f-8298-efbc65659d32")!

        XCTAssertEqual(
            CoverArtArchiveURL.release(mbid)?.absoluteString,
            "https://coverartarchive.org/release/1a33443c-3fff-450f-8298-efbc65659d32/front-500"
        )
        XCTAssertEqual(
            CoverArtArchiveURL.releaseGroup(mbid)?.absoluteString,
            "https://coverartarchive.org/release-group/1a33443c-3fff-450f-8298-efbc65659d32/front-500"
        )
    }

    func testReleaseGroupLoadsOnceAndPopulatesCache() async {
        let mbid = UUID()
        let seed = releaseSeed(mbid: mbid)
        let cache = EntityDetailCache<UUID, ReleaseGroupDetail>()
        let firstProvider = MediaDetailFixtureProvider(release: releaseDetail(mbid: mbid, title: "Loaded title"))
        let first = ReleaseGroupDetailModel(
            seed: seed,
            token: "",
            provider: firstProvider,
            cache: cache
        )

        await first.load()
        await first.load()

        XCTAssertEqual(first.phase, .ready)
        XCTAssertEqual(first.detail?.title, "Loaded title")
        let firstCalls = await firstProvider.releaseCalls
        XCTAssertEqual(firstCalls, [mbid])

        let secondProvider = MediaDetailFixtureProvider(release: releaseDetail(mbid: mbid, title: "Network title"))
        let second = ReleaseGroupDetailModel(
            seed: seed,
            token: "",
            provider: secondProvider,
            cache: cache
        )
        await second.load()

        XCTAssertEqual(second.detail?.title, "Loaded title")
        let secondCalls = await secondProvider.releaseCalls
        XCTAssertTrue(secondCalls.isEmpty)
    }

    func testMissingReleaseMetadataKeepsSeedAvailable() async {
        let seed = releaseSeed(mbid: UUID())
        let provider = MediaDetailFixtureProvider(release: nil)
        let model = ReleaseGroupDetailModel(
            seed: seed,
            token: "",
            provider: provider,
            cache: EntityDetailCache()
        )

        await model.load()

        XCTAssertEqual(model.phase, .unavailable)
        XCTAssertNil(model.detail)
        XCTAssertEqual(model.seed.title, "Seed title")
    }

    func testStaleReleaseValueSurvivesRefreshFailure() async {
        let mbid = UUID()
        let cache = EntityDetailCache<UUID, ReleaseGroupDetail>(timeToLive: -1)
        await cache.save(releaseDetail(mbid: mbid, title: "Stale title"), for: mbid)
        let provider = MediaDetailFixtureProvider(
            release: nil,
            playlist: nil,
            error: MediaDetailFixtureError.failed
        )
        let model = ReleaseGroupDetailModel(
            seed: releaseSeed(mbid: mbid),
            token: "",
            provider: provider,
            cache: cache
        )

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.detail?.title, "Stale title")
        XCTAssertNotNil(model.refreshMessage)
    }

    func testInvalidPlaylistIdentifierNeverCallsProvider() async {
        let seed = SearchPlaylist(
            title: "Invalid",
            creator: "listener",
            annotation: nil,
            identifier: "https://example.com/playlist/\(UUID().uuidString)",
            isPublic: true,
            lastModifiedAt: nil
        )
        let provider = MediaDetailFixtureProvider(playlist: playlistDetail(mbid: UUID()))
        let model = PlaylistDetailModel(
            seed: seed,
            token: "",
            provider: provider,
            cache: EntityDetailCache()
        )

        await model.load()

        guard case .failed = model.phase else {
            return XCTFail("Expected invalid identity to fail before transport")
        }
        let invalidCalls = await provider.playlistCalls
        XCTAssertTrue(invalidCalls.isEmpty)
    }

    func testPlaylistIdentifierRequiresCanonicalURLShape() {
        let mbid = UUID()
        XCTAssertEqual(playlistSeed(mbid: mbid).playlistMBID, mbid)

        let extraPath = SearchPlaylist(
            title: "Extra",
            creator: "listener",
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(mbid.uuidString)/edit",
            isPublic: true,
            lastModifiedAt: nil
        )
        let query = SearchPlaylist(
            title: "Query",
            creator: "listener",
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(mbid.uuidString)?token=unexpected",
            isPublic: true,
            lastModifiedAt: nil
        )

        XCTAssertNil(extraPath.playlistMBID)
        XCTAssertNil(query.playlistMBID)
        XCTAssertNil(extraPath.listenBrainzURL)
    }

    func testPlaylistLoadsAllTracksWithOneProviderCall() async {
        let mbid = UUID()
        let tracks = (1 ... 120).map { position in
            PlaylistTrack(
                position: position,
                recording: Recording(
                    identity: .init(mbid: UUID(), msid: nil),
                    title: "Track \(position)",
                    artistName: "Artist",
                    artistMBIDs: [],
                    releaseTitle: "Release",
                    releaseMBID: nil,
                    releaseGroupMBID: nil,
                    artworkReleaseMBID: nil,
                    durationMilliseconds: 180_000,
                    source: nil
                ),
                addedAt: nil,
                addedBy: nil
            )
        }
        let detail = playlistDetail(mbid: mbid, tracks: tracks)
        let provider = MediaDetailFixtureProvider(playlist: detail)
        let model = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            token: "",
            provider: provider,
            cache: EntityDetailCache()
        )

        await model.load()
        _ = model.detail?.tracks.map(\.recording.title)

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.detail?.tracks.count, 120)
        XCTAssertEqual(model.detail?.totalDurationMilliseconds, 21_600_000)
        let calls = await provider.playlistCalls
        XCTAssertEqual(calls, [mbid])
    }

    func testPlaylistFreshCacheAvoidsTransport() async {
        let mbid = UUID()
        let cached = playlistDetail(mbid: mbid)
        let cache = EntityDetailCache<UUID, PlaylistDetail>()
        await cache.save(cached, for: mbid)
        let provider = MediaDetailFixtureProvider(playlist: playlistDetail(mbid: mbid, title: "Network"))
        let model = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            token: "",
            provider: provider,
            cache: cache
        )

        await model.load()

        XCTAssertEqual(model.detail?.title, "Fixture playlist")
        let calls = await provider.playlistCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testDetailCacheEvictsLeastRecentlyUsedValue() async {
        let cache = EntityDetailCache<Int, String>(maximumEntryCount: 2)
        let start = Date(timeIntervalSince1970: 1_000)
        await cache.save("one", for: 1, now: start)
        await cache.save("two", for: 2, now: start.addingTimeInterval(1))
        _ = await cache.value(for: 1, now: start.addingTimeInterval(2))
        await cache.save("three", for: 3, now: start.addingTimeInterval(3))

        let first = await cache.value(for: 1)
        let second = await cache.value(for: 2)
        let third = await cache.value(for: 3)
        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertNotNil(third)
    }

    private func releaseSeed(mbid: UUID) -> SearchReleaseGroup {
        SearchReleaseGroup(
            mbid: mbid,
            title: "Seed title",
            artistName: "Seed artist",
            primaryType: "Album",
            firstReleaseDate: "2024-01-01"
        )
    }

    private func releaseDetail(mbid: UUID, title: String) -> ReleaseGroupDetail {
        ReleaseGroupDetail(
            mbid: mbid,
            title: title,
            artistCreditName: "Fixture artist",
            artists: [],
            releaseDate: nil,
            primaryType: "Album",
            tags: ["ambient"],
            artworkReleaseMBID: nil
        )
    }

    private func playlistSeed(mbid: UUID) -> SearchPlaylist {
        SearchPlaylist(
            title: "Fixture playlist",
            creator: "listener",
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(mbid.uuidString)",
            isPublic: true,
            lastModifiedAt: nil
        )
    }

    private func playlistDetail(
        mbid: UUID,
        title: String = "Fixture playlist",
        tracks: [PlaylistTrack] = []
    ) -> PlaylistDetail {
        PlaylistDetail(
            mbid: mbid,
            title: title,
            creator: "listener",
            annotation: "Description",
            createdAt: nil,
            lastModifiedAt: nil,
            isPublic: true,
            createdFor: nil,
            collaborators: [],
            copiedFrom: nil,
            tracks: tracks
        )
    }
}

private actor MediaDetailFixtureProvider: ReleaseDetailProviding, PlaylistDetailProviding {
    private(set) var releaseCalls: [UUID] = []
    private(set) var playlistCalls: [UUID] = []
    private let releaseValue: ReleaseGroupDetail?
    private let playlistValue: PlaylistDetail?
    private let error: (any Error & Sendable)?

    init(
        release: ReleaseGroupDetail? = nil,
        playlist: PlaylistDetail? = nil,
        error: (any Error & Sendable)? = nil
    ) {
        self.releaseValue = release
        self.playlistValue = playlist
        self.error = error
    }

    func releaseGroup(mbid: UUID) async throws -> ReleaseGroupDetail? {
        releaseCalls.append(mbid)
        if let error { throw error }
        return releaseValue
    }

    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        playlistCalls.append(mbid)
        if let error { throw error }
        guard let playlistValue else { throw MediaDetailFixtureError.missingFixture }
        return playlistValue
    }
}

private enum MediaDetailFixtureError: LocalizedError, Sendable {
    case failed
    case missingFixture

    var errorDescription: String? { "Fixture request failed." }
}
