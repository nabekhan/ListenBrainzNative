import Foundation
import ListenBrainzKit
import XCTest
@testable import Brainz

@MainActor
final class PlaylistCopyTests: XCTestCase {
    func testConfirmedCopyUsesOneCallAndInvalidatesOnlyPlaylistListCache() async throws {
        let sourceMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let copiedMBID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let detailKey = PlaylistDetailCacheKey(
            mbid: sourceMBID,
            accessScope: .authenticatedViewer(.authenticated(token: "listener"))
        )
        let pageKey = profilePageKey()
        await detailCache.save(playlistDetail(mbid: sourceMBID), for: detailKey)
        await pageCache.save(emptyProfilePage(), for: pageKey)
        let transport = PlaylistCopyTransportSpy(copiedMBID: copiedMBID)
        let provider = ListenBrainzPlaylistCopyProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: detailCache,
            profilePageCache: pageCache
        )

        let result = try await provider.copy(mbid: sourceMBID)

        XCTAssertEqual(result, copiedMBID)
        let calls = await transport.recordedMBIDs()
        let cachedDetail = await detailCache.value(for: detailKey)
        let cachedPage = await pageCache.value(for: pageKey)
        XCTAssertEqual(calls, [sourceMBID])
        XCTAssertNotNil(cachedDetail, "Copy does not mutate the source playlist detail")
        XCTAssertNil(cachedPage, "Owned Playlists changed and must be reloaded")
    }

    func testCopyRateLimitIsVisibleAndNeverRetried() async {
        let transport = PlaylistCopyTransportSpy(error: LBError.rateLimited(resetIn: 6))
        let provider = ListenBrainzPlaylistCopyProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        do {
            _ = try await provider.copy(mbid: UUID())
            XCTFail("Expected rate limiting")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 6)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await transport.recordedMBIDs()
        XCTAssertEqual(calls.count, 1)
    }

    func testCopyDefiniteRejectionDoesNotBecomeIndeterminate() async {
        for sourceError in [LBError.badRequest, LBError.invalidJSON, LBError.invalidParam] {
            let transport = PlaylistCopyTransportSpy(error: sourceError)
            let provider = ListenBrainzPlaylistCopyProvider(
                transport: transport,
                gate: RequestGate(minimumInterval: .zero)
            )

            do {
                _ = try await provider.copy(mbid: UUID())
                XCTFail("Expected a definite rejection")
            } catch let error as PlaylistMutationProviderError {
                guard case .copyRejected = error else {
                    return XCTFail("Expected copy rejection, got \(error)")
                }
                XCTAssertFalse(error.isIndeterminate)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            let calls = await transport.recordedMBIDs()
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testCopyAccessFailuresPurgePrivateDetailAndPlaylistListCaches() async {
        for sourceError in [LBError.invalidAuth, LBError.forbidden, LBError.notFound] {
            let sourceMBID = UUID()
            let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
            let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
            let detailKey = PlaylistDetailCacheKey(
                mbid: sourceMBID,
                accessScope: .authenticatedViewer(.authenticated(token: "listener"))
            )
            let pageKey = profilePageKey()
            await detailCache.save(
                playlistDetail(mbid: sourceMBID, isPublic: false),
                for: detailKey
            )
            await pageCache.save(emptyProfilePage(), for: pageKey)
            let provider = ListenBrainzPlaylistCopyProvider(
                transport: PlaylistCopyTransportSpy(error: sourceError),
                gate: RequestGate(minimumInterval: .zero),
                detailCache: detailCache,
                profilePageCache: pageCache
            )

            do {
                _ = try await provider.copy(mbid: sourceMBID)
                XCTFail("Expected access failure")
            } catch let error as PlaylistMutationProviderError {
                if sourceError == .invalidAuth {
                    guard case .invalidAuthentication = error else {
                        return XCTFail("Expected invalid authentication, got \(error)")
                    }
                } else {
                    guard case .playlistUnavailable = error else {
                        return XCTFail("Expected unavailable playlist, got \(error)")
                    }
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            let cachedDetail = await detailCache.value(for: detailKey)
            let cachedPage = await pageCache.value(for: pageKey)
            XCTAssertNil(cachedDetail)
            XCTAssertNil(cachedPage)
        }
    }

    func testLostCopyResponseIsIndeterminateNeverRetriedAndClearsListCache() async {
        let sourceMBID = UUID()
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let pageKey = profilePageKey()
        await pageCache.save(emptyProfilePage(), for: pageKey)
        let transport = PlaylistCopyTransportSpy(error: PlaylistCopyFixtureError.failed)
        let provider = ListenBrainzPlaylistCopyProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: EntityDetailCache(),
            profilePageCache: pageCache
        )

        do {
            _ = try await provider.copy(mbid: sourceMBID)
            XCTFail("Expected an indeterminate copy result")
        } catch let error as PlaylistMutationProviderError {
            guard case .indeterminateCopy = error else {
                return XCTFail("Expected indeterminate copy, got \(error)")
            }
            XCTAssertTrue(error.isIndeterminate)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await transport.recordedMBIDs()
        let cachedPage = await pageCache.value(for: pageKey)
        XCTAssertEqual(calls, [sourceMBID])
        XCTAssertNil(cachedPage)
    }

    func testCancellationAfterCopyTransportStartsIsIndeterminate() async {
        let transport = CancellationCopyTransport()
        let provider = ListenBrainzPlaylistCopyProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: EntityDetailCache(),
            profilePageCache: EntityDetailCache()
        )
        let task = Task { try await provider.copy(mbid: UUID()) }
        while !(await transport.hasStarted) { await Task.yield() }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected an indeterminate cancellation result")
        } catch let error as PlaylistMutationProviderError {
            guard case .indeterminateCopy = error else {
                return XCTFail("Expected indeterminate copy, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 1)
    }

    func testCancellationBeforeCopyTransportAdmissionDoesNotDispatch() async throws {
        let gate = RequestGate(minimumInterval: .seconds(5))
        _ = try await gate.perform { true }
        let transport = CancellationCopyTransport()
        let provider = ListenBrainzPlaylistCopyProvider(
            transport: transport,
            gate: gate,
            detailCache: EntityDetailCache(),
            profilePageCache: EntityDetailCache()
        )
        let task = Task { try await provider.copy(mbid: UUID()) }
        await Task.yield()

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation before transport")
        } catch is CancellationError {
            // No POST was admitted.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let didStart = await transport.hasStarted
        XCTAssertFalse(didStart)
    }

    func testCopyModelSerializesTapsAndUsesCanonicalDestinationInsteadOfSourceSnapshot() async {
        let copiedMBID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
        let provider = PlaylistCopyProviderSpy(copiedMBID: copiedMBID, delay: .milliseconds(60))
        let source = playlistDetail(
            mbid: UUID(),
            title: "Shared mix",
            isPublic: false,
            collaborators: ["friend"],
            tracks: [playlistTrack(durationMilliseconds: 180_000)]
        )
        let canonical = playlistDetail(
            mbid: copiedMBID,
            title: "Canonical server copy",
            creator: "listener",
            annotation: "Changed on ListenBrainz",
            createdAt: Date(timeIntervalSince1970: 2_000),
            isPublic: true,
            collaborators: [],
            copiedFrom: source.mbid.uuidString,
            tracks: [playlistTrack(durationMilliseconds: 240_000)]
        )
        let detailProvider = PlaylistCopyDetailProviderSpy(detail: canonical)
        let model = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: provider,
            detailProvider: detailProvider,
            reconciliationJournal: PlaylistCopyReconciliationJournal()
        )

        async let first: Void = model.copy(source)
        async let second: Void = model.copy(source)
        _ = await (first, second)

        let calls = await provider.recordedMBIDs()
        XCTAssertEqual(calls, [source.mbid])
        guard case let .confirmed(copied)? = model.notice else {
            return XCTFail("Expected a confirmed copy")
        }
        XCTAssertEqual(copied.playlistMBID, copiedMBID)
        XCTAssertEqual(copied.title, "Canonical server copy")
        XCTAssertEqual(copied.creator, "listener")
        XCTAssertTrue(copied.isPublic, "Visibility must come from the copied playlist GET")
        XCTAssertEqual(copied.annotation, "Changed on ListenBrainz")
        XCTAssertEqual(copied.durationMilliseconds, 240_000)
        XCTAssertTrue(copied.collaborators.isEmpty)
        XCTAssertEqual(copied.copiedFromMBID, source.mbid)
        XCTAssertTrue(model.requiresReconciliation, "Confirmation remains durable until acknowledged")
        let detailCalls = await detailProvider.calls
        XCTAssertEqual(detailCalls, [copiedMBID])
        model.acknowledgeConfirmedCopy()
        XCTAssertFalse(model.requiresReconciliation)
    }

    func testCanonicalFetchFailureKeepsKnownDestinationLockedForSafeRetry() async {
        let copiedMBID = UUID()
        let source = playlistDetail(mbid: UUID())
        let journal = PlaylistCopyReconciliationJournal()
        let provider = PlaylistCopyProviderSpy(copiedMBID: copiedMBID)
        let model = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: provider,
            detailProvider: PlaylistCopyDetailProviderSpy(error: PlaylistCopyFixtureError.failed),
            reconciliationJournal: journal
        )

        await model.copy(source)

        XCTAssertTrue(model.requiresReconciliation)
        XCTAssertEqual(model.reconciliationRecord?.destinationMBID, copiedMBID)
        guard case let .verificationNeeded(_, destinationMBID, _)? = model.notice else {
            return XCTFail("Expected verification-needed state")
        }
        XCTAssertEqual(destinationMBID, copiedMBID)
    }

    func testCanonicalDestinationRequiresAuthenticatedOwnerAndSourceProvenance() async {
        let source = playlistDetail(mbid: UUID())
        let wrongSource = UUID()
        let fixtures: [PlaylistDetail] = [
            playlistDetail(
                mbid: UUID(),
                creator: "someone-else",
                copiedFrom: source.mbid.uuidString
            ),
            playlistDetail(
                mbid: UUID(),
                creator: "listener",
                copiedFrom: wrongSource.uuidString
            ),
            playlistDetail(
                mbid: UUID(),
                creator: "listener",
                copiedFrom: nil
            ),
        ]

        for canonical in fixtures {
            let journal = PlaylistCopyReconciliationJournal()
            let provider = PlaylistCopyProviderSpy(copiedMBID: canonical.mbid)
            let model = PlaylistCopyModel(
                account: Account(username: "Listener", token: "token"),
                sourceMBID: source.mbid,
                provider: provider,
                detailProvider: PlaylistCopyDetailProviderSpy(detail: canonical),
                reconciliationJournal: journal
            )

            await model.copy(source)

            XCTAssertTrue(model.requiresReconciliation)
            XCTAssertEqual(model.reconciliationRecord?.destinationMBID, canonical.mbid)
            guard case let .verificationNeeded(_, destinationMBID, _)? = model.notice else {
                return XCTFail("Unrelated canonical details must not confirm a copy")
            }
            XCTAssertEqual(destinationMBID, canonical.mbid)
        }
    }

    func testKnownDestinationPersistsAcrossRelaunchAndReconcilesWithoutOwnedScan() async {
        let suiteName = "PlaylistCopyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let source = playlistDetail(mbid: UUID())
        let destinationMBID = UUID()
        let copyProvider = PlaylistCopyProviderSpy(copiedMBID: destinationMBID)
        let firstModel = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: copyProvider,
            detailProvider: PlaylistCopyDetailProviderSpy(error: PlaylistCopyFixtureError.failed),
            reconciliationJournal: PlaylistCopyReconciliationJournal(defaults: defaults)
        )
        await firstModel.copy(source)

        let profileProvider = PlaylistCopyProfileProviderSpy(error: PlaylistCopyFixtureError.failed)
        let canonicalProvider = PlaylistCopyDetailProviderSpy(detail: playlistDetail(
            mbid: destinationMBID,
            title: "Canonical copy",
            creator: "listener",
            copiedFrom: source.mbid.uuidString
        ))
        let reopenedModel = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: copyProvider,
            detailProvider: canonicalProvider,
            profileProvider: profileProvider,
            reconciliationJournal: PlaylistCopyReconciliationJournal(defaults: defaults)
        )

        await reopenedModel.reconcileAfterOwnedPlaylistsRefresh()

        guard case let .confirmed(copy)? = reopenedModel.notice else {
            return XCTFail("Expected the persisted destination to load canonically")
        }
        XCTAssertEqual(copy.playlistMBID, destinationMBID)
        let copyCalls = await copyProvider.recordedMBIDs()
        let profileCalls = await profileProvider.calls
        XCTAssertEqual(copyCalls, [source.mbid])
        XCTAssertTrue(profileCalls.isEmpty, "A known destination does not need an Owned scan")
    }

    func testIndeterminateAttemptPersistsAcrossRelaunchAndMissingFreshPageCannotUnlockReplay() async {
        let suiteName = "PlaylistCopyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = PlaylistCopyProviderSpy(
            error: PlaylistMutationProviderError.indeterminateCopy
        )
        let source = playlistDetail(mbid: UUID())
        let attemptDate = Date(timeIntervalSince1970: 10_000)
        let journal = PlaylistCopyReconciliationJournal(defaults: defaults)
        let model = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: provider,
            reconciliationJournal: journal,
            now: { attemptDate }
        )

        await model.copy(source)
        let refreshedOwned = PlaylistCopyProfileProviderSpy(page: ProfilePlaylistPage(
            username: "listener",
            category: .owned,
            playlists: [],
            requestedCount: 100,
            offset: 0,
            totalCount: 0
        ))
        let reopenedJournal = PlaylistCopyReconciliationJournal(defaults: defaults)
        let reopenedModel = PlaylistCopyModel(
            account: Account(username: "LISTENER", token: "token"),
            sourceMBID: source.mbid,
            provider: provider,
            profileProvider: refreshedOwned,
            reconciliationJournal: reopenedJournal
        )
        await reopenedModel.reconcileAfterOwnedPlaylistsRefresh()
        await reopenedModel.copy(source)

        XCTAssertTrue(model.requiresReconciliation)
        XCTAssertTrue(reopenedModel.requiresReconciliation)
        guard case .verificationNeeded? = reopenedModel.notice else {
            return XCTFail("Expected the safety lock to remain")
        }
        let calls = await provider.recordedMBIDs()
        XCTAssertEqual(calls, [source.mbid])
        let refreshCalls = await refreshedOwned.calls
        XCTAssertEqual(refreshCalls, [.init(category: .owned, offset: 0, count: 100)])
    }

    func testIndeterminateAttemptResolvesOnlyFromFreshProvenanceAndCanonicalDestination() async {
        let suiteName = "PlaylistCopyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let source = playlistDetail(mbid: UUID())
        let destinationMBID = UUID()
        let attemptDate = Date(timeIntervalSince1970: 20_000)
        let copyProvider = PlaylistCopyProviderSpy(
            error: PlaylistMutationProviderError.indeterminateCopy
        )
        let firstModel = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: copyProvider,
            reconciliationJournal: PlaylistCopyReconciliationJournal(defaults: defaults),
            now: { attemptDate }
        )
        await firstModel.copy(source)

        let candidate = SearchPlaylist(
            title: "Copy of Playlist",
            creator: "listener",
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(destinationMBID.uuidString)",
            isPublic: true,
            lastModifiedAt: attemptDate,
            createdAt: attemptDate.addingTimeInterval(1),
            copiedFrom: source.mbid.uuidString
        )
        let refreshedOwned = PlaylistCopyProfileProviderSpy(page: ProfilePlaylistPage(
            username: "listener",
            category: .owned,
            playlists: [candidate],
            requestedCount: 100,
            offset: 0,
            totalCount: 1
        ))
        let canonical = playlistDetail(
            mbid: destinationMBID,
            title: "Copy of Playlist",
            creator: "listener",
            createdAt: attemptDate.addingTimeInterval(1),
            copiedFrom: source.mbid.uuidString
        )
        let detailProvider = PlaylistCopyDetailProviderSpy(detail: canonical)
        let reopenedModel = PlaylistCopyModel(
            account: Account(username: "LISTENER", token: "token"),
            sourceMBID: source.mbid,
            provider: copyProvider,
            detailProvider: detailProvider,
            profileProvider: refreshedOwned,
            reconciliationJournal: PlaylistCopyReconciliationJournal(defaults: defaults)
        )

        await reopenedModel.reconcileAfterOwnedPlaylistsRefresh()

        XCTAssertTrue(reopenedModel.requiresReconciliation)
        guard case let .confirmed(confirmed)? = reopenedModel.notice else {
            return XCTFail("Expected a canonically verified copy")
        }
        XCTAssertEqual(confirmed.playlistMBID, destinationMBID)
        let copyCalls = await copyProvider.recordedMBIDs()
        let detailCalls = await detailProvider.calls
        XCTAssertEqual(copyCalls, [source.mbid])
        XCTAssertEqual(detailCalls, [destinationMBID])
        reopenedModel.acknowledgeConfirmedCopy()
        XCTAssertFalse(reopenedModel.requiresReconciliation)
    }

    func testOldCopyWithSameProvenanceDoesNotResolveNewIndeterminateAttempt() async {
        let source = playlistDetail(mbid: UUID())
        let attemptDate = Date(timeIntervalSince1970: 30_000)
        let journal = PlaylistCopyReconciliationJournal()
        journal.beginAttempt(username: "listener", sourceMBID: source.mbid, at: attemptDate)
        let oldCopy = SearchPlaylist(
            title: "Old copy",
            creator: "listener",
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(UUID().uuidString)",
            isPublic: true,
            lastModifiedAt: nil,
            createdAt: attemptDate.addingTimeInterval(-60),
            copiedFrom: source.mbid.uuidString
        )
        let model = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: PlaylistCopyProviderSpy(),
            profileProvider: PlaylistCopyProfileProviderSpy(page: ProfilePlaylistPage(
                username: "listener",
                category: .owned,
                playlists: [oldCopy],
                requestedCount: 100,
                offset: 0,
                totalCount: 1
            )),
            reconciliationJournal: journal
        )

        await model.reconcileAfterOwnedPlaylistsRefresh()

        XCTAssertTrue(model.requiresReconciliation)
        guard case .verificationNeeded? = model.notice else {
            return XCTFail("An old copy must not unlock the current attempt")
        }
    }

    func testUnavailableOwnedPageDuringReconciliationReportsSourceVisibilityAndKeepsLock() async {
        let source = playlistDetail(mbid: UUID())
        let journal = PlaylistCopyReconciliationJournal()
        journal.beginAttempt(
            username: "listener",
            sourceMBID: source.mbid,
            at: Date(timeIntervalSince1970: 40_000)
        )
        let copyProvider = PlaylistCopyProviderSpy()
        let model = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: copyProvider,
            profileProvider: PlaylistCopyProfileProviderSpy(
                error: ProfilePlaylistsProviderError.profileUnavailable
            ),
            reconciliationJournal: journal
        )

        await model.reconcileAfterOwnedPlaylistsRefresh()
        await model.copy(source)

        XCTAssertEqual(model.sourceAccessLossReason, .sourceVisibility)
        XCTAssertEqual(
            model.sourceAccessMessage,
            ProfilePlaylistsProviderError.profileUnavailable.localizedDescription
        )
        XCTAssertTrue(model.requiresReconciliation)
        guard case .verificationNeeded? = model.notice else {
            return XCTFail("A failed source reconciliation must keep copy verification locked")
        }
        let copyCalls = await copyProvider.recordedMBIDs()
        XCTAssertTrue(copyCalls.isEmpty, "Reconciliation failure must never replay the copy POST")
    }

    func testMutationJournalRetainsEveryEventInRevisionOrder() async {
        let journal = PlaylistMutationJournal()
        let profilePageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let sourceMBID = UUID()
        let copiedMBID = UUID()
        let accessLoss = PlaylistAccessLossEvent(
            viewerUsername: "listener",
            sourceMBID: sourceMBID,
            reason: .sourceVisibility,
            message: "No longer visible"
        )
        let copy = ConfirmedPlaylistCopy(
            ownerUsername: "listener",
            playlist: SearchPlaylist(
                title: "Copy",
                creator: "listener",
                annotation: nil,
                identifier: "https://listenbrainz.org/playlist/\(copiedMBID.uuidString)",
                isPublic: false,
                lastModifiedAt: nil,
                copiedFrom: sourceMBID.uuidString
            )
        )
        let edit = ConfirmedPlaylistMetadataEdit(
            mbid: sourceMBID,
            ownerUsername: "listener",
            draft: .init(title: "Edited", isPublic: false)
        )

        await journal.recordAccessLoss(
            sourceMBID: sourceMBID,
            viewerUsername: " Listener ",
            reason: accessLoss.reason,
            message: accessLoss.message,
            profilePageCache: profilePageCache
        )
        journal.recordConfirmedCopy(copy.playlist, ownerUsername: "LISTENER")
        journal.recordConfirmedEdit(
            mbid: edit.mbid,
            ownerUsername: "Listener",
            draft: edit.draft
        )

        let entries = journal.entries(after: 0)
        XCTAssertEqual(entries.map(\.revision), [1, 2, 3])
        XCTAssertEqual(entries.map(\.event), [
            .accessLoss(accessLoss),
            .copy(copy),
            .edit(edit),
        ])
        XCTAssertEqual(journal.entries(after: 1).map(\.revision), [2, 3])
    }

    func testCopyModelFlagsVisibleStatePurgeForAuthenticationLoss() async {
        let provider = PlaylistCopyProviderSpy(
            error: PlaylistMutationProviderError.invalidAuthentication
        )
        let source = playlistDetail(mbid: UUID(), isPublic: false)
        let model = PlaylistCopyModel(
            account: Account(username: "listener", token: "revoked"),
            sourceMBID: source.mbid,
            provider: provider,
            reconciliationJournal: PlaylistCopyReconciliationJournal()
        )

        await model.copy(source)

        XCTAssertTrue(model.sourceAccessWasLost)
        XCTAssertEqual(model.sourceAccessLossReason, .authentication)
        XCTAssertEqual(
            model.sourceAccessMessage,
            PlaylistMutationProviderError.invalidAuthentication.localizedDescription
        )
    }

    func testCopyModelClassifiesUnavailableSourceSeparatelyFromAuthenticationLoss() async {
        let provider = PlaylistCopyProviderSpy(
            error: PlaylistMutationProviderError.playlistUnavailable
        )
        let source = playlistDetail(mbid: UUID(), isPublic: false)
        let model = PlaylistCopyModel(
            account: Account(username: "listener", token: "token"),
            sourceMBID: source.mbid,
            provider: provider,
            reconciliationJournal: PlaylistCopyReconciliationJournal()
        )

        await model.copy(source)

        XCTAssertEqual(model.sourceAccessLossReason, .sourceVisibility)
        XCTAssertFalse(model.requiresReconciliation, "A definite 404/403 did not create a copy")
    }

    private func profilePageKey() -> ProfilePlaylistPageKey {
        ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "listener")),
            category: .owned,
            offset: 0,
            count: 20
        )
    }

    private func emptyProfilePage() -> ProfilePlaylistPage {
        ProfilePlaylistPage(
            username: "listener",
            category: .owned,
            playlists: [],
            requestedCount: 20,
            offset: 0,
            totalCount: 0
        )
    }

    private func playlistDetail(
        mbid: UUID,
        title: String = "Playlist",
        creator: String = "source-owner",
        annotation: String? = "Description",
        createdAt: Date? = nil,
        isPublic: Bool = true,
        collaborators: [String] = [],
        copiedFrom: String? = nil,
        tracks: [PlaylistTrack] = []
    ) -> PlaylistDetail {
        PlaylistDetail(
            mbid: mbid,
            title: title,
            creator: creator,
            annotation: annotation,
            createdAt: createdAt,
            lastModifiedAt: nil,
            isPublic: isPublic,
            createdFor: "listener",
            collaborators: collaborators,
            copiedFrom: copiedFrom,
            tracks: tracks
        )
    }

    private func playlistTrack(durationMilliseconds: Int) -> PlaylistTrack {
        PlaylistTrack(
            position: 0,
            recording: Recording(
                identity: .init(mbid: UUID(), msid: nil),
                title: "Track",
                artistName: "Artist",
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: durationMilliseconds,
                source: nil
            ),
            addedAt: nil,
            addedBy: nil
        )
    }
}

