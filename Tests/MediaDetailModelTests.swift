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

    func testConcreteReleaseLoadsOrderedTracksWithOneProviderCall() async {
        let mbid = UUID()
        let detail = concreteReleaseDetail(mbid: mbid, trackTitles: ["Opening", "Second", "Finale"])
        let provider = MediaDetailFixtureProvider(concreteRelease: detail)
        let model = ReleaseDetailModel(
            seed: concreteReleaseSeed(mbid: mbid),
            provider: provider,
            cache: EntityDetailCache()
        )

        await model.load()
        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.detail?.media.flatMap(\.tracks).map(\.recording.title), ["Opening", "Second", "Finale"])
        let calls = await provider.concreteReleaseCalls
        XCTAssertEqual(calls, [mbid])
    }

    func testConcreteReleaseRequestUsesSingleOrderedMediaLookup() throws {
        let releaseID = UUID(uuidString: "1a33443c-3fff-450f-8298-efbc65659d32")!
        let groupID = UUID(uuidString: "2a33443c-3fff-450f-8298-efbc65659d32")!
        let recordingID = UUID(uuidString: "3a33443c-3fff-450f-8298-efbc65659d32")!
        let request = try MusicBrainzSearchClient.makeReleaseRequest(mbid: releaseID, userAgent: "Tests")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(request.url?.path, "/ws/2/release/1a33443c-3fff-450f-8298-efbc65659d32")
        XCTAssertEqual(query?.first(where: { $0.name == "inc" })?.value, "artist-credits+recordings+media+release-groups+labels")

        let json = """
        {
          "title": "Edition", "artist-credit": [{"name": "Artist"}],
          "release-group": {"id": "\(groupID.uuidString)", "primary-type": "EP"},
          "media": [
            {"position": 2, "format": "CD", "tracks": [
              {"position": 8, "number": "8", "title": "Source first", "length": 123000, "recording": {"id": "\(recordingID.uuidString)", "title": "Source first"}},
              {"position": 1, "number": "1", "title": "Source second", "length": 234000}
            ]},
            {"position": 1, "format": "CD", "tracks": [
              {"position": 1, "number": "1", "title": "Prelude", "length": 42000}
            ]}
          ]
        }
        """
        let detail = try MusicBrainzSearchClient.decodeRelease(
            data: Data(json.utf8),
            mbid: releaseID,
            context: concreteReleaseSeed(mbid: releaseID)
        )

        XCTAssertEqual(detail.releaseGroupMBID, groupID)
        XCTAssertEqual(detail.releaseGroupPrimaryType, "EP")
        XCTAssertEqual(detail.media.map(\.position), [1, 2])
        XCTAssertEqual(detail.media.flatMap(\.tracks).map(\.recording.title), ["Prelude", "Source second", "Source first"])
        XCTAssertNil(detail.media.flatMap(\.tracks).first?.recording.identity.mbid)
        XCTAssertEqual(detail.media.flatMap(\.tracks).last?.recording.identity.mbid, recordingID)
    }

    func testConcreteReleaseIdentityIgnoresSourcePresentationContext() throws {
        let mbid = UUID()
        let rankedSeed = concreteReleaseSeed(mbid: mbid)
        let freshRelease = FreshRelease(
            releaseMBID: mbid,
            releaseGroupMBID: UUID(),
            title: "A newer title",
            artistName: "Another credit",
            artistMBIDs: [UUID()],
            releaseDate: "2026-09-17",
            primaryType: "EP",
            secondaryType: "Live",
            tags: ["dream pop", "indie"],
            confidence: 3,
            listenCount: 24,
            artworkReleaseMBID: UUID(),
            sourcePosition: 7
        )
        let freshSeed = try XCTUnwrap(ReleaseSeed(freshRelease: freshRelease))

        XCTAssertEqual(rankedSeed, freshSeed)
        XCTAssertEqual(Set([rankedSeed, freshSeed]).count, 1)
        XCTAssertEqual(freshSeed.discoveryContext?.tags, ["dream pop", "indie"])
        XCTAssertEqual(freshSeed.discoveryContext?.confidence, 3)
        XCTAssertEqual(freshSeed.discoveryContext?.listenCount, 24)
        XCTAssertTrue(ReleaseDiscoveryContext(tags: [], confidence: 1, listenCount: nil).hasVisibleContent)
    }

    func testStaleConcreteReleaseSurvivesRefreshFailure() async {
        let mbid = UUID()
        let cache = EntityDetailCache<UUID, ReleaseDetail>(timeToLive: -1)
        await cache.save(concreteReleaseDetail(mbid: mbid, trackTitles: ["Cached"]), for: mbid)
        let provider = MediaDetailFixtureProvider(error: MediaDetailFixtureError.failed)
        let model = ReleaseDetailModel(
            seed: concreteReleaseSeed(mbid: mbid),
            provider: provider,
            cache: cache
        )

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.detail?.media.flatMap(\.tracks).map(\.recording.title), ["Cached"])
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
            account: Account(username: "listener", token: ""),
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
            account: Account(username: "listener", token: ""),
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
        let account = Account(username: "listener", token: "")
        let cache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        await cache.save(cached, for: .init(mbid: mbid, accessScope: .init(account: account)))
        let provider = MediaDetailFixtureProvider(playlist: playlistDetail(mbid: mbid, title: "Network"))
        let model = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            account: account,
            provider: provider,
            cache: cache
        )

        await model.load()

        XCTAssertEqual(model.detail?.title, "Fixture playlist")
        let calls = await provider.playlistCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testPlaylistEditRevalidationUsesFreshMutationInspection() async throws {
        let mbid = UUID()
        let provider = MediaDetailFixtureProvider(playlist: playlistDetail(mbid: mbid))
        let model = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            account: Account(username: "listener", token: "token"),
            provider: provider,
            cache: EntityDetailCache()
        )

        let detail = try await model.revalidateForEditing()

        XCTAssertEqual(detail.mbid, mbid)
        let ordinaryCalls = await provider.playlistCalls
        let inspectionCalls = await provider.playlistInspectionCalls
        XCTAssertTrue(ordinaryCalls.isEmpty)
        XCTAssertEqual(inspectionCalls, [mbid])
    }

    func testPlaylistCacheIsScopedByViewerAccess() async {
        let mbid = UUID()
        let cache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let authenticated = Account(username: "listener", token: "private-token")
        await cache.save(
            playlistDetail(mbid: mbid, title: "Private cached title"),
            for: .init(mbid: mbid, accessScope: .init(account: authenticated))
        )

        let publicAccount = Account(username: "listener", token: "")
        let publicProvider = MediaDetailFixtureProvider(
            playlist: playlistDetail(mbid: mbid, title: "Public transport title")
        )
        let publicModel = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            account: publicAccount,
            provider: publicProvider,
            cache: cache
        )

        await publicModel.load()

        XCTAssertEqual(publicModel.detail?.title, "Public transport title")
        let calls = await publicProvider.playlistCalls
        XCTAssertEqual(calls, [mbid])
    }

    func testRevokedPlaylistAccessPurgesExpiredPrivateDetail() async {
        let mbid = UUID()
        let account = Account(username: "listener", token: "private-token")
        let cache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>(timeToLive: -1)
        let key = PlaylistDetailCacheKey(mbid: mbid, accessScope: .init(account: account))
        await cache.save(
            playlistDetail(mbid: mbid, title: "Private cached title", isPublic: false),
            for: key
        )
        let model = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            account: account,
            provider: MediaDetailFixtureProvider(error: MediaDetailError.playlistUnavailable),
            cache: cache
        )

        await model.load()

        XCTAssertNil(model.detail)
        XCTAssertTrue(model.accessWasLost)
        guard case .failed = model.phase else {
            return XCTFail("Expected revoked access to remove stale private detail")
        }
        let cached = await cache.value(for: key)
        XCTAssertNil(cached)
    }

    func testConfirmedPrivateEditEvictsFormerPublicDetailBeforeTokenlessLoad() async {
        let mbid = UUID()
        let cache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let authenticated = Account(username: "listener", token: "private-token")
        let publicAccount = Account(username: "listener", token: "")
        let formerlyPublic = playlistDetail(mbid: mbid, title: "Formerly public")
        await cache.save(
            formerlyPublic,
            for: .init(mbid: mbid, accessScope: .init(account: authenticated))
        )
        await cache.save(
            formerlyPublic,
            for: .init(mbid: mbid, accessScope: .init(account: publicAccount))
        )
        let authenticatedProvider = MediaDetailFixtureProvider(
            playlist: playlistDetail(mbid: mbid, title: "Private now", isPublic: false)
        )
        let authenticatedModel = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            account: authenticated,
            provider: authenticatedProvider,
            cache: cache
        )
        await authenticatedModel.load()

        await authenticatedModel.reconcileAfterConfirmedEdit(.init(
            title: "Private now",
            annotation: "Description",
            isPublic: false,
            collaborators: []
        ))

        let publicProvider = MediaDetailFixtureProvider(error: MediaDetailFixtureError.failed)
        let publicModel = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            account: publicAccount,
            provider: publicProvider,
            cache: cache
        )
        await publicModel.load()

        XCTAssertNil(publicModel.detail)
        guard case .failed = publicModel.phase else {
            return XCTFail("Expected tokenless lookup to reauthorize with the server")
        }
        let publicCalls = await publicProvider.playlistCalls
        XCTAssertEqual(publicCalls, [mbid])
        let publicCached = await cache.value(for: .init(
            mbid: mbid,
            accessScope: .publicOnly
        ))
        XCTAssertNil(publicCached)
    }

    func testConfirmedPlaylistEditReconcilesWithServerDetail() async {
        let mbid = UUID()
        let account = Account(username: "listener", token: "token")
        let cache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let provider = SequencedPlaylistProvider(
            initial: playlistDetail(mbid: mbid, title: "Before"),
            refreshed: playlistDetail(mbid: mbid, title: "Canonical server title")
        )
        let model = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            account: account,
            provider: provider,
            cache: cache
        )
        await model.load()

        await model.reconcileAfterConfirmedEdit(.init(
            title: "Locally confirmed title",
            annotation: "Updated note",
            isPublic: false,
            collaborators: ["friend"]
        ))

        XCTAssertEqual(model.detail?.title, "Canonical server title")
        XCTAssertNil(model.refreshMessage)
        let calls = await provider.playlistCalls
        XCTAssertEqual(calls, [mbid, mbid])
        let cached = await cache.value(for: .init(mbid: mbid, accessScope: .init(account: account)))
        XCTAssertEqual(cached?.value.title, "Canonical server title")
    }

    func testConfirmedPlaylistEditSurvivesFailedReconciliation() async {
        let mbid = UUID()
        let account = Account(username: "listener", token: "token")
        let cache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let provider = SequencedPlaylistProvider(
            initial: playlistDetail(mbid: mbid, title: "Before"),
            refreshError: MediaDetailFixtureError.failed
        )
        let model = PlaylistDetailModel(
            seed: playlistSeed(mbid: mbid),
            account: account,
            provider: provider,
            cache: cache
        )
        await model.load()

        await model.reconcileAfterConfirmedEdit(.init(
            title: "Confirmed locally",
            annotation: "",
            isPublic: false,
            collaborators: ["friend"]
        ))

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.detail?.title, "Confirmed locally")
        XCTAssertNil(model.detail?.annotation)
        XCTAssertFalse(model.detail?.isPublic ?? true)
        XCTAssertEqual(model.detail?.collaborators, ["friend"])
        XCTAssertEqual(model.refreshMessage, MediaDetailFixtureError.failed.localizedDescription)
        let cached = await cache.value(for: .init(mbid: mbid, accessScope: .init(account: account)))
        XCTAssertEqual(cached?.value.title, "Confirmed locally")
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

    private func concreteReleaseSeed(mbid: UUID) -> ReleaseSeed {
        ReleaseSeed(
            mbid: mbid,
            title: "Fixture edition",
            artistName: "Fixture artist",
            artistMBIDs: [],
            releaseGroupMBID: UUID(),
            releaseDate: "2024-01-01",
            primaryType: "Album",
            artworkReleaseMBID: mbid
        )
    }

    private func concreteReleaseDetail(mbid: UUID, trackTitles: [String]) -> ReleaseDetail {
        ReleaseDetail(
            mbid: mbid,
            title: "Fixture edition",
            artistCreditName: "Fixture artist",
            releaseDate: "2024-01-01",
            country: "CA",
            status: "Official",
            barcode: nil,
            packaging: nil,
            labels: [],
            releaseGroupMBID: UUID(),
            releaseGroupPrimaryType: "Album",
            media: [ReleaseMedium(
                position: 1,
                format: "Digital Media",
                title: nil,
                tracks: trackTitles.enumerated().map { index, title in
                    ReleaseTrack(
                        position: index + 1,
                        number: String(index + 1),
                        recording: Recording(
                            identity: .init(mbid: UUID(), msid: nil),
                            title: title,
                            artistName: "Fixture artist",
                            artistMBIDs: [],
                            releaseTitle: "Fixture edition",
                            releaseMBID: mbid,
                            releaseGroupMBID: nil,
                            artworkReleaseMBID: mbid,
                            durationMilliseconds: 180_000,
                            source: nil
                        )
                    )
                }
            )]
        )
    }

    private func playlistDetail(
        mbid: UUID,
        title: String = "Fixture playlist",
        isPublic: Bool = true,
        collaborators: [String] = [],
        tracks: [PlaylistTrack] = []
    ) -> PlaylistDetail {
        PlaylistDetail(
            mbid: mbid,
            title: title,
            creator: "listener",
            annotation: "Description",
            createdAt: nil,
            lastModifiedAt: nil,
            isPublic: isPublic,
            createdFor: nil,
            collaborators: collaborators,
            copiedFrom: nil,
            tracks: tracks
        )
    }
}

