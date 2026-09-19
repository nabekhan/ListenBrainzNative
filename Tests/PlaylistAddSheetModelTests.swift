import XCTest
@testable import Brainz

@MainActor
final class PlaylistAddSheetModelTests: XCTestCase {
    private let recordingMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let playlistMBID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let account = Account(username: "listener", token: "token")

    func testDuplicateRequiresExplicitAnotherCopyDecision() async {
        let append = PlaylistAppendSpy()
        let detail = PlaylistAddDetailSpy(values: [
            playlist(recordings: [recordingMBID]),
            playlist(recordings: [recordingMBID]),
            playlist(recordings: [recordingMBID, recordingMBID]),
        ])
        let model = PlaylistAddSheetModel(
            account: account, recordingMBID: recordingMBID,
            playlists: ProfilePlaylistsModel(account: account, provider: EmptyProfilePlaylistsProvider(), cache: EntityDetailCache()),
            detailProvider: detail, appendProvider: append
        )

        await model.select(destination)
        XCTAssertNotNil(model.pendingDuplicate)
        let before = await append.callCount()
        XCTAssertEqual(before, 0)

        await model.appendAnotherCopy()
        let after = await append.callCount()
        XCTAssertEqual(after, 1)
        XCTAssertTrue(model.didComplete)
    }

    func testLostResponseWithIncreasedOccurrenceRemainsIndeterminateWithoutReplay() async {
        let append = PlaylistAppendSpy(error: PlaylistMutationProviderError.indeterminateAppend)
        let detail = PlaylistAddDetailSpy(values: [playlist(recordings: []), playlist(recordings: [recordingMBID])])
        let model = PlaylistAddSheetModel(
            account: account, recordingMBID: recordingMBID,
            playlists: ProfilePlaylistsModel(account: account, provider: EmptyProfilePlaylistsProvider(), cache: EntityDetailCache()),
            detailProvider: detail, appendProvider: append
        )

        await model.select(destination)
        let calls = await append.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.didBecomeIndeterminate)
        XCTAssertFalse(model.didComplete)
        XCTAssertTrue(model.message?.contains("did not confirm") == true)
    }

    func testPreflightSerializesRapidDestinationTaps() async {
        let append = PlaylistAppendSpy()
        let detail = PlaylistAddDetailSpy(
            values: [playlist(recordings: []), playlist(recordings: [recordingMBID])],
            delay: .milliseconds(50)
        )
        let model = PlaylistAddSheetModel(
            account: account,
            recordingMBID: recordingMBID,
            playlists: ProfilePlaylistsModel(
                account: account,
                provider: EmptyProfilePlaylistsProvider(),
                cache: EntityDetailCache()
            ),
            detailProvider: detail,
            appendProvider: append
        )
        let first = Task { @MainActor in await model.select(destination) }
        while await detail.callCount() == 0 { await Task.yield() }

        await model.select(destination)
        await first.value

        let appendCalls = await append.callCount()
        let detailCalls = await detail.callCount()
        XCTAssertEqual(appendCalls, 1)
        XCTAssertEqual(detailCalls, 2)
        XCTAssertTrue(model.didComplete)
    }

    func testLoadRequestsOwnedAndCollaboratingDestinations() async {
        let provider = ProfilePlaylistCategorySpy()
        let model = PlaylistAddSheetModel(
            account: account,
            recordingMBID: recordingMBID,
            playlists: ProfilePlaylistsModel(
                account: account,
                provider: provider,
                cache: EntityDetailCache()
            ),
            detailProvider: PlaylistAddDetailSpy(values: [playlist(recordings: [])]),
            appendProvider: PlaylistAppendSpy()
        )

        await model.load()

        let categories = await provider.recordedCategories()
        XCTAssertEqual(Set(categories), Set(ProfilePlaylistCategory.allCases))
    }

    func testEligibilityRequiresAuthenticationAndCanonicalRecording() {
        XCTAssertTrue(PlaylistAddSheetModel.canPresent(
            account: account,
            recordingMBID: recordingMBID
        ))
        XCTAssertFalse(PlaylistAddSheetModel.canPresent(
            account: Account(username: "listener", token: ""),
            recordingMBID: recordingMBID
        ))
        XCTAssertFalse(PlaylistAddSheetModel.canPresent(
            account: account,
            recordingMBID: nil
        ))
    }

    func testPreflightAccessLossPurgesCachedAndVisiblePrivateDestinations() async {
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let playlistModel = ProfilePlaylistsModel(
            account: account,
            provider: SingleProfilePlaylistProvider(playlist: destination),
            cache: pageCache
        )
        let detailKey = PlaylistDetailCacheKey(
            mbid: playlistMBID,
            accessScope: .authenticatedViewer(.authenticated(token: "listener"))
        )
        await detailCache.save(playlist(recordings: [recordingMBID]), for: detailKey)
        let model = PlaylistAddSheetModel(
            account: account,
            recordingMBID: recordingMBID,
            playlists: playlistModel,
            detailProvider: PlaylistAddDetailSpy(
                values: [],
                error: MediaDetailError.playlistUnavailable
            ),
            appendProvider: PlaylistAppendSpy(),
            detailCache: detailCache
        )
        await model.load()
        XCTAssertEqual(playlistModel.state(for: .owned).playlists.count, 1)

        await model.select(destination)

        XCTAssertTrue(playlistModel.state(for: .owned).playlists.isEmpty)
        XCTAssertTrue(playlistModel.state(for: .collaborating).playlists.isEmpty)
        let cachedDetail = await detailCache.value(for: detailKey)
        XCTAssertNil(cachedDetail)
    }

    func testReconciliationAccessLossAlsoPurgesCachedAndVisiblePrivateDestinations() async {
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let playlistModel = ProfilePlaylistsModel(
            account: account,
            provider: SingleProfilePlaylistProvider(playlist: destination),
            cache: pageCache
        )
        let detailKey = PlaylistDetailCacheKey(
            mbid: playlistMBID,
            accessScope: .authenticatedViewer(.authenticated(token: "listener"))
        )
        await detailCache.save(playlist(recordings: [recordingMBID]), for: detailKey)
        let model = PlaylistAddSheetModel(
            account: account,
            recordingMBID: recordingMBID,
            playlists: playlistModel,
            detailProvider: ReconciliationAccessLossDetailProvider(
                initial: playlist(recordings: [])
            ),
            appendProvider: PlaylistAppendSpy(),
            detailCache: detailCache
        )
        await model.load()

        await model.select(destination)

        XCTAssertTrue(model.didBecomeIndeterminate)
        XCTAssertFalse(model.didComplete)
        XCTAssertTrue(playlistModel.state(for: .owned).playlists.isEmpty)
        let cachedDetail = await detailCache.value(for: detailKey)
        XCTAssertNil(cachedDetail)
    }

    private var destination: SearchPlaylist {
        .init(title: "Mix", creator: "listener", annotation: nil,
              identifier: "https://listenbrainz.org/playlist/\(playlistMBID.uuidString)",
              isPublic: true, lastModifiedAt: nil, createdAt: nil, durationMilliseconds: nil, collaborators: [])
    }

    private func playlist(recordings: [UUID]) -> PlaylistDetail {
        .init(mbid: playlistMBID, title: "Mix", creator: "listener", annotation: nil,
              createdAt: nil, lastModifiedAt: nil, isPublic: true, createdFor: nil,
              collaborators: [], copiedFrom: nil, tracks: recordings.enumerated().map { index, mbid in
                  PlaylistTrack(position: index + 1, recording: Recording(identity: .init(mbid: mbid, msid: nil), title: "Track", artistName: "Artist", artistMBIDs: [], releaseTitle: nil, releaseMBID: nil, releaseGroupMBID: nil, artworkReleaseMBID: nil, durationMilliseconds: nil, source: nil), addedAt: nil, addedBy: nil)
              })
    }
}