private actor PlaylistCopyTransportSpy: PlaylistCopyTransport {
    private let copiedMBID: UUID
    private let error: (any Error & Sendable)?
    private var mbids: [UUID] = []

    init(
        copiedMBID: UUID = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!,
        error: (any Error & Sendable)? = nil
    ) {
        self.copiedMBID = copiedMBID
        self.error = error
    }

    func copy(mbid: UUID) async throws -> UUID {
        mbids.append(mbid)
        if let error { throw error }
        return copiedMBID
    }

    func recordedMBIDs() -> [UUID] { mbids }
}

private actor CancellationCopyTransport: PlaylistCopyTransport {
    private(set) var hasStarted = false
    private(set) var callCount = 0

    func copy(mbid: UUID) async throws -> UUID {
        hasStarted = true
        callCount += 1
        try await Task.sleep(for: .seconds(60))
        return UUID()
    }
}

private actor PlaylistCopyProviderSpy: PlaylistCopyProviding {
    private let copiedMBID: UUID
    private let error: (any Error & Sendable)?
    private let delay: Duration
    private var mbids: [UUID] = []

    init(
        copiedMBID: UUID = UUID(),
        error: (any Error & Sendable)? = nil,
        delay: Duration = .zero
    ) {
        self.copiedMBID = copiedMBID
        self.error = error
        self.delay = delay
    }

    func copy(mbid: UUID) async throws -> UUID {
        mbids.append(mbid)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return copiedMBID
    }

    func recordedMBIDs() -> [UUID] { mbids }
}

