import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class ProfilePlaylistsModelTests: XCTestCase {
    func testOwnerControlsRequireAuthenticatedMatchingViewer() {
        XCTAssertTrue(
            ProfilePlaylistAudience.hasOwnerAccess(
                profileUsername: " Listener ",
                viewer: .init(username: "listener", token: "token")
            )
        )
        XCTAssertFalse(
            ProfilePlaylistAudience.hasOwnerAccess(
                profileUsername: "music-friend",
                viewer: .init(username: "listener", token: "token")
            ),
            "A signed-in visitor must not receive playlist-owner controls or copy."
        )
        XCTAssertFalse(
            ProfilePlaylistAudience.hasOwnerAccess(
                profileUsername: "listener",
                viewer: .init(username: "listener", token: "")
            ),
            "A matching public profile without credentials has no owner access."
        )
    }

    func testPlaylistAccessScopesSeparatePublicAndCredentialBoundPages() {
        let publicKey = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .publicOnly,
            category: .owned,
            offset: 0,
            count: 20
        )
        let authenticated = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "token")),
            category: .owned,
            offset: 0,
            count: 20
        )

        XCTAssertNotEqual(publicKey, authenticated)
    }

    func testCategoriesLoadLazilyAndIndependently() async {
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned, offset: 0, total: 1, rows: [playlist("owned")]),
            .init(category: .collaborating, offset: 0): makePage(
                category: .collaborating, offset: 0, total: 1, rows: [playlist("shared")]),
        ])
        let model = makeModel(provider: provider)

        await model.load(category: .owned)

        XCTAssertEqual(model.state(for: .owned).playlists.map(\.title), ["owned"])
        XCTAssertEqual(model.state(for: .collaborating).phase, .idle)
        let ownedCalls = await provider.calls
        XCTAssertEqual(ownedCalls, [.init(category: .owned, offset: 0)])

        await model.load(category: .collaborating)
        let allCalls = await provider.calls
        XCTAssertEqual(
            allCalls,
            [
                .init(category: .owned, offset: 0),
                .init(category: .collaborating, offset: 0),
            ])
    }

    func testPaginationUsesServerOffsetDeduplicatesAndTerminatesAtTotal() async {
        let duplicate = playlist("a")
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned, offset: 0, total: 3, rows: [duplicate, playlist("b")]),
            .init(category: .owned, offset: 2): makePage(
                category: .owned, offset: 2, total: 3, rows: [duplicate, playlist("c")]),
        ])
        let model = makeModel(provider: provider, pageSize: 2)

        await model.load(category: .owned)
        XCTAssertEqual(model.state(for: .owned).nextOffset, 2)
        XCTAssertTrue(model.state(for: .owned).hasMore)

        await model.loadMore(category: .owned)
        let state = model.state(for: .owned)
        XCTAssertEqual(state.playlists.map(\.title), ["a", "b", "c"])
        XCTAssertEqual(state.nextOffset, 4)
        XCTAssertFalse(state.hasMore)

        await model.loadMore(category: .owned)
        let calls = await provider.calls
        XCTAssertEqual(
            calls,
            [
                .init(category: .owned, offset: 0),
                .init(category: .owned, offset: 2),
            ])
    }

    func testMalformedPageCannotCauseOffsetRepeatLoop() async {
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned, offset: 0, total: 20, rows: [playlist("one")]),
            // The second response incorrectly claims it starts at zero again.
            .init(category: .owned, offset: 1): makePage(
                category: .owned, offset: 0, total: 20, rows: [playlist("two")]),
        ])
        let model = makeModel(provider: provider)

        await model.load(category: .owned)

        await model.loadMore(category: .owned)
        XCTAssertFalse(model.state(for: .owned).hasMore)
        await model.loadMore(category: .owned)
        let calls = await provider.calls
        XCTAssertEqual(
            calls,
            [
                .init(category: .owned, offset: 0),
                .init(category: .owned, offset: 1),
            ])
    }

    func testEmptyPageTerminatesEvenWhenServerReportsMoreRows() async {
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(category: .owned, offset: 0, total: 99, rows: [])
        ])
        let model = makeModel(provider: provider)

        await model.load(category: .owned)

        XCTAssertTrue(model.state(for: .owned).playlists.isEmpty)
        XCTAssertFalse(model.state(for: .owned).hasMore)
    }

    func testFreshCacheAvoidsProviderAndStaleCacheIsRetainedOnRefreshFailure() async {
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let account = Account(username: "Listener", token: "token")
        let firstProvider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned, offset: 0, total: 1, rows: [playlist("cached")])
        ])
        let first = ProfilePlaylistsModel(account: account, provider: firstProvider, cache: cache)
        await first.load(category: .owned)

        let freshProvider = PlaylistFixtureProvider(pages: [:])
        let fresh = ProfilePlaylistsModel(account: account, provider: freshProvider, cache: cache)
        await fresh.load(category: .owned)
        XCTAssertEqual(fresh.state(for: .owned).playlists.map(\.title), ["cached"])
        let freshCalls = await freshProvider.calls
        XCTAssertTrue(freshCalls.isEmpty)

        let staleCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>(timeToLive: -1)
        await staleCache.save(
            makePage(category: .owned, offset: 0, total: 1, rows: [playlist("stale")]),
            for: .init(
                username: "listener",
                accessScope: .authenticatedViewer(.authenticated(token: "token")),
                category: .owned,
                offset: 0,
                count: 20
            )
        )
        let failing = PlaylistFixtureProvider(pages: [:], shouldFail: true)
        let stale = ProfilePlaylistsModel(account: account, provider: failing, cache: staleCache)
        await stale.load(category: .owned)
        XCTAssertEqual(stale.state(for: .owned).playlists.map(\.title), ["stale"])
        XCTAssertEqual(stale.state(for: .owned).phase, .ready)
        XCTAssertEqual(stale.state(for: .owned).refreshMessage, FixtureError.offline.localizedDescription)
    }

    func testRevokedAuthenticationPurgesExpiredPrivatePlaylistPages() async {
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>(timeToLive: -1)
        let key = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "listener")),
            category: .owned,
            offset: 0,
            count: 20
        )
        await cache.save(
            makePage(category: .owned, offset: 0, total: 1, rows: [playlist("private")]),
            for: key
        )
        let model = ProfilePlaylistsModel(
            account: .init(username: "listener", token: "revoked-token"),
            provider: AccessDeniedProfilePlaylistsProvider(),
            cache: cache
        )

        await model.load(category: .owned)

        XCTAssertTrue(model.state(for: .owned).playlists.isEmpty)
        guard case .failed = model.state(for: .owned).phase else {
            return XCTFail("Expected revoked authentication to clear stale destinations")
        }
        let cached = await cache.value(for: key)
        XCTAssertNil(cached)
    }

    func testFailedLoadMoreCanBeRetriedAtTheSameOffset() async {
        let provider = RetryingPlaylistProvider()
        let model = makeModel(provider: provider, pageSize: 2)

        await model.load(category: .owned)
        await model.loadMore(category: .owned)
        XCTAssertEqual(model.state(for: .owned).loadMoreError, FixtureError.offline.localizedDescription)

        await model.loadMore(category: .owned)
        XCTAssertEqual(model.state(for: .owned).playlists.map(\.title), ["a", "b", "c"])
        let offsets = await provider.offsets
        XCTAssertEqual(offsets, [0, 2, 2])
    }

    func testStaleAppendedPageDoesNotAdvancePastFailedRevalidation() async {
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>(timeToLive: -1)
        await cache.save(
            makePage(category: .owned, offset: 2, total: 3, rows: [playlist("stale-c")], requestedCount: 2),
            for: .init(
                username: "listener",
                accessScope: .authenticatedViewer(.authenticated(token: "listener")),
                category: .owned,
                offset: 2,
                count: 2
            )
        )
        let provider = RetryingPlaylistProvider()
        let model = ProfilePlaylistsModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: cache,
            pageSize: 2
        )

        await model.load(category: .owned)
        await model.loadMore(category: .owned)
        XCTAssertEqual(model.state(for: .owned).playlists.map(\.title), ["a", "b"])
        XCTAssertEqual(model.state(for: .owned).nextOffset, 2)
        XCTAssertEqual(model.state(for: .owned).loadMoreRetryOffset, 2)

        await model.loadMore(category: .owned)
        XCTAssertEqual(model.state(for: .owned).playlists.map(\.title), ["a", "b", "c"])
        XCTAssertNil(model.state(for: .owned).loadMoreRetryOffset)
        let offsets = await provider.offsets
        XCTAssertEqual(offsets, [0, 2, 2])
    }

    func testConcurrentInitialLoadsCoalesce() async {
        let provider = BlockingPlaylistProvider()
        let model = makeModel(provider: provider)

        let first = Task { await model.load(category: .owned) }
        await provider.waitForRequest()
        let second = Task { await model.load(category: .owned) }
        await Task.yield()
        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 1)
        await provider.release()
        await first.value
        await second.value
    }

    func testCancelledLoadRestartsWhenCategoryIsImmediatelyReselected() async {
        let provider = CancellationRetryPlaylistProvider()
        let model = makeModel(provider: provider)

        let first = Task { await model.load(category: .owned) }
        await provider.waitForFirstRequest()
        first.cancel()
        let reselected = Task { await model.load(category: .owned) }
        await Task.yield()
        await provider.releaseFirstRequest()
        await first.value
        await reselected.value

        XCTAssertEqual(model.state(for: .owned).phase, .ready)
        XCTAssertEqual(model.state(for: .owned).playlists.map(\.title), ["reselected"])
        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    func testCancelledReselectionStopsWaitingBeforeOriginalLoadSettles() async {
        let provider = BlockingPlaylistProvider()
        let model = makeModel(provider: provider)
        let waiterFinished = expectation(description: "cancelled waiter finishes")

        let first = Task { await model.load(category: .owned) }
        await provider.waitForRequest()
        let waiting = Task {
            await model.load(category: .owned)
            waiterFinished.fulfill()
        }
        await Task.yield()
        waiting.cancel()

        await fulfillment(of: [waiterFinished], timeout: 0.5)
        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 1)

        await provider.release()
        await first.value
        await waiting.value
        XCTAssertEqual(model.state(for: .owned).phase, .ready)
    }

    func testConcurrentRefreshesCoalesce() async {
        let provider = RefreshBlockingPlaylistProvider()
        let model = makeModel(provider: provider)

        await model.load(category: .owned)
        let firstRefresh = Task { await model.refresh(category: .owned) }
        await provider.waitForRefreshRequest()
        await model.refresh(category: .owned)
        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 2)
        await provider.releaseRefresh()
        await firstRefresh.value

        XCTAssertEqual(model.state(for: .owned).playlists.map(\.title), ["fresh"])
    }

    func testConfirmedMutationInvalidatesCacheAndRefreshesOwnedPlaylists() async {
        let provider = SequencedProfilePlaylistProvider()
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let model = ProfilePlaylistsModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: cache
        )

        await model.load(category: .owned)
        XCTAssertEqual(model.state(for: .owned).playlists.map(\.title), ["before"])

        await model.refreshAfterMutation()

        XCTAssertEqual(model.state(for: .owned).playlists.map(\.title), ["after"])
        let requests = await provider.requests
        XCTAssertEqual(
            requests,
            [
                .init(category: .owned, offset: 0),
                .init(category: .owned, offset: 0),
            ])
    }

    func testConfirmedEditUpdatesLoadedRowAndInvalidatesPageWithoutRefetching() async {
        let mbid = UUID()
        let source = SearchPlaylist(
            title: "Before",
            creator: "listener",
            annotation: "Old note",
            identifier: "https://listenbrainz.org/playlist/\(mbid.uuidString)",
            isPublic: true,
            lastModifiedAt: .distantPast,
            collaborators: ["Alice"]
        )
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned,
                offset: 0,
                total: 1,
                rows: [source]
            )
        ])
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let model = ProfilePlaylistsModel(
            account: .init(username: "Listener", token: "token"),
            provider: provider,
            cache: cache
        )
        await model.load(category: .owned)

        await model.reconcileAfterConfirmedEdit(
            .init(
                mbid: mbid,
                ownerUsername: "listener",
                draft: .init(
                    title: "After",
                    annotation: "New note",
                    isPublic: false,
                    collaborators: ["Alice", "Bob"]
                )
            ))

        let row = model.state(for: .owned).playlists.first
        XCTAssertEqual(row?.title, "After")
        XCTAssertEqual(row?.annotation, "New note")
        XCTAssertEqual(row?.isPublic, false)
        XCTAssertEqual(row?.collaborators, ["Alice", "Bob"])
        let calls = await provider.calls
        XCTAssertEqual(calls, [.init(category: .owned, offset: 0)])
        let cached = await cache.value(
            for: .init(
                username: "listener",
                accessScope: .authenticatedViewer(.authenticated(token: "listener")),
                category: .owned,
                offset: 0,
                count: 20
            ))
        XCTAssertNil(cached)
    }

    func testConfirmedCopyPrependsLoadedOwnedRowAndInvalidatesPageWithoutRefetching() async {
        let originalMBID = UUID()
        let copiedMBID = UUID()
        let original = SearchPlaylist(
            title: "Original",
            creator: "listener",
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(originalMBID.uuidString)",
            isPublic: true,
            lastModifiedAt: nil
        )
        let copy = SearchPlaylist(
            title: "Copy of Original",
            creator: "listener",
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(copiedMBID.uuidString)",
            isPublic: true,
            lastModifiedAt: nil
        )
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned,
                offset: 0,
                total: 1,
                rows: [original]
            )
        ])
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let model = ProfilePlaylistsModel(
            account: .init(username: "Listener", token: "token"),
            provider: provider,
            cache: cache
        )
        await model.load(category: .owned)

        await model.reconcileAfterConfirmedCopy(
            .init(
                ownerUsername: "listener",
                playlist: copy
            ))

        let state = model.state(for: .owned)
        XCTAssertEqual(state.playlists.map(\.playlistMBID), [copiedMBID, originalMBID])
        XCTAssertEqual(state.totalCount, 2)
        let calls = await provider.calls
        XCTAssertEqual(calls, [.init(category: .owned, offset: 0)])
        let cached = await cache.value(
            for: .init(
                username: "listener",
                accessScope: .authenticatedViewer(.authenticated(token: "listener")),
                category: .owned,
                offset: 0,
                count: 20
            ))
        XCTAssertNil(cached)
    }

    func testSourceVisibilityLossRemovesOnlyMatchingRenderedRowsAndClearsPages() async {
        let sourceMBID = UUID()
        let otherMBID = UUID()
        let source = playlist(mbid: sourceMBID, title: "Private source")
        let other = playlist(mbid: otherMBID, title: "Keep me")
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned,
                offset: 0,
                total: 2,
                rows: [source, other]
            ),
            .init(category: .collaborating, offset: 0): makePage(
                category: .collaborating,
                offset: 0,
                total: 2,
                rows: [source, other]
            ),
        ])
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let model = ProfilePlaylistsModel(
            account: .init(username: "Listener", token: "token"),
            provider: provider,
            cache: cache
        )
        await model.load(category: .owned)
        await model.load(category: .collaborating)

        await model.reconcileAfterAccessLoss(
            .init(
                viewerUsername: "listener",
                sourceMBID: sourceMBID,
                reason: .sourceVisibility,
                message: "No longer visible"
            ))

        for category in ProfilePlaylistCategory.allCases {
            let state = model.state(for: category)
            XCTAssertEqual(state.playlists.map(\.playlistMBID), [otherMBID])
            XCTAssertEqual(state.totalCount, 1)
            XCTAssertEqual(state.nextOffset, 0)
            XCTAssertFalse(state.hasMore)
            XCTAssertFalse(state.isLoadingMore)
            XCTAssertNotNil(state.refreshMessage)
            let cached = await cache.value(
                for: .init(
                    username: "listener",
                    accessScope: .authenticatedViewer(.authenticated(token: "listener")),
                    category: category,
                    offset: 0,
                    count: 20
                ))
            XCTAssertNil(cached)
        }

        await model.loadMore(category: .owned)
        var calls = await provider.calls
        XCTAssertEqual(
            calls,
            [
                .init(category: .owned, offset: 0),
                .init(category: .collaborating, offset: 0),
            ])

        await model.refresh(category: .owned)
        calls = await provider.calls
        XCTAssertEqual(calls.last, .init(category: .owned, offset: 0))
    }

    func testSourceVisibilityLossInvalidatesAnOlderInFlightProfileRequest() async {
        let sourceMBID = UUID()
        let provider = AccessLossBlockingPlaylistProvider(sourceMBID: sourceMBID)
        let model = makeModel(provider: provider)
        let load = Task { await model.load(category: .owned) }
        await provider.waitForRequest()

        await model.reconcileAfterAccessLoss(
            .init(
                viewerUsername: "listener",
                sourceMBID: sourceMBID,
                reason: .sourceVisibility,
                message: "No longer visible"
            ))
        await provider.release()
        await load.value

        let state = model.state(for: .owned)
        XCTAssertTrue(state.playlists.isEmpty)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertNotNil(state.refreshMessage)
    }

    func testConfirmedDeletionRemovesOwnedRowAndKeepsPaginationAligned() async {
        let deletedMBID = UUID()
        let keptMBID = UUID()
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned,
                offset: 0,
                total: 3,
                rows: [
                    playlist(mbid: deletedMBID, title: "Delete me"),
                    playlist(mbid: keptMBID, title: "Keep me"),
                ]
            )
        ])
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let model = ProfilePlaylistsModel(
            account: .init(username: "Listener", token: "token"),
            provider: provider,
            cache: cache
        )
        await model.load(category: .owned)

        await model.reconcileAfterConfirmedDeletion(
            .init(ownerUsername: "listener", playlistMBID: deletedMBID)
        )

        let state = model.state(for: .owned)
        XCTAssertEqual(state.playlists.map(\.playlistMBID), [keptMBID])
        XCTAssertEqual(state.totalCount, 2)
        XCTAssertEqual(state.nextOffset, 1)
        XCTAssertTrue(state.hasMore)
        XCTAssertEqual(state.phase, .ready)
        let cached = await cache.value(
            for: .init(
                username: "listener",
                accessScope: .authenticatedViewer(
                    .authenticated(token: "token")
                ),
                category: .owned,
                offset: 0,
                count: 20
            )
        )
        XCTAssertNil(cached)
    }

    func testConfirmedDeletionInvalidatesOlderInFlightProfileResponse() async {
        let deletedMBID = UUID()
        let provider = AccessLossBlockingPlaylistProvider(
            sourceMBID: deletedMBID
        )
        let model = makeModel(provider: provider)
        let load = Task { await model.load(category: .owned) }
        await provider.waitForRequest()

        await model.reconcileAfterConfirmedDeletion(
            .init(ownerUsername: "listener", playlistMBID: deletedMBID)
        )
        await provider.release()
        await load.value

        let state = model.state(for: .owned)
        XCTAssertTrue(state.playlists.isEmpty)
        XCTAssertEqual(state.phase, .ready)
    }

    func testConfirmedDeletionDoesNotCrossAccountBoundary() async {
        let playlistMBID = UUID()
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned,
                offset: 0,
                total: 1,
                rows: [playlist(mbid: playlistMBID, title: "Keep me")]
            )
        ])
        let model = makeModel(provider: provider)
        await model.load(category: .owned)

        await model.reconcileAfterConfirmedDeletion(
            .init(ownerUsername: "another-user", playlistMBID: playlistMBID)
        )

        XCTAssertEqual(
            model.state(for: .owned).playlists.map(\.playlistMBID),
            [playlistMBID]
        )
    }

    func testAccessLossCannotBeOverwrittenByLaterCopyOrEditEvents() async {
        let sourceMBID = UUID()
        let destinationMBID = UUID()
        let source = playlist(mbid: sourceMBID, title: "Private source")
        let journal = PlaylistMutationJournal()
        let journalCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned,
                offset: 0,
                total: 1,
                rows: [source]
            )
        ])
        let model = makeModel(provider: provider, mutationJournal: journal)
        await model.load(category: .owned)
        await journal.recordAccessLoss(
            sourceMBID: sourceMBID,
            viewerUsername: "listener",
            reason: .sourceVisibility,
            message: "No longer visible",
            profilePageCache: journalCache
        )
        journal.recordConfirmedCopy(
            playlist(mbid: destinationMBID, title: "Safe copy"),
            ownerUsername: "listener"
        )
        journal.recordConfirmedEdit(
            mbid: sourceMBID,
            ownerUsername: "listener",
            draft: .init(title: "Stale edit", isPublic: false)
        )

        await model.reconcileJournal()

        let state = model.state(for: .owned)
        XCTAssertEqual(state.playlists.map(\.playlistMBID), [destinationMBID])
        XCTAssertNotNil(state.refreshMessage)
    }

    func testNewProfileModelDoesNotReplayHistoricAccessLossFromTheJournal() async {
        let staleMBID = UUID()
        let restoredMBID = UUID()
        let journal = PlaylistMutationJournal()
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let key = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "listener")),
            category: .owned,
            offset: 0,
            count: 20
        )
        await cache.save(
            makePage(
                category: .owned,
                offset: 0,
                total: 1,
                rows: [playlist(mbid: staleMBID, title: "Stale private row")]
            ),
            for: key
        )
        await journal.recordAccessLoss(
            sourceMBID: staleMBID,
            viewerUsername: "listener",
            reason: .authentication,
            message: "Old revoked session",
            profilePageCache: cache
        )
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned,
                offset: 0,
                total: 1,
                rows: [playlist(mbid: restoredMBID, title: "Current server row")]
            )
        ])
        let model = ProfilePlaylistsModel(
            account: .init(username: "listener", token: "new-token"),
            provider: provider,
            cache: cache,
            mutationJournal: journal
        )

        await model.load(category: .owned)
        await model.reconcileJournal()

        let state = model.state(for: .owned)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.playlists.map(\.playlistMBID), [restoredMBID])
        XCTAssertNil(state.refreshMessage)
        let calls = await provider.calls
        XCTAssertEqual(calls, [.init(category: .owned, offset: 0)])
    }

    func testAuthenticationLossClearsEveryRenderedPlaylistCategory() async {
        let provider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned,
                offset: 0,
                total: 1,
                rows: [playlist(mbid: UUID(), title: "Private")]
            ),
            .init(category: .collaborating, offset: 0): makePage(
                category: .collaborating,
                offset: 0,
                total: 1,
                rows: [playlist(mbid: UUID(), title: "Shared")]
            ),
        ])
        let model = makeModel(provider: provider)
        await model.load(category: .owned)
        await model.load(category: .collaborating)

        await model.reconcileAfterAccessLoss(
            .init(
                viewerUsername: "LISTENER",
                sourceMBID: UUID(),
                reason: .authentication,
                message: "Reconnect your token"
            ))

        for category in ProfilePlaylistCategory.allCases {
            let state = model.state(for: category)
            XCTAssertTrue(state.playlists.isEmpty)
            guard case .failed(let message) = state.phase else {
                return XCTFail("Expected \(category) to discard access-sensitive state")
            }
            XCTAssertEqual(message, "Reconnect your token")
        }
    }

    func testCancellationReturnsToIdle() async {
        let blocking = BlockingPlaylistProvider()
        let model = makeModel(provider: blocking)
        let task = Task { await model.load(category: .owned) }
        await blocking.waitForRequest()
        task.cancel()
        await blocking.release()
        await task.value
        XCTAssertEqual(model.state(for: .owned).phase, .idle)
    }

    func testPublicPlaylistsLoadWithoutAuthenticationAndCacheIsVisibilityScoped() async {
        let cache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let authenticatedProvider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned, offset: 0, total: 1, rows: [playlist("private")])
        ])
        let authenticated = ProfilePlaylistsModel(
            account: .init(username: "listener", token: "token"),
            provider: authenticatedProvider,
            cache: cache
        )
        await authenticated.load(category: .owned)

        let publicProvider = PlaylistFixtureProvider(pages: [
            .init(category: .owned, offset: 0): makePage(
                category: .owned, offset: 0, total: 1, rows: [playlist("public")])
        ])
        let unauthenticated = ProfilePlaylistsModel(
            account: .init(username: "listener", token: ""),
            provider: publicProvider,
            cache: cache
        )
        await unauthenticated.load(category: .owned)
        XCTAssertEqual(unauthenticated.state(for: .owned).phase, .ready)
        XCTAssertEqual(unauthenticated.state(for: .owned).playlists.map(\.title), ["public"])
        let publicCalls = await publicProvider.calls
        XCTAssertEqual(publicCalls, [.init(category: .owned, offset: 0)])
    }

    func testProviderMakesOneMetadataRequestWithoutRowHydration() async throws {
        let transport = PlaylistTransportSpy()
        let provider = ListenBrainzProfilePlaylistsProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let result = try await provider.page(username: "listener", category: .collaborating, offset: 5, count: 2)

        XCTAssertEqual(result.playlists, [])
        let calls = await transport.calls
        XCTAssertEqual(calls, [.init(category: .collaborating, offset: 5)])
    }

    func testFreshProviderReadDoesNotJoinAnOlderEquivalentRead() async throws {
        let transport = BlockingPlaylistTransport()
        let provider = ListenBrainzProfilePlaylistsProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let olderRead = Task {
            try await provider.page(username: "listener", category: .owned, offset: 0, count: 100)
        }
        while await transport.callCount() < 1 { await Task.yield() }

        let recoveryRead = Task {
            try await provider.freshPage(username: "listener", category: .owned, offset: 0, count: 100)
        }
        for _ in 0..<1_000 {
            if await transport.callCount() >= 2 { break }
            await Task.yield()
        }
        let callsBeforeRelease = await transport.callCount()
        await transport.releaseAll()
        _ = try await olderRead.value
        _ = try await recoveryRead.value

        XCTAssertEqual(callsBeforeRelease, 2)
    }

    func testProviderMapsAuthenticationRateLimitAndNotFoundErrors() async {
        for (source, expected) in [
            (LBError.invalidAuth, ProfilePlaylistsProviderError.invalidAuthentication.localizedDescription),
            (LBError.notFound, ProfilePlaylistsProviderError.profileUnavailable.localizedDescription),
            (LBError.rateLimited(resetIn: 7), ProviderError.rateLimited(retryAfterSeconds: 7).localizedDescription),
        ] {
            let provider = ListenBrainzProfilePlaylistsProvider(
                transport: ThrowingPlaylistTransport(error: source),
                gate: RequestGate(minimumInterval: .zero)
            )
            do {
                _ = try await provider.page(username: "listener", category: .owned, offset: 0, count: 20)
                XCTFail("Expected mapped error")
            } catch {
                XCTAssertEqual(error.localizedDescription, expected)
            }
        }
    }

    func testSearchPlaylistPreservesProfileListMetadata() {
        let source = playlist("metadata")
        XCTAssertEqual(source.createdAt, .distantPast)
        XCTAssertEqual(source.durationMilliseconds, 123)
        XCTAssertEqual(source.createdFor, "listener")
        XCTAssertEqual(source.collaborators, ["friend"])
    }

    private func makeModel(
        provider: some ProfilePlaylistsProviding,
        pageSize: Int = 20,
        mutationJournal: PlaylistMutationJournal? = nil
    ) -> ProfilePlaylistsModel {
        .init(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            cache: EntityDetailCache(),
            pageSize: pageSize,
            mutationJournal: mutationJournal
        )
    }
}