private actor MediaDetailFixtureProvider: ReleaseDetailProviding, ConcreteReleaseDetailProviding, PlaylistDetailProviding {
    private(set) var releaseCalls: [UUID] = []
    private(set) var concreteReleaseCalls: [UUID] = []
    private(set) var playlistCalls: [UUID] = []
    private(set) var playlistInspectionCalls: [UUID] = []
    private let releaseValue: ReleaseGroupDetail?
    private let concreteReleaseValue: ReleaseDetail?
    private let playlistValue: PlaylistDetail?
    private let error: (any Error & Sendable)?

    init(
        release: ReleaseGroupDetail? = nil,
        concreteRelease: ReleaseDetail? = nil,
        playlist: PlaylistDetail? = nil,
        error: (any Error & Sendable)? = nil
    ) {
        self.releaseValue = release
        self.concreteReleaseValue = concreteRelease
        self.playlistValue = playlist
        self.error = error
    }

    func releaseGroup(mbid: UUID) async throws -> ReleaseGroupDetail? {
        releaseCalls.append(mbid)
        if let error { throw error }
        return releaseValue
    }

    func release(seed: ReleaseSeed) async throws -> ReleaseDetail {
        concreteReleaseCalls.append(seed.mbid)
        if let error { throw error }
        guard let concreteReleaseValue else { throw MediaDetailFixtureError.missingFixture }
        return concreteReleaseValue
    }

    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        playlistCalls.append(mbid)
        if let error { throw error }
        guard let playlistValue else { throw MediaDetailFixtureError.missingFixture }
        return playlistValue
    }

    func playlistForMutationInspection(mbid: UUID) async throws -> PlaylistDetail {
        playlistInspectionCalls.append(mbid)
        if let error { throw error }
        guard let playlistValue else { throw MediaDetailFixtureError.missingFixture }
        return playlistValue
    }
}

private actor SequencedPlaylistProvider: PlaylistDetailProviding {
    private(set) var playlistCalls: [UUID] = []
    private let initial: PlaylistDetail
    private let refreshed: PlaylistDetail?
    private let refreshError: (any Error & Sendable)?

    init(
        initial: PlaylistDetail,
        refreshed: PlaylistDetail? = nil,
        refreshError: (any Error & Sendable)? = nil
    ) {
        self.initial = initial
        self.refreshed = refreshed
        self.refreshError = refreshError
    }

    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        playlistCalls.append(mbid)
        if playlistCalls.count == 1 { return initial }
        if let refreshError { throw refreshError }
        return refreshed ?? initial
    }
}

private enum MediaDetailFixtureError: LocalizedError, Sendable {
    case failed
    case missingFixture

    var errorDescription: String? { "Fixture request failed." }
}