private actor PlaylistCopyDetailProviderSpy: PlaylistDetailProviding {
    private let detail: PlaylistDetail?
    private let error: (any Error & Sendable)?
    private(set) var calls: [UUID] = []

    init(
        detail: PlaylistDetail? = nil,
        error: (any Error & Sendable)? = nil
    ) {
        self.detail = detail
        self.error = error
    }

    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        calls.append(mbid)
        if let error { throw error }
        guard let detail else { throw PlaylistCopyFixtureError.failed }
        return detail
    }
}

private struct PlaylistCopyProfileCall: Equatable, Sendable {
    let category: ProfilePlaylistCategory
    let offset: Int
    let count: Int
}

private actor PlaylistCopyProfileProviderSpy: ProfilePlaylistsProviding {
    private let pageValue: ProfilePlaylistPage?
    private let error: (any Error & Sendable)?
    private(set) var calls: [PlaylistCopyProfileCall] = []

    init(
        page: ProfilePlaylistPage? = nil,
        error: (any Error & Sendable)? = nil
    ) {
        pageValue = page
        self.error = error
    }

    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        calls.append(.init(category: category, offset: offset, count: count))
        if let error { throw error }
        guard let pageValue else { throw PlaylistCopyFixtureError.failed }
        return pageValue
    }
}

private enum PlaylistCopyFixtureError: LocalizedError, Sendable {
    case failed

    var errorDescription: String? { "Fixture copy failed." }
}