private struct PlaylistRequest: Hashable, Sendable {
    let category: ProfilePlaylistCategory
    let offset: Int
}

private actor PlaylistFixtureProvider: ProfilePlaylistsProviding {
    let pages: [PlaylistRequest: ProfilePlaylistPage]
    let shouldFail: Bool
    private(set) var calls: [PlaylistRequest] = []

    init(pages: [PlaylistRequest: ProfilePlaylistPage], shouldFail: Bool = false) {
        self.pages = pages
        self.shouldFail = shouldFail
    }

    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> ProfilePlaylistPage
    {
        calls.append(.init(category: category, offset: offset))
        if shouldFail { throw FixtureError.offline }
        return pages[.init(category: category, offset: offset)]
            ?? ProfilePlaylistPage(
                username: username, category: category, playlists: [], requestedCount: count, offset: offset,
                totalCount: 0)
    }
}

private struct AccessDeniedProfilePlaylistsProvider: ProfilePlaylistsProviding {
    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        throw ProfilePlaylistsProviderError.invalidAuthentication
    }
}

private actor RefreshBlockingPlaylistProvider: ProfilePlaylistsProviding {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> ProfilePlaylistPage
    {
        requestCount += 1
        if requestCount == 1 {
            return makePage(category: category, offset: offset, total: 1, rows: [playlist("old")])
        }
        await withCheckedContinuation { continuation = $0 }
        return makePage(category: category, offset: offset, total: 1, rows: [playlist("fresh")])
    }

    func waitForRefreshRequest() async { while requestCount < 2 { await Task.yield() } }
    func releaseRefresh() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SequencedProfilePlaylistProvider: ProfilePlaylistsProviding {
    private(set) var requests: [PlaylistRequest] = []

    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        requests.append(.init(category: category, offset: offset))
        let title = requests.count == 1 ? "before" : "after"
        return makePage(
            category: category,
            offset: offset,
            total: 1,
            rows: [playlist(title)],
            requestedCount: count
        )
    }
}