private actor PlaylistAppendSpy: PlaylistAppendProviding {
    private(set) var count = 0
    let error: Error?
    init(error: Error? = nil) { self.error = error }
    func append(recordingMBID: UUID, to playlistMBID: UUID) async throws {
        count += 1
        if let error { throw error }
    }
    func callCount() -> Int { count }
}

private actor PlaylistAddDetailSpy: PlaylistDetailProviding {
    private var values: [PlaylistDetail]
    private let delay: Duration
    private let error: (any Error & Sendable)?
    private var calls = 0

    init(
        values: [PlaylistDetail],
        delay: Duration = .zero,
        error: (any Error & Sendable)? = nil
    ) {
        self.values = values
        self.delay = delay
        self.error = error
    }

    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        calls += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        if values.count > 1 { return values.removeFirst() }
        return values[0]
    }

    func callCount() -> Int { calls }
}

private actor ReconciliationAccessLossDetailProvider: PlaylistDetailProviding {
    let initial: PlaylistDetail
    private var calls = 0

    init(initial: PlaylistDetail) {
        self.initial = initial
    }

    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        calls += 1
        if calls == 1 { return initial }
        throw MediaDetailError.playlistUnavailable
    }
}

private struct EmptyProfilePlaylistsProvider: ProfilePlaylistsProviding {
    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws -> ProfilePlaylistPage {
        .init(username: username, category: category, playlists: [], requestedCount: count, offset: offset, totalCount: 0)
    }
}

private struct SingleProfilePlaylistProvider: ProfilePlaylistsProviding {
    let playlist: SearchPlaylist

    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        let rows = category == .owned ? [playlist] : []
        return .init(
            username: username,
            category: category,
            playlists: rows,
            requestedCount: count,
            offset: offset,
            totalCount: rows.count
        )
    }
}

private actor ProfilePlaylistCategorySpy: ProfilePlaylistsProviding {
    private var categories: [ProfilePlaylistCategory] = []

    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        categories.append(category)
        return .init(
            username: username,
            category: category,
            playlists: [],
            requestedCount: count,
            offset: offset,
            totalCount: 0
        )
    }

    func recordedCategories() -> [ProfilePlaylistCategory] { categories }
}