private actor BlockingPlaylistProvider: ProfilePlaylistsProviding {
    private var continuation: CheckedContinuation<Void, Never>?
    private var requested = false
    private(set) var requestCount = 0

    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> ProfilePlaylistPage
    {
        requested = true
        requestCount += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
        }
        try Task.checkCancellation()
        return makePage(category: category, offset: offset, total: 0, rows: [])
    }

    func waitForRequest() async { while !requested { await Task.yield() } }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor AccessLossBlockingPlaylistProvider: ProfilePlaylistsProviding {
    let sourceMBID: UUID
    private var continuation: CheckedContinuation<Void, Never>?
    private var requested = false

    init(sourceMBID: UUID) {
        self.sourceMBID = sourceMBID
    }

    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        requested = true
        await withCheckedContinuation { continuation = $0 }
        return makePage(
            category: category,
            offset: offset,
            total: 1,
            rows: [playlist(mbid: sourceMBID, title: "Private source")],
            requestedCount: count
        )
    }

    func waitForRequest() async {
        while !requested { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CancellationRetryPlaylistProvider: ProfilePlaylistsProviding {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> ProfilePlaylistPage
    {
        requestCount += 1
        if requestCount == 1 {
            await withCheckedContinuation { continuation = $0 }
            try Task.checkCancellation()
        }
        return makePage(category: category, offset: offset, total: 1, rows: [playlist("reselected")])
    }

    func waitForFirstRequest() async { while requestCount < 1 { await Task.yield() } }
    func releaseFirstRequest() {
        continuation?.resume()
        continuation = nil
    }
}

private actor RetryingPlaylistProvider: ProfilePlaylistsProviding {
    private(set) var offsets: [Int] = []
    private var shouldFailOffsetTwo = true

    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> ProfilePlaylistPage
    {
        offsets.append(offset)
        switch offset {
        case 0:
            return makePage(category: category, offset: 0, total: 3, rows: [playlist("a"), playlist("b")])
        case 2 where shouldFailOffsetTwo:
            shouldFailOffsetTwo = false
            throw FixtureError.offline
        case 2:
            return makePage(category: category, offset: 2, total: 3, rows: [playlist("c")])
        default:
            return makePage(category: category, offset: offset, total: 3, rows: [])
        }
    }
}

private actor PlaylistTransportSpy: ProfilePlaylistsTransport {
    private(set) var calls: [PlaylistRequest] = []

    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> LBPlaylistPage
    {
        calls.append(.init(category: category, offset: offset))
        return .init(playlists: [], requestedCount: count, offset: offset, playlistCount: 0)
    }
}

private actor BlockingPlaylistTransport: ProfilePlaylistsTransport {
    private var calls = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> LBPlaylistPage
    {
        calls += 1
        await withCheckedContinuation { continuations.append($0) }
        return .init(playlists: [], requestedCount: count, offset: offset, playlistCount: 0)
    }

    func callCount() -> Int { calls }

    func releaseAll() {
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

private struct ThrowingPlaylistTransport: ProfilePlaylistsTransport {
    let error: LBError

    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> LBPlaylistPage
    {
        throw error
    }
}

private enum FixtureError: LocalizedError {
    case offline
    var errorDescription: String? { "Offline" }
}

private func makePage(
    category: ProfilePlaylistCategory,
    offset: Int,
    total: Int?,
    rows: [SearchPlaylist],
    requestedCount: Int? = 20
) -> ProfilePlaylistPage {
    .init(
        username: "listener", category: category, playlists: rows, requestedCount: requestedCount, offset: offset,
        totalCount: total)
}

private func playlist(_ identifier: String) -> SearchPlaylist {
    .init(
        title: identifier,
        creator: "listener",
        annotation: nil,
        identifier: "https://listenbrainz.org/playlist/\(identifier)",
        isPublic: true,
        lastModifiedAt: nil,
        createdAt: .distantPast,
        durationMilliseconds: 123,
        createdFor: "listener",
        collaborators: ["friend"]
    )
}

private func playlist(mbid: UUID, title: String) -> SearchPlaylist {
    .init(
        title: title,
        creator: "listener",
        annotation: nil,
        identifier: "https://listenbrainz.org/playlist/\(mbid.uuidString)",
        isPublic: false,
        lastModifiedAt: nil
    )
}
