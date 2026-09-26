import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class ListeningModelTests: XCTestCase {
    func testActivityCacheKeysDoNotCrossCredentialBoundary() {
        let firstScope = RequestGate.ReadScope.authenticated(token: "first-token")
        let secondScope = RequestGate.ReadScope.authenticated(token: "second-token")

        XCTAssertNotEqual(
            DailyActivityCacheKey(username: "listener", scope: firstScope, period: .thisWeek),
            DailyActivityCacheKey(username: "listener", scope: secondScope, period: .thisWeek)
        )
        XCTAssertNotEqual(
            EraActivityCacheKey(username: "listener", scope: firstScope, period: .thisWeek),
            EraActivityCacheKey(username: "listener", scope: secondScope, period: .thisWeek)
        )
        XCTAssertNotEqual(
            ArtistEvolutionActivityCacheKey(username: "listener", scope: firstScope, period: .thisWeek),
            ArtistEvolutionActivityCacheKey(username: "listener", scope: secondScope, period: .thisWeek)
        )
        XCTAssertNotEqual(
            GenreActivityCacheKey(username: "listener", scope: firstScope, period: .thisWeek),
            GenreActivityCacheKey(username: "listener", scope: secondScope, period: .thisWeek)
        )
    }

    func testLoadBuildsARealSnapshotFromProviderData() async {
        let provider = FixtureProvider()
        let username = "fixture-\(UUID().uuidString)"
        let model = ListeningModel(
            account: Account(username: username, token: ""),
            provider: provider
        )

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.snapshot.recentListens.count, 2)
        XCTAssertEqual(model.snapshot.playingNow?.recording.title, "Playing Now")
        XCTAssertEqual(model.snapshot.listenCount, 42)
        XCTAssertEqual(model.snapshot.topArtists.first?.name, "Fixture Artist")
        XCTAssertEqual(model.snapshot.topReleases.first?.name, "Fixture Album")
        XCTAssertEqual(model.snapshot.topRecordings.first?.title, "Fixture Track")
    }

    func testReleaseGroupRankingIsLazyAndCoalescesRepeatedRequests() async throws {
        let provider = ReleaseGroupRankingProvider(delay: .milliseconds(80))
        let model = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider,
            cache: SnapshotCache(
                rootDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            releaseGroupRankingCache: EntityDetailCache()
        )

        await model.load()
        let beforeRequests = await provider.requestCount()
        XCTAssertEqual(beforeRequests, 0)
        async let first: Void = model.loadReleaseGroupRanking()
        async let second: Void = model.loadReleaseGroupRanking()
        _ = await (first, second)

        let requests = await provider.requestCount()
        XCTAssertEqual(requests, 1)
        guard case let .loaded(groups) = model.releaseGroupRankingState else {
            return XCTFail("Expected the lazy ranking to load")
        }
        XCTAssertEqual(groups.count, 2)
        XCTAssertNotNil(groups.first?.detailDestination)
        XCTAssertNil(groups.last?.detailDestination)
    }

    func testReleaseGroupRankingReopenJoinsTheCancelledViewsFlight() async {
        let provider = ReleaseGroupRankingProvider(delay: .milliseconds(80))
        let model = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider,
            releaseGroupRankingCache: EntityDetailCache()
        )

        let firstConsumer = Task { await model.loadReleaseGroupRanking() }
        while await provider.requestCount() == 0 { await Task.yield() }
        firstConsumer.cancel()
        let replacementConsumer = Task { await model.loadReleaseGroupRanking() }
        await firstConsumer.value
        await replacementConsumer.value

        let requests = await provider.requestCount()
        XCTAssertEqual(requests, 1)
        guard case .loaded = model.releaseGroupRankingState else {
            return XCTFail("The replacement consumer should receive the original request")
        }
    }

    func testReleaseGroupRankingStaleRefreshJoinsExistingFlight() async {
        let cache = EntityDetailCache<ReleaseGroupRankingCacheKey, [RankedReleaseGroup]>(timeToLive: -1)
        let key = ReleaseGroupRankingCacheKey(
            username: "listener",
            scope: .authenticated(token: "token")
        )
        await cache.save(
            [.init(mbid: UUID(), name: "Saved group", artistName: "Artist", artistMBIDs: [], listenCount: 3)],
            for: key
        )
        let provider = ReleaseGroupRankingProvider(delay: .milliseconds(80))
        let model = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider,
            releaseGroupRankingCache: cache
        )

        let revalidation = Task { await model.loadReleaseGroupRanking() }
        while await provider.requestCount() == 0 { await Task.yield() }
        async let pullToRefresh: Void = model.refreshReleaseGroupRankingIfLoaded()
        async let explicitRefresh: Void = model.loadReleaseGroupRanking(retrying: true)
        _ = await (pullToRefresh, explicitRefresh)
        await revalidation.value

        let requests = await provider.requestCount()
        XCTAssertEqual(requests, 1)
    }

    func testReleaseGroupRankingFailureRequiresExplicitRetry() async {
        let provider = ReleaseGroupRankingProvider(fails: true)
        let model = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider,
            releaseGroupRankingCache: EntityDetailCache()
        )

        await model.loadReleaseGroupRanking()
        await model.loadReleaseGroupRanking()
        var requests = await provider.requestCount()
        XCTAssertEqual(requests, 1)

        await model.loadReleaseGroupRanking(retrying: true)
        requests = await provider.requestCount()
        XCTAssertEqual(requests, 2)
    }

    func testCancellingReleaseGroupRankingAtSessionTeardownStopsTheFlight() async {
        let provider = ReleaseGroupRankingProvider(delay: .seconds(30))
        let model = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider,
            releaseGroupRankingCache: EntityDetailCache()
        )

        let consumer = Task { await model.loadReleaseGroupRanking() }
        while await provider.requestCount() == 0 { await Task.yield() }
        model.cancelReleaseGroupRankingLoad()
        await consumer.value

        XCTAssertEqual(model.releaseGroupRankingState, .idle)
        let cancellations = await provider.cancellationCount()
        XCTAssertEqual(cancellations, 1)
    }

    func testReleaseGroupRankingFreshCacheAvoidsNetworkAndIsCredentialIsolated() async {
        let cache = EntityDetailCache<ReleaseGroupRankingCacheKey, [RankedReleaseGroup]>()
        let provider = ReleaseGroupRankingProvider()
        let first = ListeningModel(
            account: Account(username: " Listener ", token: "first-token"),
            provider: provider,
            releaseGroupRankingCache: cache
        )
        await first.loadReleaseGroupRanking()
        let firstRequests = await provider.requestCount()
        XCTAssertEqual(firstRequests, 1)

        let sameScope = ListeningModel(
            account: Account(username: "listener", token: "first-token"),
            provider: provider,
            releaseGroupRankingCache: cache
        )
        await sameScope.loadReleaseGroupRanking()
        let sameScopeRequests = await provider.requestCount()
        XCTAssertEqual(sameScopeRequests, 1)

        let otherScope = ListeningModel(
            account: Account(username: "listener", token: "second-token"),
            provider: provider,
            releaseGroupRankingCache: cache
        )
        await otherScope.loadReleaseGroupRanking()
        let otherScopeRequests = await provider.requestCount()
        XCTAssertEqual(otherScopeRequests, 2)
    }

    func testStaleReleaseGroupRankingStaysVisibleWhenRefreshFails() async throws {
        let cache = EntityDetailCache<ReleaseGroupRankingCacheKey, [RankedReleaseGroup]>(timeToLive: -1)
        let stale = [RankedReleaseGroup(mbid: UUID(), name: "Saved group", artistName: "Artist", artistMBIDs: [], listenCount: 3)]
        await cache.save(stale, for: .init(username: "listener", scope: .authenticated(token: "token")))
        let provider = ReleaseGroupRankingProvider(fails: true)
        let model = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider,
            releaseGroupRankingCache: cache
        )

        await model.loadReleaseGroupRanking()
        guard case let .loaded(groups) = model.releaseGroupRankingState else {
            return XCTFail("Stale release groups should remain visible")
        }
        XCTAssertEqual(groups, stale)
        XCTAssertNotNil(model.releaseGroupRankingRefreshMessage)
    }

    func testArtistFilteringUsesMBIDsBeforeDisplayNames() async {
        let provider = FixtureProvider()
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        await model.load()

        let artist = RankedArtist(
            mbid: FixtureProvider.artistMBID,
            name: "A different localized display name",
            listenCount: 2
        )

        XCTAssertEqual(model.listens(for: artist).count, 2)
        XCTAssertEqual(model.recordings(for: artist).count, 1)
    }

    func testRecordingIdentityPrefersMusicBrainzIDAndFallsBackToMSID() {
        let mbid = UUID()
        let msid = UUID()

        XCTAssertEqual(recording(mbid: mbid, msid: msid).id, "mbid:\(mbid.uuidString)")
        XCTAssertEqual(recording(mbid: nil, msid: msid).id, "msid:\(msid.uuidString)")
    }

    func testPaginationKeepsListensSharingTheBoundarySecond() async {
        let provider = BoundaryProvider()
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.load()
        await model.loadMore()

        XCTAssertEqual(model.snapshot.recentListens.count, 42)
        XCTAssertTrue(model.snapshot.recentListens.contains { $0.recording.title == "Boundary sibling" })
        XCTAssertTrue(model.snapshot.recentListens.contains { $0.recording.title == "Older listen" })
        XCTAssertFalse(model.canLoadMore)
        let requestedCount = await provider.requestedCount()
        XCTAssertEqual(requestedCount, 100)
        let requestedBefore = await provider.requestedBefore()
        XCTAssertEqual(requestedBefore?.timeIntervalSince1970, 1_901)
    }

    func testConfirmedListenDeletionRemovesEveryMatchingVisibleOccurrenceAndFiltersRefreshes() async {
        let provider = DeleteListenProvider()
        let model = ListeningModel(
            account: Account(username: "delete-\(UUID().uuidString)", token: "token"),
            provider: provider,
            cache: SnapshotCache(rootDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        )

        await model.load()
        await model.selectHistoryDay(.now)
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)

        await model.deleteListen(target)

        XCTAssertFalse(model.snapshot.recentListens.contains { $0.recording.identity.msid == target.recording.identity.msid && $0.listenedAt == target.listenedAt })
        XCTAssertFalse(model.selectedDayListens.contains { $0.recording.identity.msid == target.recording.identity.msid && $0.listenedAt == target.listenedAt })
        let deleteRequests = await provider.deleteRequestCount()
        XCTAssertEqual(deleteRequests, 1)

        await model.refresh()
        XCTAssertFalse(model.snapshot.recentListens.contains { $0.recording.identity.msid == target.recording.identity.msid && $0.listenedAt == target.listenedAt })
    }

    func testAmbiguousListenDeletionRetainsListenAndNeverReplays() async {
        let provider = DeleteListenProvider(deleteResult: .ambiguous)
        let model = ListeningModel(
            account: Account(username: "delete-\(UUID().uuidString)", token: "token"),
            provider: provider
        )

        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)
        await model.deleteListen(target)
        await model.deleteListen(target)
        await model.refresh()

        XCTAssertTrue(model.snapshot.recentListens.contains { $0.id == target.id })
        let deleteRequests = await provider.deleteRequestCount()
        XCTAssertEqual(deleteRequests, 1)
        XCTAssertTrue(model.actionError?.contains("didn’t send it again") == true)
    }

    func testConfirmedListenDeletionRemainsHiddenAfterRelaunch() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journalURL = root.appending(path: "journal.json")
        let account = Account(username: "listener", token: "token")
        let provider = DeleteListenProvider()
        let firstJournal = ListenDeletionSafetyJournal(fileURL: journalURL)
        let model = ListeningModel(account: account, provider: provider, deletionJournal: firstJournal)

        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)
        await model.deleteListen(target)

        let reopenedJournal = ListenDeletionSafetyJournal(fileURL: journalURL)
        let reopenedModel = ListeningModel(account: account, provider: provider, deletionJournal: reopenedJournal)
        await reopenedModel.load()

        XCTAssertFalse(reopenedModel.snapshot.recentListens.contains { $0.id == target.id })
        let timestamp = Int(target.listenedAt.timeIntervalSince1970)
        let msid = try! XCTUnwrap(target.recording.identity.msid)
        XCTAssertEqual(
            reopenedJournal.state(username: account.username, listenedAt: timestamp, recordingMSID: msid),
            .confirmed
        )
    }

    func testConfirmedDeletionIsRemovedFromCacheBeforeAnOfflineRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = Account(username: "listener", token: "token")
        let journal = ListenDeletionSafetyJournal(fileURL: root.appending(path: "journal.json"))
        let initialCache = SnapshotCache(rootDirectory: root)
        let initialModel = ListeningModel(
            account: account,
            provider: DeleteListenProvider(),
            cache: initialCache,
            deletionJournal: journal
        )

        await initialModel.load()
        let target = try XCTUnwrap(initialModel.snapshot.recentListens.first)
        let timestamp = Int(target.listenedAt.timeIntervalSince1970)
        let msid = try XCTUnwrap(target.recording.identity.msid)
        journal.beginAttempt(username: account.username, listenedAt: timestamp, recordingMSID: msid)
        journal.markConfirmed(username: account.username, listenedAt: timestamp, recordingMSID: msid)

        let offlineCache = SnapshotCache(rootDirectory: root)
        let offlineModel = ListeningModel(
            account: account,
            provider: DeleteListenProvider(recentListensFails: true),
            cache: offlineCache,
            deletionJournal: journal
        )
        await offlineModel.load()

        XCTAssertFalse(offlineModel.snapshot.recentListens.contains { $0.id == target.id })
        XCTAssertEqual(offlineModel.phase, .ready)

        let persistedCache = SnapshotCache(rootDirectory: root)
        let persistedLease = await persistedCache.beginSession(username: account.username)
        let persistedValue = await persistedCache.load(username: account.username, lease: persistedLease)
        let persisted = try XCTUnwrap(persistedValue)
        XCTAssertFalse(persisted.recentListens.contains { $0.id == target.id })
    }

    func testDefiniteListenDeletionFailureRetainsListenAndAllowsLaterRetry() async {
        let provider = DeleteListenProvider(deleteResult: .definiteFailure)
        let model = ListeningModel(
            account: Account(username: "delete-\(UUID().uuidString)", token: "token"),
            provider: provider
        )

        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)
        await model.deleteListen(target)
        await model.deleteListen(target)

        XCTAssertTrue(model.snapshot.recentListens.contains { $0.id == target.id })
        let deleteRequests = await provider.deleteRequestCount()
        XCTAssertEqual(deleteRequests, 2)
    }

    func testDuplicateRapidDeletionRequestsDispatchOnlyOnce() async {
        let provider = DeleteListenProvider(deleteDelay: .milliseconds(30))
        let model = ListeningModel(
            account: Account(username: "delete-\(UUID().uuidString)", token: "token"),
            provider: provider
        )

        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)
        async let first: Void = model.deleteListen(target)
        async let second: Void = model.deleteListen(target)
        _ = await (first, second)

        let deleteRequests = await provider.deleteRequestCount()
        XCTAssertEqual(deleteRequests, 1)
        XCTAssertFalse(model.snapshot.recentListens.contains { $0.id == target.id })
    }

    func testConcurrentModelsShareOneDeletionReservation() async {
        let journal = ListenDeletionSafetyJournal()
        let provider = DeleteListenProvider(
            deleteDelay: .milliseconds(30),
            validationDelay: .milliseconds(30)
        )
        let account = Account(username: "listener", token: "token")
        let firstModel = ListeningModel(account: account, provider: provider, deletionJournal: journal)
        let secondModel = ListeningModel(account: account, provider: provider, deletionJournal: journal)
        await firstModel.load()
        let target = try! XCTUnwrap(firstModel.snapshot.recentListens.first)

        async let first: Void = firstModel.deleteListen(target)
        async let second: Void = secondModel.deleteListen(target)
        _ = await (first, second)

        let deleteRequests = await provider.deleteRequestCount()
        XCTAssertEqual(deleteRequests, 1)
    }

    func testUnreadableDeletionJournalBlocksPostsUntilExplicitReset() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journalURL = root.appending(path: "journal.json")
        try! Data("not valid JSON".utf8).write(to: journalURL)
        let journal = ListenDeletionSafetyJournal(fileURL: journalURL)
        let provider = DeleteListenProvider()
        let model = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider,
            deletionJournal: journal
        )
        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)

        await model.deleteListen(target)

        XCTAssertTrue(model.deletionSafetyRecoveryNeeded)
        let blockedRequestCount = await provider.deleteRequestCount()
        XCTAssertEqual(blockedRequestCount, 0)

        model.resetDeletionSafetyData()
        await model.deleteListen(target)

        XCTAssertFalse(model.deletionSafetyRecoveryNeeded)
        let acceptedRequestCount = await provider.deleteRequestCount()
        XCTAssertEqual(acceptedRequestCount, 1)
    }

    func testIndeterminateDeletionSurvivesRelaunchWithoutFilteringTheListen() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journalURL = root.appending(path: "journal.json")
        let journal = ListenDeletionSafetyJournal(fileURL: journalURL)
        let provider = DeleteListenProvider(deleteResult: .ambiguous)
        let account = Account(username: " Delete Listener ", token: "token")
        let model = ListeningModel(account: account, provider: provider, deletionJournal: journal)

        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)
        await model.deleteListen(target)
        XCTAssertTrue(model.snapshot.recentListens.contains { $0.id == target.id })

        let reopened = ListenDeletionSafetyJournal(fileURL: journalURL)
        let reopenedModel = ListeningModel(account: account, provider: provider, deletionJournal: reopened)
        await reopenedModel.load()
        XCTAssertTrue(reopenedModel.isDeletionIndeterminate(target))
        XCTAssertTrue(reopenedModel.snapshot.recentListens.contains { $0.id == target.id })
    }

    func testIndeterminateRetryCancellationPreservesOriginalReplayBarrier() async {
        let journal = ListenDeletionSafetyJournal()
        let provider = DeleteListenProvider(deleteResult: .cancelled)
        let account = Account(username: "listener", token: "token")
        let model = ListeningModel(account: account, provider: provider, deletionJournal: journal)

        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)
        let timestamp = Int(target.listenedAt.timeIntervalSince1970)
        let msid = try! XCTUnwrap(target.recording.identity.msid)
        journal.beginAttempt(username: account.username, listenedAt: timestamp, recordingMSID: msid)

        await model.retryListenDeletionAnyway(target)

        XCTAssertTrue(model.isDeletionIndeterminate(target))
        XCTAssertEqual(
            journal.state(username: account.username, listenedAt: timestamp, recordingMSID: msid),
            .indeterminate
        )
    }

    func testExplicitIndeterminateRetryPostsOnceAndPreservesBarrierAfterDefiniteFailure() async {
        let journal = ListenDeletionSafetyJournal()
        let provider = DeleteListenProvider(deleteResults: [.ambiguous, .definiteFailure])
        let account = Account(username: "listener", token: "token")
        let model = ListeningModel(account: account, provider: provider, deletionJournal: journal)

        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)
        await model.deleteListen(target)
        await model.retryListenDeletionAnyway(target)

        let deleteRequests = await provider.deleteRequestCount()
        XCTAssertEqual(deleteRequests, 2)
        XCTAssertTrue(model.snapshot.recentListens.contains { $0.id == target.id })
        XCTAssertTrue(model.isDeletionIndeterminate(target))
    }

    func testDeletionJournalSeparatesAccountsAndContainsNoTokenField() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journalURL = root.appending(path: "journal.json")
        let journal = ListenDeletionSafetyJournal(fileURL: journalURL)
        let msid = UUID()

        journal.beginAttempt(username: " Listener ", listenedAt: 123, recordingMSID: msid)

        XCTAssertEqual(journal.state(username: "listener", listenedAt: 123, recordingMSID: msid), .indeterminate)
        XCTAssertNil(journal.state(username: "other-listener", listenedAt: 123, recordingMSID: msid))
        let data = try Data(contentsOf: journalURL)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(json.contains("super-secret-value"))
    }

    func testMismatchedValidatedUsernameSendsNoDeletePost() async {
        let provider = DeleteListenProvider(canonicalUsername: "someone-else")
        let model = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider
        )

        await model.load()
        let target = try! XCTUnwrap(model.snapshot.recentListens.first)
        await model.deleteListen(target)

        XCTAssertTrue(model.snapshot.recentListens.contains { $0.id == target.id })
        let deleteRequests = await provider.deleteRequestCount()
        XCTAssertEqual(deleteRequests, 0)
        XCTAssertTrue(model.actionError?.contains("another account") == true)
    }

    func testDeletionRejectsUnauthenticatedPlayingNowAndUnmappedListensWithoutPosting() async {
        let provider = DeleteListenProvider()
        let unauthenticated = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider
        )
        await unauthenticated.load()
        let submitted = try! XCTUnwrap(unauthenticated.snapshot.recentListens.first)
        await unauthenticated.deleteListen(submitted)

        let authenticated = ListeningModel(
            account: Account(username: "listener", token: "token"),
            provider: provider
        )
        let playingNow = Listen(
            recording: submitted.recording,
            listenedAt: submitted.listenedAt,
            insertedAt: submitted.insertedAt,
            isPlayingNow: true
        )
        await authenticated.deleteListen(playingNow)
        let unmapped = Listen(
            recording: Recording(
                identity: .init(mbid: nil, msid: nil),
                title: "Unmapped",
                artistName: "Artist",
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: submitted.listenedAt,
            insertedAt: nil,
            isPlayingNow: false
        )
        await authenticated.deleteListen(unmapped)

        let deleteRequests = await provider.deleteRequestCount()
        XCTAssertEqual(deleteRequests, 0)
    }

    nonisolated func testDeleteProviderTreatsServerUnknownAsIndeterminate() async {
        let transport = DeleteListenTransportSpy(error: .unknownError)
        let provider = ListenBrainzProvider(
            token: "token",
            gate: RequestGate(minimumInterval: .zero),
            deletionTransport: transport
        )

        do {
            try await provider.deleteListen(listenedAt: .now, recordingMSID: UUID())
            XCTFail("Expected an indeterminate outcome")
        } catch ProviderError.deleteListenOutcomeUnknown {
            // A 5xx may follow a committed queue insert, so it is never retryable.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 1)
    }

    nonisolated func testDeleteProviderPreservesDefiniteValidationFailure() async {
        let transport = DeleteListenTransportSpy(error: .invalidJSON)
        let provider = ListenBrainzProvider(
            token: "token",
            gate: RequestGate(minimumInterval: .zero),
            deletionTransport: transport
        )

        do {
            try await provider.deleteListen(listenedAt: .now, recordingMSID: UUID())
            XCTFail("Expected invalid JSON")
        } catch ProviderError.deleteListenRejected {
            // The server rejected the body before accepting a deletion.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 1)
    }

    nonisolated func testDeleteProviderCancellationBeforeTransportRemainsCancellation() async throws {
        let gate = RequestGate(minimumInterval: .seconds(5))
        _ = try await gate.perform { true }
        let transport = DeleteListenTransportSpy()
        let provider = ListenBrainzProvider(token: "token", gate: gate, deletionTransport: transport)
        let task = Task {
            try await provider.deleteListen(listenedAt: .now, recordingMSID: UUID())
        }
        await Task.yield()
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected pre-transport cancellation")
        } catch is CancellationError {
            // No POST was admitted.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 0)
    }

    nonisolated func testDeleteProviderCancellationAfterTransportIsIndeterminate() async throws {
        let transport = DeleteListenTransportSpy(waitsForCancellation: true)
        let provider = ListenBrainzProvider(
            token: "token",
            gate: RequestGate(minimumInterval: .zero),
            deletionTransport: transport
        )
        let task = Task {
            try await provider.deleteListen(listenedAt: .now, recordingMSID: UUID())
        }
        while !(await transport.hasStarted) { await Task.yield() }
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected an indeterminate post-transport cancellation")
        } catch ProviderError.deleteListenOutcomeUnknown {
            // Transport began, so URLSession cancellation cannot prove rejection.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 1)
    }

    func testHistoryDayBoundsUseLocalCalendarArithmeticAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12))!
        let bounds = HistoryDayBounds(day: day, calendar: calendar)

        XCTAssertEqual(bounds.day, calendar.startOfDay(for: day))
        XCTAssertEqual(bounds.earliest.timeIntervalSince(bounds.day), -1)
        XCTAssertEqual(bounds.latest.timeIntervalSince(bounds.day), 23 * 60 * 60)
    }

    func testSelectedDayForwardsStrictDayBoundsWithoutChangingSnapshot() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let provider = DayHistoryProvider(mode: .singleDay)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        let listensBefore = model.snapshot.recentListens
        let savedAtBefore = model.snapshot.savedAt

        await model.selectHistoryDay(day, calendar: calendar)

        let request = await provider.requests().first
        XCTAssertEqual(request?.before, HistoryDayBounds(day: day, calendar: calendar).latest)
        XCTAssertEqual(request?.after, HistoryDayBounds(day: day, calendar: calendar).earliest)
        XCTAssertEqual(model.selectedDayListens.count, 1)
        XCTAssertEqual(model.snapshot.recentListens, listensBefore)
        XCTAssertEqual(model.snapshot.savedAt, savedAtBefore)
    }

    func testSelectedDayRefreshPreservesOriginalCalendarBounds() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let day = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let provider = DayHistoryProvider(mode: .singleDay)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)

        await model.selectHistoryDay(day, calendar: calendar)
        await model.refreshSelectedHistoryDay()

        let requests = await provider.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].before, requests[1].before)
        XCTAssertEqual(requests[0].after, requests[1].after)
    }

    func testCancellingCurrentDayLoadClearsLoadingWithoutShowingAnError() async throws {
        let provider = DayHistoryProvider(mode: .staleSelection)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        let task = Task { await model.selectHistoryDay(.now) }
        let clock = ContinuousClock()
        while await provider.requests().isEmpty {
            try await clock.sleep(for: .milliseconds(1))
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.isLoadingSelectedDay)
        XCTAssertNil(model.selectedDayError)
    }

    func testCancelledDayLoadThatReturnsNormallyStillClearsLoading() async throws {
        let provider = DayHistoryProvider(mode: .returnsAfterCancellation)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        let task = Task { await model.selectHistoryDay(.now) }
        let clock = ContinuousClock()
        while await provider.requests().isEmpty {
            try await clock.sleep(for: .milliseconds(1))
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.isLoadingSelectedDay)
        XCTAssertTrue(model.selectedDayListens.isEmpty)
        XCTAssertNil(model.selectedDayError)
    }

    func testCancelledDayLoadReportedAsURLErrorDoesNotBecomeFailure() async throws {
        let provider = DayHistoryProvider(mode: .urlCancellation)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        let task = Task { await model.selectHistoryDay(.now) }
        let clock = ContinuousClock()
        while await provider.requests().isEmpty {
            try await clock.sleep(for: .milliseconds(1))
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.isLoadingSelectedDay)
        XCTAssertNil(model.selectedDayError)
    }

    func testNewerDaySelectionSupersedesOlderResult() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let provider = DayHistoryProvider(mode: .staleSelection)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)

        async let first: Void = model.selectHistoryDay(firstDay)
        try? await ContinuousClock().sleep(for: .milliseconds(5))
        await model.selectHistoryDay(secondDay)
        await first

        XCTAssertEqual(model.selectedHistoryDay?.day, HistoryDayBounds(day: secondDay).day)
        XCTAssertEqual(model.selectedDayListens.first?.recording.title, "Newer day")
    }

    func testSelectedDayPaginationKeepsLowerBoundAndDistinctMSIDs() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let provider = DayHistoryProvider(mode: .boundarySiblings)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)

        await model.selectHistoryDay(day, calendar: calendar)
        await model.loadMoreSelectedHistoryDay()

        let bounds = HistoryDayBounds(day: day, calendar: calendar)
        let requests = await provider.requests()
        XCTAssertEqual(requests.last?.after, bounds.earliest)
        XCTAssertEqual(model.selectedDayListens.count, 102)
        XCTAssertEqual(Set(model.selectedDayListens.map(\.id)).count, 102)
        XCTAssertTrue(model.selectedDayListens.contains { $0.recording.identity.msid != nil })
    }

    func testSelectedDayStopsWhenAPageCannotAdvanceCursor() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2025, month: 6, day: 8, hour: 12))!
        let provider = DayHistoryProvider(mode: .repeatedCursor)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)

        await model.selectHistoryDay(day, calendar: calendar)
        await model.loadMoreSelectedHistoryDay()

        XCTAssertFalse(model.canLoadMoreSelectedDay)
    }

    func testSelectingAnotherDayResetsSupersededPaginationState() async throws {
        let provider = DayHistoryProvider(mode: .stalePagination)
        let model = ListeningModel(account: Account(username: "fixture", token: ""), provider: provider)
        await model.selectHistoryDay(.now.addingTimeInterval(-86_400))
        let pagination = Task { await model.loadMoreSelectedHistoryDay() }
        let clock = ContinuousClock()
        while await provider.requests().count < 2 {
            try await clock.sleep(for: .milliseconds(1))
        }

        await model.selectHistoryDay(.now)
        await pagination.value

        XCTAssertFalse(model.isLoadingSelectedDay)
        XCTAssertFalse(model.isLoadingMoreSelectedDay)
        XCTAssertEqual(model.selectedDayListens.first?.recording.title, "Replacement day")
    }

    func testRecentHistoryStopsWhenAFullPageCannotAdvanceCursor() async {
        let provider = DayHistoryProvider(mode: .repeatedCursor)
        let model = ListeningModel(
            account: Account(username: "recent-repeat-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.load()
        await model.loadMore()

        XCTAssertFalse(model.canLoadMore)
        XCTAssertEqual(model.snapshot.recentListens.count, 100)
    }

    func testInvalidatedCacheLeaseRejectsLateWrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BrainzCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SnapshotCache(rootDirectory: root)
        let username = "lease-fixture"
        let firstLease = await cache.beginSession(username: username)

        await cache.save(.empty, username: username, lease: firstLease)
        let initialValue = await cache.load(username: username, lease: firstLease)
        XCTAssertNotNil(initialValue)

        try await cache.invalidate(username: username)
        await cache.save(.empty, username: username, lease: firstLease)
        let secondLease = await cache.beginSession(username: username)
        let valueAfterInvalidation = await cache.load(username: username, lease: secondLease)
        XCTAssertNil(valueAfterInvalidation)
    }

    func testListeningActivityUsesServerBucketsAndCachesEachPeriod() async {
        let provider = FixtureProvider()
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.loadListeningActivity(for: .thisMonth)
        await model.loadListeningActivity(for: .lastMonth)
        await model.loadListeningActivity(for: .thisMonth)

        guard case let .loaded(activity) = model.activityState(for: .thisMonth) else {
            return XCTFail("Expected This Month activity to load")
        }
        XCTAssertEqual(activity.totalListens, 15)
        XCTAssertEqual(activity.busiestBucket?.label, "Tuesday")
        XCTAssertEqual(activity.busiestBucket?.listenCount, 9)
        let thisMonthRequests = await provider.activityRequestCount(for: .thisMonth)
        let lastMonthRequests = await provider.activityRequestCount(for: .lastMonth)
        XCTAssertEqual(thisMonthRequests, 1)
        XCTAssertEqual(lastMonthRequests, 1)
    }

    func testListeningActivityPeriodMapsToListenBrainzRanges() {
        XCTAssertEqual(ListenBrainzProvider.range(for: .thisWeek).rawValue, "this_week")
        XCTAssertEqual(ListenBrainzProvider.range(for: .thisMonth).rawValue, "this_month")
        XCTAssertEqual(ListenBrainzProvider.range(for: .thisYear).rawValue, "this_year")
        XCTAssertEqual(ListenBrainzProvider.range(for: .lastWeek).rawValue, "week")
        XCTAssertEqual(ListenBrainzProvider.range(for: .lastMonth).rawValue, "month")
        XCTAssertEqual(ListenBrainzProvider.range(for: .lastYear).rawValue, "year")
        XCTAssertEqual(ListenBrainzProvider.range(for: .allTime).rawValue, "all_time")
    }

    func testCancelledActivityLoadReturnsToIdle() async throws {
        let provider = FixtureProvider(activityDelay: .seconds(1))
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let task = Task { await model.loadListeningActivity(for: .thisWeek) }
        let clock = ContinuousClock()
        while await provider.activityRequestCount(for: .thisWeek) == 0 {
            try await clock.sleep(for: .milliseconds(1))
        }

        task.cancel()
        await task.value

        XCTAssertEqual(model.activityState(for: .thisWeek), .idle)
    }

    func testReplacementActivityLoadSurvivesOlderCancellation() async throws {
        let provider = FixtureProvider(activityDelay: .milliseconds(80))
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let first = Task { await model.loadListeningActivity(for: .thisWeek) }
        let clock = ContinuousClock()
        while await provider.activityRequestCount(for: .thisWeek) < 1 {
            try await clock.sleep(for: .milliseconds(1))
        }

        let replacement = Task { await model.loadListeningActivity(for: .thisWeek) }
        while await provider.activityRequestCount(for: .thisWeek) < 2 {
            try await clock.sleep(for: .milliseconds(1))
        }
        first.cancel()

        await first.value
        await replacement.value

        guard case .loaded = model.activityState(for: .thisWeek) else {
            return XCTFail("Expected the replacement request to remain loaded")
        }
        let requestCount = await provider.activityRequestCount(for: .thisWeek)
        XCTAssertEqual(requestCount, 2)
    }

    func testRetryingLoadedActivityStartsANewRequest() async {
        let provider = FixtureProvider()
        let model = ListeningModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.loadListeningActivity(for: .thisWeek)
        await model.loadListeningActivity(for: .thisWeek)
        let initialRequestCount = await provider.activityRequestCount(for: .thisWeek)
        XCTAssertEqual(initialRequestCount, 1)

        await model.loadListeningActivity(for: .thisWeek, retrying: true)
        let retryRequestCount = await provider.activityRequestCount(for: .thisWeek)
        XCTAssertEqual(retryRequestCount, 2)
    }

    func testDailyActivityNormalizesToACompleteUTCWeek() {
        let activity = DailyActivity(
            period: .thisWeek,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            dailyActivity: [
                "Monday": [
                    .init(hour: 0, listenCount: 2),
                    .init(hour: 0, listenCount: 3),
                    .init(hour: 24, listenCount: 99),
                    .init(hour: -1, listenCount: 99),
                    .init(hour: 3, listenCount: -8),
                ],
                "Sunday": [.init(hour: 23, listenCount: 7)],
            ]
        )

        XCTAssertEqual(activity.cells.count, 168)
        XCTAssertEqual(activity.cell(weekday: .monday, hour: 0)?.listenCount, 5)
        XCTAssertEqual(activity.cell(weekday: .monday, hour: 3)?.listenCount, 0)
        XCTAssertEqual(activity.cell(weekday: .tuesday, hour: 12)?.listenCount, 0)
        XCTAssertEqual(activity.cell(weekday: .sunday, hour: 23)?.listenCount, 7)
        XCTAssertNil(activity.cell(weekday: .monday, hour: 24))
    }

    func testDailyActivityDateRangeIsFormattedInUTC() {
        let activity = DailyActivity(
            period: .thisWeek,
            from: Date(timeIntervalSince1970: 1_735_689_600), // 2025-01-01 00:00 UTC
            to: Date(timeIntervalSince1970: 1_735_776_000),   // 2025-01-02 00:00 UTC
            lastUpdated: .distantPast,
            dailyActivity: [:]
        )

        XCTAssertEqual(
            TasteView.dailyActivityDateRange(activity, locale: Locale(identifier: "en_US_POSIX")),
            "Jan 1, 2025 – Jan 2, 2025 · UTC"
        )
    }

    func testDailyActivityCachesOneFreshRequestPerNormalizedUserAndPeriod() async {
        let cache = EntityDetailCache<DailyActivityCacheKey, DailyActivity>()
        let provider = DailyActivityProvider(result: .activity(listenCount: 4))
        let first = ListeningModel(
            account: Account(username: " Listener ", token: ""),
            provider: provider,
            dailyActivityCache: cache
        )

        await first.loadDailyActivity(for: .thisWeek)
        await first.loadDailyActivity(for: .thisWeek)
        let firstRequestCount = await provider.requestCount()
        XCTAssertEqual(firstRequestCount, 1)

        let sameUser = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            dailyActivityCache: cache
        )
        await sameUser.loadDailyActivity(for: .thisWeek)
        let sameUserRequestCount = await provider.requestCount()
        XCTAssertEqual(sameUserRequestCount, 1)

        let otherUser = ListeningModel(
            account: Account(username: "someone-else", token: ""),
            provider: provider,
            dailyActivityCache: cache
        )
        await otherUser.loadDailyActivity(for: .thisWeek)
        await otherUser.loadDailyActivity(for: .thisMonth)
        let isolatedRequestCount = await provider.requestCount()
        XCTAssertEqual(isolatedRequestCount, 3)
    }

    func testStaleDailyActivityStaysVisibleDuringRefreshAndOnFailure() async throws {
        let cache = EntityDetailCache<DailyActivityCacheKey, DailyActivity>(timeToLive: -1)
        let stale = DailyActivity.fixture(period: .thisWeek, listenCount: 3)
        await cache.save(
            stale,
            for: .init(
                username: "listener",
                scope: .authenticated(token: ""),
                period: .thisWeek
            )
        )
        let provider = DailyActivityProvider(result: .failure, delay: .seconds(1))
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            dailyActivityCache: cache
        )

        let task = Task { await model.loadDailyActivity(for: .thisWeek) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        guard case let .loaded(visible) = model.dailyActivityState(for: .thisWeek) else {
            return XCTFail("Stale data should remain visible while refreshing")
        }
        XCTAssertEqual(visible.totalListens, stale.totalListens)

        await task.value
        guard case let .loaded(retained) = model.dailyActivityState(for: .thisWeek) else {
            return XCTFail("A refresh failure must not discard stale data")
        }
        XCTAssertEqual(retained.totalListens, stale.totalListens)
        XCTAssertNotNil(model.dailyActivityRefreshMessage(for: .thisWeek))
    }

    func testDailyActivityReplacementCannotBeOverwrittenByOlderRequest() async throws {
        let provider = DailyActivityProvider(
            results: [.activity(listenCount: 2), .activity(listenCount: 9)],
            delays: [.milliseconds(80), .milliseconds(1)],
            ignoresCancellation: true
        )
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            dailyActivityCache: EntityDetailCache()
        )

        let first = Task { await model.loadDailyActivity(for: .thisWeek) }
        while await provider.requestCount() < 1 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        let replacement = Task { await model.loadDailyActivity(for: .thisWeek, retrying: true) }
        await first.value
        await replacement.value

        guard case let .loaded(activity) = model.dailyActivityState(for: .thisWeek) else {
            return XCTFail("Expected replacement result")
        }
        XCTAssertEqual(activity.totalListens, 9)
    }

    func testDailyActivityNilAndAllZeroResponsesAreHonest() async {
        let noContent = DailyActivityProvider(result: .noContent)
        let noContentModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: noContent,
            dailyActivityCache: EntityDetailCache()
        )
        await noContentModel.loadDailyActivity(for: .thisWeek)
        XCTAssertEqual(noContentModel.dailyActivityState(for: .thisWeek), .unavailable)

        let zeros = DailyActivityProvider(result: .activity(listenCount: 0))
        let zeroModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: zeros,
            dailyActivityCache: EntityDetailCache()
        )
        await zeroModel.loadDailyActivity(for: .thisWeek)
        guard case let .loaded(activity) = zeroModel.dailyActivityState(for: .thisWeek) else {
            return XCTFail("Expected a loaded all-zero matrix")
        }
        XCTAssertTrue(activity.isEmpty)
    }

    func testEraActivityNormalizesYearsAndBuildsCompleteDecades() {
        let activity = EraActivity(
            period: .thisYear,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            years: [
                .init(year: 1997, listenCount: 4),
                .init(year: 1997, listenCount: 5),
                .init(year: 2011, listenCount: 7),
                .init(year: 2024, listenCount: 3),
                .init(year: 2025, listenCount: -8),
                .init(year: -1, listenCount: 99),
            ]
        )

        XCTAssertEqual(activity.years.map(\.year), [1997, 2011, 2024, 2025])
        XCTAssertEqual(activity.years.map(\.listenCount), [9, 7, 3, 0])
        XCTAssertEqual(activity.decades.map(\.year), [1990, 2000, 2010, 2020])
        XCTAssertEqual(activity.decades.map(\.listenCount), [9, 0, 7, 3])
        XCTAssertEqual(activity.leadingDecade?.year, 1990)
        XCTAssertEqual(activity.years(in: 1990).map(\.year), Array(1990 ... 1999))
        XCTAssertEqual(activity.years(in: 1990).first(where: { $0.year == 1997 })?.listenCount, 9)
        XCTAssertEqual(activity.totalListens, 19)
    }

    func testEraActivityRejectsUnboundedYearsAndBoundsSparseGapFilling() {
        let activity = EraActivity(
            period: .allTime,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            years: [
                .init(year: Int.min, listenCount: 1),
                .init(year: 0, listenCount: 2),
                .init(year: 1000, listenCount: 3),
                .init(year: 2024, listenCount: 4),
                .init(year: 9999, listenCount: 5),
                .init(year: Int.max, listenCount: 6),
            ]
        )

        XCTAssertEqual(activity.years.map(\.year), [1000, 2024, 9999])
        XCTAssertEqual(activity.decades.map(\.year), [1000, 2020, 9990])
        XCTAssertEqual(activity.decades.map(\.listenCount), [3, 4, 5])
        XCTAssertTrue(activity.years(in: Int.min).isEmpty)
        XCTAssertTrue(activity.years(in: Int.max).isEmpty)
    }

    func testEraActivityCachesOneFreshRequestPerNormalizedUserAndPeriod() async {
        let cache = EntityDetailCache<EraActivityCacheKey, EraActivity>()
        let provider = EraActivityProvider(result: .activity(year: 1997, listenCount: 4))
        let first = ListeningModel(
            account: Account(username: " Listener ", token: ""),
            provider: provider,
            eraActivityCache: cache
        )

        await first.loadEraActivity(for: .thisYear)
        await first.loadEraActivity(for: .thisYear)
        let firstRequestCount = await provider.requestCount()
        XCTAssertEqual(firstRequestCount, 1)

        let sameUser = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            eraActivityCache: cache
        )
        await sameUser.loadEraActivity(for: .thisYear)
        let sameUserRequestCount = await provider.requestCount()
        XCTAssertEqual(sameUserRequestCount, 1)

        let otherUser = ListeningModel(
            account: Account(username: "someone-else", token: ""),
            provider: provider,
            eraActivityCache: cache
        )
        await otherUser.loadEraActivity(for: .thisYear)
        await otherUser.loadEraActivity(for: .allTime)
        let isolatedRequestCount = await provider.requestCount()
        XCTAssertEqual(isolatedRequestCount, 3)
    }

    func testStaleEraActivityStaysVisibleDuringRefreshAndOnFailure() async throws {
        let cache = EntityDetailCache<EraActivityCacheKey, EraActivity>(timeToLive: -1)
        let stale = EraActivity.fixture(period: .thisYear, year: 1997, listenCount: 3)
        await cache.save(
            stale,
            for: .init(username: "listener", scope: .authenticated(token: ""), period: .thisYear)
        )
        let provider = EraActivityProvider(result: .failure, delay: .seconds(1))
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            eraActivityCache: cache
        )

        let task = Task { await model.loadEraActivity(for: .thisYear) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        guard case let .loaded(visible) = model.eraActivityState(for: .thisYear) else {
            return XCTFail("Stale era data should remain visible while refreshing")
        }
        XCTAssertEqual(visible.totalListens, stale.totalListens)

        await task.value
        guard case let .loaded(retained) = model.eraActivityState(for: .thisYear) else {
            return XCTFail("A refresh failure must not discard stale era data")
        }
        XCTAssertEqual(retained.totalListens, stale.totalListens)
        XCTAssertNotNil(model.eraActivityRefreshMessage(for: .thisYear))
    }

    func testEraActivityNilAndEmptyResponsesAreHonest() async {
        let unavailableProvider = EraActivityProvider(result: .noContent)
        let unavailableModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: unavailableProvider,
            eraActivityCache: EntityDetailCache()
        )
        await unavailableModel.loadEraActivity(for: .thisYear)
        XCTAssertEqual(unavailableModel.eraActivityState(for: .thisYear), .unavailable)

        let emptyProvider = EraActivityProvider(result: .activity(year: 2025, listenCount: 0))
        let emptyModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: emptyProvider,
            eraActivityCache: EntityDetailCache()
        )
        await emptyModel.loadEraActivity(for: .thisYear)
        guard case let .loaded(activity) = emptyModel.eraActivityState(for: .thisYear) else {
            return XCTFail("Expected a loaded zero-count release year")
        }
        XCTAssertTrue(activity.isEmpty)
    }

    func testCancellingEraActivityLoadReturnsToIdle() async throws {
        let provider = EraActivityProvider(
            result: .activity(year: 2024, listenCount: 3),
            delay: .seconds(1)
        )
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            eraActivityCache: EntityDetailCache()
        )

        let task = Task { await model.loadEraActivity(for: .thisYear) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        task.cancel()
        await task.value

        XCTAssertEqual(model.eraActivityState(for: .thisYear), .idle)
    }

    func testArtistEvolutionNormalizesSparseUnorderedRowsByStableArtistIdentity() {
        let artistMBID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let activity = ArtistEvolutionActivity(
            period: .thisWeek,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [
                .init(timeUnit: "Tuesday", artistMBID: nil, artistName: "Second Artist", listenCount: 4),
                .init(timeUnit: "monday", artistMBID: artistMBID, artistName: "First Artist", listenCount: 3),
                .init(timeUnit: " Monday ", artistMBID: nil, artistName: "First Artist", listenCount: 5),
                .init(timeUnit: "Tuesday", artistMBID: artistMBID, artistName: "First Artist", listenCount: -9),
                .init(timeUnit: "Monday", artistMBID: artistMBID, artistName: "First Artist", listenCount: Int.max),
                .init(timeUnit: "not-a-day", artistMBID: nil, artistName: "Ignored", listenCount: 100),
            ]
        )

        XCTAssertEqual(activity.timeUnits, ListeningWeekday.allCases.map(\.rawValue))
        XCTAssertEqual(activity.artists.map(\.name), ["First Artist", "Second Artist"])
        XCTAssertEqual(activity.artists.first?.mbid, artistMBID)
        XCTAssertEqual(activity.artists.first?.listenCount, Int.max)
        XCTAssertEqual(activity.artists.first?.listenCount(at: "Tuesday"), 0)
        XCTAssertEqual(activity.artists.last?.listenCount(at: "Monday"), 0)
        XCTAssertEqual(activity.artists.last?.listenCount(at: "Tuesday"), 4)
        XCTAssertEqual(activity.totalListens, Int.max)
    }

    func testArtistEvolutionBoundsAllTimeYearsAndSparseGapFilling() {
        let activity = ArtistEvolutionActivity(
            period: .allTime,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [
                .init(timeUnit: String(Int.min), artistMBID: nil, artistName: "Artist", listenCount: 1),
                .init(timeUnit: "0", artistMBID: nil, artistName: "Artist", listenCount: 2),
                .init(timeUnit: "1000", artistMBID: nil, artistName: "Artist", listenCount: 3),
                .init(timeUnit: "2024", artistMBID: nil, artistName: "Artist", listenCount: 4),
                .init(timeUnit: "9999", artistMBID: nil, artistName: "Artist", listenCount: 5),
                .init(timeUnit: String(Int.max), artistMBID: nil, artistName: "Artist", listenCount: 6),
            ]
        )

        XCTAssertEqual(activity.timeUnits, ["1000", "2024", "9999"])
        XCTAssertEqual(activity.artists.first?.points.map(\.listenCount), [3, 4, 5])
        XCTAssertEqual(activity.totalListens, 12)
    }

    func testArtistEvolutionUsesListenBrainzEnglishMonthProtocolValues() {
        let activity = ArtistEvolutionActivity(
            period: .thisYear,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [
                .init(timeUnit: "january", artistMBID: nil, artistName: "Artist", listenCount: 3),
                .init(timeUnit: " December ", artistMBID: nil, artistName: "Artist", listenCount: 7),
                .init(timeUnit: "M01", artistMBID: nil, artistName: "Ignored", listenCount: 99),
            ]
        )

        XCTAssertEqual(activity.timeUnits, ArtistEvolutionActivity.monthNames)
        XCTAssertEqual(activity.artists.first?.listenCount(at: "January"), 3)
        XCTAssertEqual(activity.artists.first?.listenCount(at: "December"), 7)
        XCTAssertEqual(activity.totalListens, 10)
    }

    func testArtistEvolutionKeepsSameNameArtistsWithDistinctMBIDsSeparate() {
        let firstMBID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondMBID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let activity = ArtistEvolutionActivity(
            period: .thisWeek,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [
                .init(timeUnit: "Monday", artistMBID: firstMBID, artistName: "Shared Name", listenCount: 3),
                .init(timeUnit: "Tuesday", artistMBID: secondMBID, artistName: "Shared Name", listenCount: 7),
            ]
        )

        XCTAssertEqual(activity.artists.count, 2)
        XCTAssertEqual(Set(activity.artists.map(\.id)).count, 2)
        XCTAssertEqual(Set(activity.artists.compactMap(\.mbid)), Set([firstMBID, secondMBID]))
        XCTAssertEqual(activity.artists.map(\.listenCount), [7, 3])
    }

    func testArtistEvolutionCachesOneFreshRequestPerNormalizedUserAndPeriod() async {
        let cache = EntityDetailCache<ArtistEvolutionActivityCacheKey, ArtistEvolutionActivity>()
        let provider = ArtistEvolutionProvider(result: .activity(listenCount: 4))
        let first = ListeningModel(
            account: Account(username: " Listener ", token: ""),
            provider: provider,
            artistEvolutionActivityCache: cache
        )

        await first.loadArtistEvolution(for: .thisYear)
        await first.loadArtistEvolution(for: .thisYear)
        let firstRequestCount = await provider.requestCount()
        XCTAssertEqual(firstRequestCount, 1)

        let sameUser = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            artistEvolutionActivityCache: cache
        )
        await sameUser.loadArtistEvolution(for: .thisYear)
        let sameUserRequestCount = await provider.requestCount()
        XCTAssertEqual(sameUserRequestCount, 1)

        let otherUser = ListeningModel(
            account: Account(username: "someone-else", token: ""),
            provider: provider,
            artistEvolutionActivityCache: cache
        )
        await otherUser.loadArtistEvolution(for: .thisYear)
        await otherUser.loadArtistEvolution(for: .allTime)
        let isolatedRequestCount = await provider.requestCount()
        XCTAssertEqual(isolatedRequestCount, 3)
    }

    func testStaleArtistEvolutionStaysVisibleDuringRefreshAndOnFailure() async throws {
        let cache = EntityDetailCache<ArtistEvolutionActivityCacheKey, ArtistEvolutionActivity>(timeToLive: -1)
        let stale = ArtistEvolutionActivity.fixture(period: .thisYear, listenCount: 3)
        await cache.save(
            stale,
            for: .init(username: "listener", scope: .authenticated(token: ""), period: .thisYear)
        )
        let provider = ArtistEvolutionProvider(result: .failure, delay: .seconds(1))
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            artistEvolutionActivityCache: cache
        )

        let task = Task { await model.loadArtistEvolution(for: .thisYear) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        guard case let .loaded(visible) = model.artistEvolutionState(for: .thisYear) else {
            return XCTFail("Stale artist evolution should remain visible while refreshing")
        }
        XCTAssertEqual(visible.totalListens, stale.totalListens)

        await task.value
        guard case let .loaded(retained) = model.artistEvolutionState(for: .thisYear) else {
            return XCTFail("A refresh failure must not discard stale artist evolution")
        }
        XCTAssertEqual(retained.totalListens, stale.totalListens)
        XCTAssertNotNil(model.artistEvolutionRefreshMessage(for: .thisYear))
    }

    func testArtistEvolutionReplacementCannotBeOverwrittenByOlderRequest() async throws {
        let provider = ArtistEvolutionProvider(
            results: [.activity(listenCount: 1), .activity(listenCount: 9)],
            delays: [.milliseconds(80), .zero],
            ignoresCancellation: true
        )
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            artistEvolutionActivityCache: EntityDetailCache()
        )

        let first = Task { await model.loadArtistEvolution(for: .thisWeek) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        let replacement = Task { await model.loadArtistEvolution(for: .thisWeek, retrying: true) }
        await replacement.value
        first.cancel()
        await first.value

        guard case let .loaded(activity) = model.artistEvolutionState(for: .thisWeek) else {
            return XCTFail("Expected the replacement artist evolution response")
        }
        XCTAssertEqual(activity.totalListens, 9)
    }

    func testArtistEvolutionNilEmptyAndCancellationStatesAreHonest() async throws {
        let unavailableModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: ArtistEvolutionProvider(result: .noContent),
            artistEvolutionActivityCache: EntityDetailCache()
        )
        await unavailableModel.loadArtistEvolution(for: .thisMonth)
        XCTAssertEqual(unavailableModel.artistEvolutionState(for: .thisMonth), .unavailable)

        let emptyModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: ArtistEvolutionProvider(result: .activity(listenCount: 0)),
            artistEvolutionActivityCache: EntityDetailCache()
        )
        await emptyModel.loadArtistEvolution(for: .thisMonth)
        guard case let .loaded(empty) = emptyModel.artistEvolutionState(for: .thisMonth) else {
            return XCTFail("Expected a loaded zero-count artist evolution response")
        }
        XCTAssertTrue(empty.isEmpty)

        let delayedProvider = ArtistEvolutionProvider(result: .activity(listenCount: 3), delay: .seconds(1))
        let cancelledModel = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: delayedProvider,
            artistEvolutionActivityCache: EntityDetailCache()
        )
        let task = Task { await cancelledModel.loadArtistEvolution(for: .thisWeek) }
        while await delayedProvider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        task.cancel()
        await task.value
        XCTAssertEqual(cancelledModel.artistEvolutionState(for: .thisWeek), .idle)
    }

    func testGenreActivityNormalizesWhitespaceAndCaseWithoutInventingGenreIdentity() {
        let activity = GenreActivity(
            period: .thisWeek,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [
                .init(genre: "  Electronic  ", hour: 1, listenCount: 2),
                .init(genre: "electronic", hour: 1, listenCount: 3),
                .init(genre: "ELECTRONIC", hour: 22, listenCount: Int.max),
                .init(genre: "Hip   Hop", hour: 0, listenCount: 4),
                .init(genre: "hip hop", hour: 24, listenCount: 99),
                .init(genre: " ", hour: 3, listenCount: 99),
                .init(genre: "Ignored", hour: -1, listenCount: 99),
                .init(genre: "Ignored", hour: 4, listenCount: -8),
            ]
        )

        XCTAssertEqual(activity.genres.map(\.name), ["ELECTRONIC", "Hip Hop", "Ignored"])
        XCTAssertEqual(activity.genres.map(\.totalListenCount), [Int.max, 4, 0])
        XCTAssertEqual(activity.leadingGenre?.listenCount(atUTCHour: 1), 5)
        XCTAssertEqual(activity.leadingGenre?.listenCount(atUTCHour: 22), Int.max)
        XCTAssertEqual(activity.leadingGenre?.listenCount(atUTCHour: 24), 0)
        XCTAssertEqual(activity.totalListenCount, Int.max)
    }

    func testGenreActivityCachesOneFreshRequestPerNormalizedUserAndPeriod() async {
        let cache = EntityDetailCache<GenreActivityCacheKey, GenreActivity>()
        let provider = GenreActivityProvider(result: .activity(listenCount: 4))
        let first = ListeningModel(
            account: Account(username: " Listener ", token: ""),
            provider: provider,
            genreActivityCache: cache
        )

        await first.loadGenreActivity(for: .thisWeek)
        await first.loadGenreActivity(for: .thisWeek)
        let initialRequestCount = await provider.requestCount()
        XCTAssertEqual(initialRequestCount, 1)

        let sameUser = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            genreActivityCache: cache
        )
        await sameUser.loadGenreActivity(for: .thisWeek)
        let sameUserRequestCount = await provider.requestCount()
        XCTAssertEqual(sameUserRequestCount, 1)

        let isolated = ListeningModel(
            account: Account(username: "someone-else", token: ""),
            provider: provider,
            genreActivityCache: cache
        )
        await isolated.loadGenreActivity(for: .thisWeek)
        await isolated.loadGenreActivity(for: .allTime)
        let isolatedRequestCount = await provider.requestCount()
        XCTAssertEqual(isolatedRequestCount, 3)
    }

    func testStaleGenreActivityStaysVisibleDuringRefreshFailure() async throws {
        let cache = EntityDetailCache<GenreActivityCacheKey, GenreActivity>(timeToLive: -1)
        let stale = GenreActivity.fixture(period: .thisYear, listenCount: 3)
        await cache.save(
            stale,
            for: .init(username: "listener", scope: .authenticated(token: ""), period: .thisYear)
        )
        let provider = GenreActivityProvider(result: .failure, delay: .seconds(1))
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            genreActivityCache: cache
        )

        let task = Task { await model.loadGenreActivity(for: .thisYear) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        guard case let .loaded(visible) = model.genreActivityState(for: .thisYear) else {
            return XCTFail("Stale genre activity should remain visible while refreshing")
        }
        XCTAssertEqual(visible.totalListenCount, stale.totalListenCount)

        await task.value
        guard case let .loaded(retained) = model.genreActivityState(for: .thisYear) else {
            return XCTFail("A refresh failure must not discard stale genre activity")
        }
        XCTAssertEqual(retained.totalListenCount, stale.totalListenCount)
        XCTAssertNotNil(model.genreActivityRefreshMessage(for: .thisYear))
    }

    func testGenreActivityReplacementCannotBeOverwrittenByOlderRequest() async throws {
        let provider = GenreActivityProvider(
            results: [.activity(listenCount: 1), .activity(listenCount: 9)],
            delays: [.milliseconds(80), .zero],
            ignoresCancellation: true
        )
        let model = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: provider,
            genreActivityCache: EntityDetailCache()
        )

        let first = Task { await model.loadGenreActivity(for: .thisWeek) }
        while await provider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        let replacement = Task { await model.loadGenreActivity(for: .thisWeek, retrying: true) }
        await replacement.value
        first.cancel()
        await first.value

        guard case let .loaded(activity) = model.genreActivityState(for: .thisWeek) else {
            return XCTFail("Expected replacement genre activity response")
        }
        XCTAssertEqual(activity.totalListenCount, 9)
    }

    func testGenreActivityNilEmptyAndCancellationStatesAreHonest() async throws {
        let unavailable = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: GenreActivityProvider(result: .noContent),
            genreActivityCache: EntityDetailCache()
        )
        await unavailable.loadGenreActivity(for: .thisMonth)
        XCTAssertEqual(unavailable.genreActivityState(for: .thisMonth), .unavailable)

        let empty = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: GenreActivityProvider(result: .activity(listenCount: 0)),
            genreActivityCache: EntityDetailCache()
        )
        await empty.loadGenreActivity(for: .thisMonth)
        guard case let .loaded(activity) = empty.genreActivityState(for: .thisMonth) else {
            return XCTFail("Expected a loaded zero-count genre aggregate")
        }
        XCTAssertTrue(activity.isEmpty)

        let delayedProvider = GenreActivityProvider(result: .activity(listenCount: 3), delay: .seconds(1))
        let cancelled = ListeningModel(
            account: Account(username: "listener", token: ""),
            provider: delayedProvider,
            genreActivityCache: EntityDetailCache()
        )
        let task = Task { await cancelled.loadGenreActivity(for: .thisWeek) }
        while await delayedProvider.requestCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        task.cancel()
        await task.value
        XCTAssertEqual(cancelled.genreActivityState(for: .thisWeek), .idle)
    }

    func testFreshReleasesKeepPersonalizedAndSitewideRequestsSeparate() async {
        let provider = FixtureProvider()
        let model = FreshReleasesModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )

        await model.load(scope: .forYou)
        guard case let .loaded(personalized) = model.state(for: .forYou) else {
            return XCTFail("Expected personalized releases")
        }
        XCTAssertTrue(personalized.isEmpty)
        let personalizedRequests = await provider.freshReleaseRequestCount(for: .forYou)
        let sitewideRequestsBeforeSelection = await provider.freshReleaseRequestCount(for: .all)
        XCTAssertEqual(personalizedRequests, 1)
        XCTAssertEqual(sitewideRequestsBeforeSelection, 0)

        await model.load(scope: .all)
        guard case let .loaded(sitewide) = model.state(for: .all) else {
            return XCTFail("Expected sitewide releases")
        }
        XCTAssertEqual(sitewide.count, 1)
        let sitewideRequests = await provider.freshReleaseRequestCount(for: .all)
        XCTAssertEqual(sitewideRequests, 1)
    }

    func testReplacementFreshReleaseLoadSurvivesOlderCancellation() async throws {
        let provider = FixtureProvider(freshReleaseDelay: .milliseconds(80))
        let model = FreshReleasesModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let first = Task { await model.load(scope: .forYou) }
        let clock = ContinuousClock()
        while await provider.freshReleaseRequestCount(for: .forYou) < 1 {
            try await clock.sleep(for: .milliseconds(1))
        }

        let replacement = Task { await model.load(scope: .forYou) }
        first.cancel()

        await first.value
        await replacement.value

        guard case .loaded = model.state(for: .forYou) else {
            return XCTFail("Expected the model-owned Fresh Releases request to remain loaded")
        }
        let requestCount = await provider.freshReleaseRequestCount(for: .forYou)
        XCTAssertEqual(requestCount, 1)
    }

    func testFreshReleaseRefreshCoalescesWhileLoading() async throws {
        let provider = FixtureProvider(freshReleaseDelay: .milliseconds(80))
        let model = FreshReleasesModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let load = Task { await model.load(scope: .all) }
        let clock = ContinuousClock()
        while await provider.freshReleaseRequestCount(for: .all) < 1 {
            try await clock.sleep(for: .milliseconds(1))
        }

        await model.refresh(scope: .all)

        let requestCount = await provider.freshReleaseRequestCount(for: .all)
        XCTAssertEqual(requestCount, 1)
        await load.value
    }

    func testFreshReleaseQueryNormalizesEquivalentServerShapes() {
        let normalized = FreshReleaseQuery(
            scope: .all,
            days: .ninety,
            includesPast: false,
            includesUpcoming: false,
            sort: .confidence
        )
        let explicit = FreshReleaseQuery(
            scope: .all,
            days: .thirty,
            includesPast: true,
            includesUpcoming: true,
            sort: .releaseDate
        )

        XCTAssertEqual(normalized, explicit)
        XCTAssertEqual(normalized.days, .thirty)
        XCTAssertEqual(normalized.sort, .releaseDate)
        XCTAssertTrue(normalized.includesPast)
        XCTAssertTrue(normalized.includesUpcoming)
    }

    func testFreshReleaseModelKeysExactNormalizedQueriesAndForwardsThem() async {
        let provider = FixtureProvider()
        let model = FreshReleasesModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let rawSitewide = FreshReleaseQuery(scope: .all, days: .ninety, sort: .confidence)
        let equivalentSitewide = FreshReleaseQuery(scope: .all, days: .thirty, sort: .releaseDate)
        let personalized = FreshReleaseQuery(scope: .forYou, days: .ninety, sort: .confidence)

        await model.load(query: rawSitewide)
        await model.load(query: equivalentSitewide)
        await model.load(query: personalized)

        let sitewideRequests = await provider.freshReleaseRequestCount(for: equivalentSitewide)
        let personalizedRequests = await provider.freshReleaseRequestCount(for: personalized)
        let totalRequests = await provider.freshReleaseRequestCount()
        XCTAssertEqual(sitewideRequests, 1)
        XCTAssertEqual(personalizedRequests, 1)
        XCTAssertEqual(totalRequests, 2)
        XCTAssertEqual(model.state(for: rawSitewide), model.state(for: equivalentSitewide))
        XCTAssertNotEqual(model.state(for: rawSitewide), model.state(for: personalized))
    }

    func testFreshReleaseDateKeepsCalendarDayWestOfUTC() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Edmonton"))
        let release = FreshRelease(
            releaseMBID: FixtureProvider.releaseMBID,
            releaseGroupMBID: nil,
            title: "Dated Fixture",
            artistName: "Fixture Artist",
            artistMBIDs: [FixtureProvider.artistMBID],
            releaseDate: "2026-9-7",
            primaryType: "Album",
            secondaryType: nil,
            tags: [],
            confidence: nil,
            listenCount: nil,
            artworkReleaseMBID: FixtureProvider.releaseMBID,
            sourcePosition: 0
        )

        let date = try XCTUnwrap(release.releaseDateValue(in: timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 7)
    }

    func testFreshReleaseIdentityDistinguishesDuplicateUnmappedRows() {
        func release(at sourcePosition: Int) -> FreshRelease {
            FreshRelease(
                releaseMBID: nil,
                releaseGroupMBID: nil,
                title: "Same title",
                artistName: "Same artist",
                artistMBIDs: [],
                releaseDate: "2026-9-7",
                primaryType: nil,
                secondaryType: nil,
                tags: [],
                confidence: nil,
                listenCount: nil,
                artworkReleaseMBID: nil,
                sourcePosition: sourcePosition
            )
        }

        XCTAssertNotEqual(release(at: 0).id, release(at: 1).id)
    }

    func testFreshReleasesArePresentedNewestFirst() {
        func release(date: String?, sourcePosition: Int) -> FreshRelease {
            FreshRelease(
                releaseMBID: nil,
                releaseGroupMBID: nil,
                title: date ?? "Unknown date",
                artistName: "Fixture Artist",
                artistMBIDs: [],
                releaseDate: date,
                primaryType: nil,
                secondaryType: nil,
                tags: [],
                confidence: nil,
                listenCount: nil,
                artworkReleaseMBID: nil,
                sourcePosition: sourcePosition
            )
        }
        let releases = [
            release(date: "2026-09-10", sourcePosition: 0),
            release(date: nil, sourcePosition: 1),
            release(date: "2026-09-20", sourcePosition: 2),
        ]

        let sorted = releases.sorted(by: ListenBrainzProvider.freshReleaseComesFirst)

        XCTAssertEqual(sorted.map(\.releaseDate), ["2026-09-20", "2026-09-10", nil])
    }

    func testFreshReleaseLocalFiltersMatchTypeAndTagsWithoutAnotherRead() async {
        let provider = FixtureProvider()
        let model = FreshReleasesModel(
            account: Account(username: "fixture-\(UUID().uuidString)", token: ""),
            provider: provider
        )
        let query = FreshReleaseQuery(scope: .all)
        await model.load(query: query)
        guard case let .loaded(loadedReleases) = model.state(for: query) else {
            return XCTFail("Expected loaded Fresh Releases fixtures")
        }
        let liveAlbum = FreshRelease(
            releaseMBID: nil,
            releaseGroupMBID: nil,
            title: "Live Fixture",
            artistName: "Fixture Artist",
            artistMBIDs: [],
            releaseDate: "2026-9-8",
            primaryType: "Album",
            secondaryType: "Live",
            tags: ["fixture", "live"],
            confidence: 0.5,
            listenCount: nil,
            artworkReleaseMBID: nil,
            sourcePosition: 1
        )
        let releases = loadedReleases + [liveAlbum]
        let readsBeforeFiltering = await provider.freshReleaseRequestCount()

        var filters = FreshReleaseFilters()
        let serverQueryBeforeLocalChanges = filters.query(for: .all)
        filters.releaseTypes = [" album "]
        filters.includedTags = ["FÍXTURE"]
        filters.excludedTags = ["live"]
        filters.direction = .ascending
        let visible = filters.filtered(releases, using: .releaseDate)

        XCTAssertEqual(visible.map(\.title), ["Fresh Fixture"])
        XCTAssertEqual(filters.query(for: .all), serverQueryBeforeLocalChanges)
        filters.excludedTags = []
        XCTAssertEqual(Set(filters.filtered(releases, using: .releaseDate).map(\.title)), ["Fresh Fixture", "Live Fixture"])
        XCTAssertEqual(FreshReleaseFilters.availableTypes(in: releases), ["Album", "Live"])
        let readsAfterFiltering = await provider.freshReleaseRequestCount()
        XCTAssertEqual(readsAfterFiltering, readsBeforeFiltering)
    }

    func testFreshReleaseLocalSortDirectionKeepsMissingValuesLast() {
        func release(
            title: String,
            artist: String,
            date: String?,
            confidence: Double?,
            sourcePosition: Int
        ) -> FreshRelease {
            FreshRelease(
                releaseMBID: nil,
                releaseGroupMBID: nil,
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseDate: date,
                primaryType: "Album",
                secondaryType: nil,
                tags: [],
                confidence: confidence,
                listenCount: nil,
                artworkReleaseMBID: nil,
                sourcePosition: sourcePosition
            )
        }
        let releases = [
            release(title: "Beta", artist: "Zulu", date: "2026-09-10", confidence: 0.4, sourcePosition: 0),
            release(title: "Alpha", artist: "Alpha", date: nil, confidence: nil, sourcePosition: 1),
            release(title: "Gamma", artist: "Mike", date: "2026-09-20", confidence: 0.9, sourcePosition: 2),
        ]

        var filters = FreshReleaseFilters()
        filters.direction = .ascending
        XCTAssertEqual(
            filters.filtered(releases, using: .releaseDate).map(\.title),
            ["Beta", "Gamma", "Alpha"]
        )
        filters.direction = .descending
        XCTAssertEqual(
            filters.filtered(releases, using: .confidence).map(\.title),
            ["Gamma", "Beta", "Alpha"]
        )
        filters.direction = .ascending
        XCTAssertEqual(
            filters.filtered(releases, using: .artistCreditName).map(\.artistName),
            ["Alpha", "Mike", "Zulu"]
        )
        XCTAssertEqual(
            filters.filtered(releases, using: .releaseName).map(\.title),
            ["Alpha", "Beta", "Gamma"]
        )
    }

    func testSearchTrimsCachesPerScopeAndAvoidsEmptyRequests() async {
        let provider = SearchFixtureProvider()
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider
        )

        await model.searchImmediatelyForTesting()
        let emptyRequestCount = await provider.requestCount()
        XCTAssertEqual(emptyRequestCount, 0)

        model.update(query: "  Björk  ")
        await model.searchImmediatelyForTesting()
        XCTAssertEqual(model.results.first?.title, "Björk")
        let firstQueries = await provider.queries()
        XCTAssertEqual(firstQueries, ["Björk"])

        model.update(query: "BJÖRK")
        await model.searchImmediatelyForTesting()
        let cachedRequestCount = await provider.requestCount()
        XCTAssertEqual(cachedRequestCount, 1)

        model.update(scope: .recordings)
        await model.searchImmediatelyForTesting()
        let scopedRequestCount = await provider.requestCount()
        XCTAssertEqual(scopedRequestCount, 2)
    }

    func testInitialSearchConfigurationStartsOnlyOnce() async throws {
        let provider = SearchFixtureProvider()
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider,
            debounceDuration: .milliseconds(1),
            initialQuery: "listener",
            initialScope: .users
        )

        model.startInitialSearchIfNeeded()
        model.startInitialSearchIfNeeded()
        try await ContinuousClock().sleep(for: .milliseconds(20))

        XCTAssertEqual(model.scope, .users)
        XCTAssertEqual(model.state, .loaded)
        let requestCount = await provider.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testPlaylistSearchRequiresThreeCharactersBeforeCallingProvider() async {
        let provider = SearchFixtureProvider()
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider
        )
        model.update(scope: .playlists)
        model.update(query: "ab")

        await model.searchImmediatelyForTesting()

        XCTAssertEqual(model.state, .idle)
        let requestCount = await provider.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testSupersededSearchCannotOverwriteNewerResults() async throws {
        let provider = SearchFixtureProvider(delay: .milliseconds(40))
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider
        )
        model.update(query: "older")
        let older = Task { await model.searchImmediatelyForTesting() }
        try await ContinuousClock().sleep(for: .milliseconds(5))
        model.update(query: "newer")
        await model.searchImmediatelyForTesting()
        await older.value

        XCTAssertEqual(model.results.first?.title, "newer")
    }

    func testMusicBrainzSearchUsesLiteralQueryAndClampedLimit() throws {
        let request = try MusicBrainzSearchClient.makeRequest(
            query: "A/B + C && D || E",
            scope: .artists,
            limit: 999,
            userAgent: "Brainz test"
        )
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["query"], "\"A\\/B \\+ C \\&\\& D \\|\\| E\"")
        XCTAssertEqual(values["limit"], "25")
        XCTAssertEqual(values["fmt"], "json")
        XCTAssertTrue(components.path.hasSuffix("/artist/"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Brainz test")
    }

    func testMusicBrainzSearchNeutralizesLuceneWordOperators() {
        XCTAssertEqual(
            MusicBrainzSearchClient.escapeLuceneLiteral("Björk OR Prince NOT remix"),
            "\"Björk OR Prince NOT remix\""
        )
    }

    func testMusicBrainzRetryAfterSupportsHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://musicbrainz.org")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": formatter.string(from: now.addingTimeInterval(12))]
        ))

        XCTAssertEqual(MusicBrainzSearchClient.retryAfter(response, now: now), 12)
    }

    func testMusicBrainzRecordingDecodeToleratesSparseMetadataAndKeepsCreditJoinPhrases() throws {
        let data = Data(#"""
        {
          "recordings": [{
            "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "title": "A sparse recording",
            "artist-credit": [
              {"name": "One", "joinphrase": " feat. ", "artist": {"id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "name": "One"}},
              {"name": "Two", "artist": {"id": "cccccccc-cccc-cccc-cccc-cccccccccccc", "name": "Two"}}
            ]
          }]
        }
        """#.utf8)

        let result = try XCTUnwrap(MusicBrainzSearchClient.decode(data: data, scope: .recordings).first)
        guard case let .recording(recording) = result else {
            return XCTFail("Expected a recording result")
        }
        XCTAssertEqual(recording.artistName, "One feat. Two")
        XCTAssertEqual(recording.releaseTitle, nil)
        XCTAssertEqual(recording.artistMBIDs.count, 2)
    }

    func testClosingSearchCancelsAnInFlightProviderRequest() async throws {
        let provider = SearchFixtureProvider(delay: .seconds(2))
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider,
            debounceDuration: .milliseconds(1)
        )
        model.update(query: "abandoned")
        try await ContinuousClock().sleep(for: .milliseconds(20))

        model.cancel()
        try await ContinuousClock().sleep(for: .milliseconds(20))

        XCTAssertEqual(model.state, .idle)
        let cancellationCount = await provider.cancellationCount()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testChangingQueryCancelsAnInFlightRetry() async throws {
        let provider = SearchFixtureProvider(delay: .seconds(2))
        let model = SearchModel(
            account: Account(username: "fixture", token: ""),
            provider: provider
        )
        model.update(query: "first")
        let retry = Task { await model.retry() }
        try await ContinuousClock().sleep(for: .milliseconds(20))

        model.update(query: "second")
        try await ContinuousClock().sleep(for: .milliseconds(20))
        model.cancel()
        await retry.value

        let queries = await provider.queries()
        let cancellationCount = await provider.cancellationCount()
        XCTAssertEqual(queries, ["first"])
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(model.state, .idle)
    }

    nonisolated func testRequestGateSpacesActualOperationStarts() async throws {
        let gate = RequestGate(minimumInterval: .milliseconds(40))
        let clock = ContinuousClock()
        let start = clock.now

        let elapsed = try await withThrowingTaskGroup(of: Duration.self) { group in
            for _ in 0 ..< 3 {
                group.addTask {
                    try await gate.perform {
                        start.duration(to: clock.now)
                    }
                }
            }
            var values: [Duration] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }
        let milliseconds = elapsed.map(Self.milliseconds).sorted()

        XCTAssertGreaterThanOrEqual(milliseconds[1] - milliseconds[0], 30)
        XCTAssertGreaterThanOrEqual(milliseconds[2] - milliseconds[1], 30)
    }

    nonisolated func testRequestGateHonorsServerDeferral() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let clock = ContinuousClock()
        await gate.deferRequests(for: .milliseconds(50))
        let start = clock.now

        let elapsed = try await gate.perform {
            start.duration(to: clock.now)
        }

        XCTAssertGreaterThanOrEqual(Self.milliseconds(elapsed), 40)
    }

    nonisolated func testAuthenticatedEmptyTokenScopeIsNotAnonymous() {
        XCTAssertNotEqual(
            RequestGate.ReadScope.authenticated(token: ""),
            .anonymous
        )
    }

    nonisolated func testIsolatedReadScopesDoNotMatch() {
        XCTAssertNotEqual(
            RequestGate.ReadScope.isolated(),
            RequestGate.ReadScope.isolated()
        )
    }

    nonisolated func testServerDeferralReschedulesAlreadyQueuedCallers() async throws {
        let gate = RequestGate(minimumInterval: .milliseconds(20))
        let clock = ContinuousClock()
        try await gate.perform {}
        let start = clock.now

        let first = Task {
            try await gate.perform {
                start.duration(to: clock.now)
            }
        }
        let second = Task {
            try await gate.perform {
                start.duration(to: clock.now)
            }
        }
        try await clock.sleep(for: .milliseconds(5))
        await gate.deferRequests(for: .milliseconds(70))

        let firstElapsed = try await first.value
        let secondElapsed = try await second.value
        let elapsed = [firstElapsed, secondElapsed].map(Self.milliseconds).sorted()
        XCTAssertGreaterThanOrEqual(elapsed[0], 60)
        XCTAssertGreaterThanOrEqual(elapsed[1] - elapsed[0], 15)
    }

    nonisolated func testRateLimitDeferralIsInstalledBeforeQueuedOperationStarts() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = GateProbe()
        let clock = ContinuousClock()

        let limited = Task {
            try await gate.perform({
                await probe.markStarted()
                try await clock.sleep(for: .milliseconds(10))
                throw GateTestError.rateLimited
            }, deferralForError: { error in
                error is GateTestError ? .milliseconds(60) : nil
            })
        }

        while !(await probe.hasStarted()) {
            try await clock.sleep(for: .milliseconds(1))
        }
        let queuedAt = clock.now
        let queued = Task {
            try await gate.perform {
                queuedAt.duration(to: clock.now)
            }
        }

        do {
            try await limited.value
            XCTFail("The first operation should surface its rate-limit error")
        } catch GateTestError.rateLimited {}

        let elapsed = try await queued.value
        XCTAssertGreaterThanOrEqual(Self.milliseconds(elapsed), 60)
    }

    nonisolated func testCancellingQueuedOperationTransfersOwnership() async throws {
        let gate = RequestGate(minimumInterval: .milliseconds(100))
        let probe = GateProbe()
        let clock = ContinuousClock()

        let active = Task {
            try await gate.perform {
                await probe.markStarted()
                try await clock.sleep(for: .milliseconds(40))
            }
        }
        while !(await probe.hasStarted()) {
            try await clock.sleep(for: .milliseconds(1))
        }

        let cancelled = Task {
            try await gate.perform { 2 }
        }
        let successor = Task {
            try await gate.perform { 3 }
        }
        while await gate.queuedRequestCountForTesting() < 2 {
            try await clock.sleep(for: .milliseconds(1))
        }

        try await active.value
        // Completion has transferred ownership to the first waiter. Cancelling
        // in that handoff window must still release the next queued caller.
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled queued operation should not start")
        } catch is CancellationError {}
        let successorValue = try await successor.value
        XCTAssertEqual(successorValue, 3)
    }

    nonisolated func testRequestAuditCountsMutationTransportsAndSkipsPreStartCancellation() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = ReadGateProbe()

        let active = Task {
            try await gate.perform {
                await probe.startAndWait()
                return 1
            }
        }
        try await waitForCondition { await probe.startedCount() == 1 }

        let cancelledBeforeStart = Task {
            try await gate.perform { 2 }
        }
        try await waitForCondition { await gate.queuedRequestCountForTesting() == 1 }
        cancelledBeforeStart.cancel()
        do {
            _ = try await cancelledBeforeStart.value
            XCTFail("A cancelled queued mutation must not start its transport")
        } catch is CancellationError {}

        var snapshot = await gate.requestAuditSnapshot()
        XCTAssertEqual(snapshot.mutations.started, 1)
        XCTAssertEqual(snapshot.mutations.cancelled, 0)
        XCTAssertEqual(snapshot.activeMutationTransports, 1)
        XCTAssertEqual(snapshot.maximumActiveMutationTransports, 1)

        await probe.releaseAll()
        let activeValue = try await active.value
        XCTAssertEqual(activeValue, 1)

        do {
            let _: Void = try await gate.perform {
                throw GateTestError.rateLimited
            }
            XCTFail("A failed transport should surface its error")
        } catch GateTestError.rateLimited {}

        snapshot = await gate.requestAuditSnapshot()
        XCTAssertEqual(snapshot.mutations.started, 2)
        XCTAssertEqual(snapshot.mutations.finished, 1)
        XCTAssertEqual(snapshot.mutations.failed, 1)
        XCTAssertEqual(snapshot.mutations.cancelled, 0)
        XCTAssertEqual(snapshot.activeMutationTransports, 0)
        XCTAssertEqual(snapshot.maximumActiveMutationTransports, 1)
    }

    nonisolated func testRequestAuditCountsInFlightMutationCancellation() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = GateProbe()
        let task = Task {
            try await gate.perform {
                await probe.markStarted()
                try await ContinuousClock().sleep(for: .seconds(1))
                return 1
            }
        }
        try await waitForCondition { await probe.hasStarted() }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled in-flight mutation should surface cancellation")
        } catch is CancellationError {}

        let snapshot = await gate.requestAuditSnapshot()
        XCTAssertEqual(snapshot.mutations.started, 1)
        XCTAssertEqual(snapshot.mutations.finished, 0)
        XCTAssertEqual(snapshot.mutations.failed, 0)
        XCTAssertEqual(snapshot.mutations.cancelled, 1)
        XCTAssertEqual(snapshot.activeMutationTransports, 0)
        XCTAssertEqual(snapshot.maximumActiveMutationTransports, 1)
    }

    nonisolated func testRequestGateRunsTwoIndependentReadsAndQueuesTheThird() async throws {
        let gate = RequestGate(minimumInterval: .zero, maximumConcurrentReads: 2)
        let probe = ReadGateProbe()
        let scope = RequestGate.ReadScope.authenticated(token: "fixture-account")

        let first = Task {
            try await gate.read(for: .init(scope: scope, feature: .historyRecent, identityComponents: ["first"])) {
                await probe.startAndWait()
                return 1
            }
        }
        let second = Task {
            try await gate.read(for: .init(scope: scope, feature: .historyRecent, identityComponents: ["second"])) {
                await probe.startAndWait()
                return 2
            }
        }
        let third = Task {
            try await gate.read(for: .init(scope: scope, feature: .historyRecent, identityComponents: ["third"])) {
                await probe.startAndWait()
                return 3
            }
        }

        try await waitForCondition { await probe.startedCount() >= 2 }
        let activeReads = await gate.activeReadCountForTesting()
        let queuedReads = await gate.queuedReadCountForTesting()
        XCTAssertEqual(activeReads, 2)
        XCTAssertEqual(queuedReads, 1)
        var audit = await gate.requestAuditSnapshot()
        var counts = try XCTUnwrap(
            audit.reads.first { $0.feature == .historyRecent }?.counts
        )
        XCTAssertEqual(counts.started, 2)
        XCTAssertEqual(audit.activeReadTransports, 2)
        XCTAssertEqual(audit.maximumActiveReadTransports, 2)

        await probe.releaseOne()
        try await waitForCondition { await probe.startedCount() >= 3 }
        await probe.releaseAll()
        let firstValue = try await first.value
        let secondValue = try await second.value
        let thirdValue = try await third.value
        XCTAssertEqual(firstValue, 1)
        XCTAssertEqual(secondValue, 2)
        XCTAssertEqual(thirdValue, 3)
        audit = await gate.requestAuditSnapshot()
        counts = try XCTUnwrap(
            audit.reads.first { $0.feature == .historyRecent }?.counts
        )
        XCTAssertEqual(counts.started, 3)
        XCTAssertEqual(counts.finished, 3)
        XCTAssertEqual(audit.activeReadTransports, 0)
        XCTAssertEqual(audit.maximumActiveReadTransports, 2)
    }

    nonisolated func testRequestGateCancelsQueuedReadWithoutStartingItsTransport() async throws {
        let gate = RequestGate(minimumInterval: .zero, maximumConcurrentReads: 1)
        let probe = ReadGateProbe()
        let scope = RequestGate.ReadScope.authenticated(token: "fixture-account")
        let active = Task {
            try await gate.read(
                for: .init(scope: scope, feature: .historyRecent, identityComponents: ["active"])
            ) {
                await probe.startAndWait()
                return 1
            }
        }
        try await waitForCondition { await probe.startedCount() == 1 }

        let queued = Task {
            try await gate.read(
                for: .init(scope: scope, feature: .historyRecent, identityComponents: ["queued"])
            ) {
                await probe.startAndWait()
                return 2
            }
        }
        try await waitForCondition { await gate.queuedReadCountForTesting() == 1 }

        queued.cancel()
        do {
            _ = try await queued.value
            XCTFail("A cancelled queued read must not start its transport")
        } catch is CancellationError {}
        try await waitForCondition { await gate.queuedReadCountForTesting() == 0 }
        let startsBeforeRelease = await probe.startedCount()
        XCTAssertEqual(startsBeforeRelease, 1)
        var audit = await gate.requestAuditSnapshot()
        var counts = try XCTUnwrap(
            audit.reads.first { $0.feature == .historyRecent }?.counts
        )
        XCTAssertEqual(counts.started, 1)
        XCTAssertEqual(counts.cancelled, 0)
        XCTAssertEqual(audit.activeReadTransports, 1)

        await probe.releaseAll()
        let activeValue = try await active.value
        XCTAssertEqual(activeValue, 1)
        audit = await gate.requestAuditSnapshot()
        counts = try XCTUnwrap(
            audit.reads.first { $0.feature == .historyRecent }?.counts
        )
        XCTAssertEqual(counts.finished, 1)
        XCTAssertEqual(counts.cancelled, 0)
        XCTAssertEqual(audit.activeReadTransports, 0)
    }

    nonisolated func testRequestAuditCountsReadFailure() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let key = RequestGate.ReadKey(
            scope: .anonymous,
            feature: .discoveryFreshReleases,
            identityComponents: ["private query"]
        )

        do {
            let _: Int = try await gate.read(for: key) {
                throw GateTestError.rateLimited
            }
            XCTFail("A failed read transport should surface its error")
        } catch GateTestError.rateLimited {}

        let audit = await gate.requestAuditSnapshot()
        let counts = try XCTUnwrap(
            audit.reads.first { $0.feature == .discoveryFreshReleases }?.counts
        )
        XCTAssertEqual(counts.started, 1)
        XCTAssertEqual(counts.finished, 0)
        XCTAssertEqual(counts.failed, 1)
        XCTAssertEqual(counts.cancelled, 0)
        XCTAssertEqual(audit.activeReadTransports, 0)
        XCTAssertEqual(audit.maximumActiveReadTransports, 1)
        XCTAssertFalse(String(describing: audit).contains("private query"))
    }

    nonisolated func testRequestGateCoalescesIdenticalReadsIntoOneTransport() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = ReadGateProbe()
        let key = RequestGate.ReadKey(scope: .authenticated(token: "fixture-account"), feature: .profileSummary, identityComponents: ["private identity"])

        let first = Task {
            try await gate.read(for: key) {
                await probe.startAndWait()
                return "loaded"
            }
        }
        try await waitForCondition { await probe.startedCount() >= 1 }
        let second = Task { try await gate.read(for: key) { "should not run" } }
        try await waitForCondition { await gate.readWaiterCountForTesting(key) == 2 }

        let startedCount = await probe.startedCount()
        XCTAssertEqual(startedCount, 1)
        let telemetry = await gate.readTelemetryForTesting()
        XCTAssertTrue(telemetry.contains { $0.feature == .profileSummary && $0.lifecycle == "coalesced" })
        XCTAssertFalse(telemetry.description.contains("private identity"))
        var audit = await gate.requestAuditSnapshot()
        var counts = try XCTUnwrap(
            audit.reads.first { $0.feature == .profileSummary }?.counts
        )
        XCTAssertEqual(counts.started, 1)
        XCTAssertEqual(counts.coalesced, 1)
        XCTAssertEqual(counts.finished, 0)
        XCTAssertEqual(audit.activeReadTransports, 1)
        XCTAssertEqual(audit.maximumActiveReadTransports, 1)
        XCTAssertFalse(String(describing: audit).contains("private identity"))

        await probe.releaseAll()
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, "loaded")
        XCTAssertEqual(secondValue, "loaded")
        audit = await gate.requestAuditSnapshot()
        counts = try XCTUnwrap(
            audit.reads.first { $0.feature == .profileSummary }?.counts
        )
        XCTAssertEqual(counts.finished, 1)
        XCTAssertEqual(audit.activeReadTransports, 0)
    }

    nonisolated func testRequestGateCancelsOnlyOneCoalescedReadWaiter() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = ReadGateProbe()
        let key = RequestGate.ReadKey(scope: .authenticated(token: "fixture-account"), feature: .profileSummary, identityComponents: ["same"])

        let first = Task {
            try await gate.read(for: key) {
                await probe.startAndWait()
                return 1
            }
        }
        try await waitForCondition { await probe.startedCount() >= 1 }
        let second = Task { try await gate.read(for: key) { 2 } }
        try await waitForCondition { await gate.readWaiterCountForTesting(key) == 2 }
        first.cancel()

        do {
            _ = try await first.value
            XCTFail("The cancelled waiter should not receive the shared result")
        } catch is CancellationError {}
        // The shared transport remains blocked: only this caller left.
        let startsBeforeRelease = await probe.startedCount()
        XCTAssertEqual(startsBeforeRelease, 1)
        await probe.releaseAll()
        let secondValue = try await second.value
        let starts = await probe.startedCount()
        XCTAssertEqual(secondValue, 1)
        XCTAssertEqual(starts, 1)
    }

    nonisolated func testRequestGateCancelsUnderlyingReadAfterFinalWaiterLeaves() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = ReadGateProbe()
        let scope = RequestGate.ReadScope.authenticated(token: "fixture-account")
        let task = Task {
            try await gate.read(for: .init(scope: scope, feature: .searchResults, identityComponents: ["query"])) {
                await probe.markStarted()
                do {
                    try await ContinuousClock().sleep(for: .seconds(1))
                } catch {
                    await probe.markCancelled()
                    throw error
                }
                return 1
            }
        }
        try await waitForCondition { await probe.startedCount() >= 1 }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("The final waiter cancellation should propagate")
        } catch is CancellationError {}
        try await waitForCondition { await probe.cancellationCount() >= 1 }
        try await waitForCondition { await gate.activeReadCountForTesting() == 0 }
        let activeReads = await gate.activeReadCountForTesting()
        XCTAssertEqual(activeReads, 0)
        let audit = await gate.requestAuditSnapshot()
        let counts = try XCTUnwrap(
            audit.reads.first { $0.feature == .searchResults }?.counts
        )
        XCTAssertEqual(counts.started, 1)
        XCTAssertEqual(counts.cancelled, 1)
        XCTAssertEqual(audit.activeReadTransports, 0)
    }

    nonisolated func testRequestGateDoesNotOverlapReplacementWhileCancelledReadDrains() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = ReadGateProbe()
        let key = RequestGate.ReadKey(scope: .authenticated(token: "fixture-account"), feature: .historyRecent, identityComponents: ["same"])
        let first = Task {
            try await gate.read(for: key) {
                await probe.startAndWait()
                return 1
            }
        }
        try await waitForCondition { await probe.startedCount() >= 1 }

        first.cancel()
        do {
            _ = try await first.value
            XCTFail("The cancelled original waiter should return immediately")
        } catch is CancellationError {}
        let isDraining = await gate.isReadDrainingForTesting(key)
        XCTAssertTrue(isDraining)

        let replacement = Task {
            try await gate.read(for: key) {
                await probe.startAndWait()
                return 2
            }
        }
        try await waitForCondition { await gate.drainingWaiterCountForTesting(key) == 1 }
        let startsBeforeRelease = await probe.startedCount()
        XCTAssertEqual(startsBeforeRelease, 1)

        replacement.cancel()
        do {
            _ = try await replacement.value
            XCTFail("A stale replacement must not wait for a draining transport")
        } catch is CancellationError {}
        try await waitForCondition { await gate.drainingWaiterCountForTesting(key) == 0 }
        let startsAfterReplacementCancellation = await probe.startedCount()
        XCTAssertEqual(startsAfterReplacementCancellation, 1)

        await probe.releaseOne()
        let final = Task {
            try await gate.read(for: key) {
                await probe.startAndWait()
                return 3
            }
        }
        try await waitForCondition { await probe.startedCount() >= 2 }
        await probe.releaseAll()
        let finalValue = try await final.value
        XCTAssertEqual(finalValue, 3)
    }

    nonisolated func testRequestGateDoesNotCoalesceAcrossAuthenticatedScopes() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = ReadGateProbe()
        let first = Task {
            try await gate.read(
                for: .init(
                    scope: .authenticated(token: "fixture-account-a"),
                    feature: .profileSummary,
                    identityComponents: ["same"]
                )
            ) {
                await probe.startAndWait()
                return 1
            }
        }
        let second = Task {
            try await gate.read(
                for: .init(
                    scope: .authenticated(token: "fixture-account-b"),
                    feature: .profileSummary,
                    identityComponents: ["same"]
                )
            ) {
                await probe.startAndWait()
                return 2
            }
        }
        try await waitForCondition { await probe.startedCount() >= 2 }
        await probe.releaseAll()
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, 1)
        XCTAssertEqual(secondValue, 2)
    }

    nonisolated func testRequestGateRejectsMismatchedResultTypesForAnExistingReadKey() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = ReadGateProbe()
        let key = RequestGate.ReadKey(
            scope: .authenticated(token: "fixture-account"),
            feature: .metadataRecording,
            identityComponents: ["same"]
        )
        let first = Task {
            try await gate.read(for: key) {
                await probe.startAndWait()
                return 1
            }
        }
        try await waitForCondition { await probe.startedCount() >= 1 }

        do {
            _ = try await gate.read(for: key) { "wrong type" }
            XCTFail("A matching key must not bridge different result types")
        } catch RequestGate.ReadError.incompatibleReadResultType {}
        await probe.releaseAll()
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, 1)
    }

    nonisolated func testReadRateLimitReschedulesAlreadyQueuedMutation() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let probe = ReadGateProbe()
        let clock = ContinuousClock()
        let activeMutation = Task {
            try await gate.perform { await probe.startAndWait() }
        }
        try await waitForCondition { await probe.startedCount() >= 1 }
        let queuedAt = clock.now
        let queuedMutation = Task {
            try await gate.perform { queuedAt.duration(to: clock.now) }
        }
        try await waitForCondition { await gate.queuedRequestCountForTesting() >= 1 }

        let scope = RequestGate.ReadScope.authenticated(token: "fixture-account")
        do {
            _ = try await gate.read(
                for: .init(scope: scope, feature: .historyRecent, identityComponents: ["limited"]),
                { () async throws -> Int in throw GateTestError.rateLimited },
                deferralForError: { error in
                    error is GateTestError ? .milliseconds(60) : nil
                }
            )
            XCTFail("The read should surface its rate-limit error")
        } catch GateTestError.rateLimited {}

        await probe.releaseAll()
        _ = try await activeMutation.value
        let elapsed = try await queuedMutation.value
        XCTAssertGreaterThanOrEqual(Self.milliseconds(elapsed), 50)
    }

    nonisolated func testReadRateLimitReschedulesAlreadyQueuedRead() async throws {
        let gate = RequestGate(minimumInterval: .zero, maximumConcurrentReads: 1)
        let probe = ReadGateProbe()
        let clock = ContinuousClock()
        let scope = RequestGate.ReadScope.authenticated(token: "fixture-account")
        let limited = Task {
            try await gate.read(
                for: .init(scope: scope, feature: .historyRecent, identityComponents: ["limited"]),
                {
                    await probe.startAndWait()
                    throw GateTestError.rateLimited
                },
                deferralForError: { error in
                    error is GateTestError ? .milliseconds(60) : nil
                }
            ) as Int
        }
        try await waitForCondition { await probe.startedCount() == 1 }

        let queuedAt = clock.now
        let queued = Task {
            try await gate.read(
                for: .init(scope: scope, feature: .historyRecent, identityComponents: ["queued"])
            ) {
                queuedAt.duration(to: clock.now)
            }
        }
        try await waitForCondition { await gate.queuedReadCountForTesting() == 1 }

        await probe.releaseAll()
        do {
            _ = try await limited.value
            XCTFail("The first read should surface its rate-limit error")
        } catch GateTestError.rateLimited {}
        let elapsed = try await queued.value
        XCTAssertGreaterThanOrEqual(Self.milliseconds(elapsed), 50)
    }

    nonisolated func testReadRateLimitDeferralDelaysFollowingMutation() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let clock = ContinuousClock()
        let scope = RequestGate.ReadScope.authenticated(token: "fixture-account")
        let limited = Task {
            try await gate.read(
                for: .init(scope: scope, feature: .historyRecent, identityComponents: ["limited"]),
                { throw GateTestError.rateLimited },
                deferralForError: { error in
                    error is GateTestError ? .milliseconds(60) : nil
                }
            ) as Int
        }
        do {
            _ = try await limited.value
            XCTFail("The read should surface its rate-limit error")
        } catch GateTestError.rateLimited {}

        let start = clock.now
        let elapsed = try await gate.perform { start.duration(to: clock.now) }
        XCTAssertGreaterThanOrEqual(Self.milliseconds(elapsed), 50)
    }

    func testLoadedHistorySearchMatchesCanonicalAndSubmittedMetadata() {
        let canonical = historySearchListen(
            title: "Midnight City",
            artist: "M83",
            release: "Hurry Up, We're Dreaming"
        )
        let submitted = historySearchListen(
            title: "Resolved title",
            artist: "Resolved artist",
            release: "Resolved release",
            submittedTrack: "Original Élan",
            submittedArtist: "Björk",
            submittedRelease: "Debut"
        )
        let listens = [canonical, submitted]

        XCTAssertEqual(HistoryLoadedListenSearch.filter(listens, query: "").count, 2)
        XCTAssertEqual(HistoryLoadedListenSearch.filter(listens, query: "midnight").map(\.id), [canonical.id])
        XCTAssertEqual(HistoryLoadedListenSearch.filter(listens, query: "m83").map(\.id), [canonical.id])
        XCTAssertEqual(HistoryLoadedListenSearch.filter(listens, query: "dreaming").map(\.id), [canonical.id])
        XCTAssertEqual(HistoryLoadedListenSearch.filter(listens, query: "elan").map(\.id), [submitted.id])
        XCTAssertEqual(HistoryLoadedListenSearch.filter(listens, query: "bjork").map(\.id), [submitted.id])
        XCTAssertEqual(HistoryLoadedListenSearch.filter(listens, query: "debut").map(\.id), [submitted.id])
    }

    func testLoadedHistorySearchAllowsTermsAcrossFieldsAndMatchesPlayingNow() {
        let playingNow = historySearchListen(
            title: "Neon Skyline",
            artist: "Andy Shauf",
            release: "The Neon Skyline",
            isPlayingNow: true
        )
        let other = historySearchListen(title: "Neon", artist: "Someone Else", release: "Elsewhere")

        XCTAssertTrue(HistoryLoadedListenSearch.matches(playingNow, query: "neon andy"))
        XCTAssertFalse(HistoryLoadedListenSearch.matches(other, query: "neon andy"))
        XCTAssertEqual(HistoryLoadedListenSearch.filter([playingNow, other], query: "neon andy").map(\.id), [playingNow.id])
    }

    func testLoadedHistorySearchSuppressesPaginationAndRefreshWhileActive() {
        XCTAssertTrue(HistoryLoadedListenSearch.allowsPagination(query: "   "))
        XCTAssertTrue(HistoryLoadedListenSearch.allowsRefresh(query: "\n\t"))
        XCTAssertFalse(HistoryLoadedListenSearch.allowsPagination(query: "artist"))
        XCTAssertFalse(HistoryLoadedListenSearch.allowsRefresh(query: "artist"))
    }

    private func recording(mbid: UUID?, msid: UUID?) -> Recording {
        Recording(
            identity: .init(mbid: mbid, msid: msid),
            title: "Fixture Track",
            artistName: "Fixture Artist",
            artistMBIDs: [FixtureProvider.artistMBID],
            releaseTitle: "Fixture Album",
            releaseMBID: FixtureProvider.releaseMBID,
            releaseGroupMBID: nil,
            artworkReleaseMBID: FixtureProvider.releaseMBID,
            durationMilliseconds: 180_000,
            source: "Fixture"
        )
    }

    private func historySearchListen(
        title: String,
        artist: String,
        release: String?,
        submittedTrack: String? = nil,
        submittedArtist: String? = nil,
        submittedRelease: String? = nil,
        isPlayingNow: Bool = false
    ) -> Listen {
        let inspection: ListenInspection?
        if let submittedTrack, let submittedArtist {
            inspection = ListenInspection(
                submittedArtist: submittedArtist,
                submittedTrack: submittedTrack,
                submittedRelease: submittedRelease,
                recordingMSID: nil,
                submittedRecordingMSID: nil,
                submittedArtistMBIDs: [],
                submittedRecordingMBID: nil,
                submittedReleaseMBID: nil,
                submittedReleaseGroupMBID: nil,
                submittedTrackMBID: nil,
                submittedWorkMBIDs: [],
                resolvedArtistMBIDs: [],
                resolvedRecordingMBID: nil,
                resolvedReleaseMBID: nil,
                resolvedReleaseGroupMBID: nil,
                resolvedRecordingName: nil,
                trackNumber: nil,
                isrc: nil,
                spotifyID: nil,
                tags: [],
                mediaPlayer: nil,
                mediaPlayerVersion: nil,
                submissionClient: nil,
                submissionClientVersion: nil,
                musicService: nil,
                musicServiceName: nil,
                originURL: nil,
                durationMilliseconds: nil
            )
        } else {
            inspection = nil
        }
        return Listen(
            recording: Recording(
                identity: .init(mbid: nil, msid: UUID()),
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: release,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: .now,
            insertedAt: nil,
            isPlayingNow: isPlayingNow,
            inspection: inspection
        )
    }

    nonisolated private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    nonisolated private func waitForCondition(
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for asynchronous test state.", file: file, line: line)
                throw GateTestError.timeout
            }
            try await clock.sleep(for: .milliseconds(1))
        }
    }
}

private enum GateTestError: Error {
    case rateLimited
    case timeout
}

private actor GateProbe {
    private var started = false

    func markStarted() { started = true }
    func hasStarted() -> Bool { started }
}

private actor ReadGateProbe {
    private var starts = 0
    private var cancellations = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func markStarted() { starts += 1 }

    func startAndWait() async {
        starts += 1
        await withCheckedContinuation { continuations.append($0) }
    }

    func markCancelled() { cancellations += 1 }
    func startedCount() -> Int { starts }
    func cancellationCount() -> Int { cancellations }

    func releaseOne() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor SearchFixtureProvider: SearchProviding {
    private let delay: Duration?
    private var calls: [(String, SearchScope)] = []
    private var cancellations = 0

    init(delay: Duration? = nil) { self.delay = delay }

    func search(query: String, scope: SearchScope) async throws -> [SearchResult] {
        calls.append((query, scope))
        if let delay {
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch {
                cancellations += 1
                throw error
            }
        }
        return [.user(.init(username: query))]
    }

    func requestCount() -> Int { calls.count }
    func queries() -> [String] { calls.map(\.0) }
    func cancellationCount() -> Int { cancellations }
}

private extension DailyActivity {
    static func fixture(period: ListeningActivityPeriod, listenCount: Int) -> DailyActivity {
        DailyActivity(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            dailyActivity: ["Monday": [.init(hour: 20, listenCount: listenCount)]]
        )
    }
}

private actor DailyActivityProvider: ListeningProvider {
    enum Result: Sendable {
        case activity(listenCount: Int)
        case noContent
        case failure
    }

    private var results: [Result]
    private var delays: [Duration]
    private let ignoresCancellation: Bool
    private var requests = 0

    init(
        result: Result,
        delay: Duration = .zero,
        ignoresCancellation: Bool = false
    ) {
        self.results = [result]
        self.delays = [delay]
        self.ignoresCancellation = ignoresCancellation
    }

    init(results: [Result], delays: [Duration], ignoresCancellation: Bool) {
        self.results = results
        self.delays = delays
        self.ignoresCancellation = ignoresCancellation
    }

    func validateToken() async throws -> String { "fixture" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func dailyActivity(username: String, period: ListeningActivityPeriod) async throws -> DailyActivity? {
        let index = requests
        requests += 1
        let delay = delays[min(index, delays.count - 1)]
        if delay > .zero {
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch where !ignoresCancellation {
                throw CancellationError()
            } catch {
                // Deliberately behave like a provider that returns late after
                // cancellation, to prove the model's request ID protection.
            }
        }
        switch results[min(index, results.count - 1)] {
        case let .activity(listenCount):
            return .fixture(period: period, listenCount: listenCount)
        case .noContent:
            return nil
        case .failure:
            throw URLError(.cannotConnectToHost)
        }
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    func requestCount() -> Int { requests }
}

private extension EraActivity {
    static func fixture(
        period: ListeningActivityPeriod,
        year: Int,
        listenCount: Int
    ) -> EraActivity {
        EraActivity(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            years: [.init(year: year, listenCount: listenCount)]
        )
    }
}

private actor EraActivityProvider: ListeningProvider {
    enum Result: Sendable {
        case activity(year: Int, listenCount: Int)
        case noContent
        case failure
    }

    private let result: Result
    private let delay: Duration
    private var requests = 0

    init(result: Result, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }

    func validateToken() async throws -> String { "fixture" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func eraActivity(username: String, period: ListeningActivityPeriod) async throws -> EraActivity? {
        requests += 1
        if delay > .zero {
            try await ContinuousClock().sleep(for: delay)
        }
        switch result {
        case let .activity(year, listenCount):
            return .fixture(period: period, year: year, listenCount: listenCount)
        case .noContent:
            return nil
        case .failure:
            throw URLError(.cannotConnectToHost)
        }
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    func requestCount() -> Int { requests }
}

private extension ArtistEvolutionActivity {
    static func fixture(
        period: ListeningActivityPeriod,
        listenCount: Int
    ) -> ArtistEvolutionActivity {
        let timeUnit: String
        switch period {
        case .thisWeek, .lastWeek:
            timeUnit = "Monday"
        case .thisMonth, .lastMonth:
            timeUnit = "1"
        case .thisYear, .lastYear:
            timeUnit = "January"
        case .allTime:
            timeUnit = "2024"
        }
        return ArtistEvolutionActivity(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [
                .init(
                    timeUnit: timeUnit,
                    artistMBID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
                    artistName: "Fixture Artist",
                    listenCount: listenCount
                ),
            ]
        )
    }
}

private actor ArtistEvolutionProvider: ListeningProvider {
    enum Result: Sendable {
        case activity(listenCount: Int)
        case noContent
        case failure
    }

    private var results: [Result]
    private var delays: [Duration]
    private let ignoresCancellation: Bool
    private var requests = 0

    init(result: Result, delay: Duration = .zero, ignoresCancellation: Bool = false) {
        self.results = [result]
        self.delays = [delay]
        self.ignoresCancellation = ignoresCancellation
    }

    init(results: [Result], delays: [Duration], ignoresCancellation: Bool) {
        self.results = results
        self.delays = delays
        self.ignoresCancellation = ignoresCancellation
    }

    func validateToken() async throws -> String { "fixture" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func artistEvolutionActivity(
        username: String,
        period: ListeningActivityPeriod
    ) async throws -> ArtistEvolutionActivity? {
        let index = requests
        requests += 1
        let delay = delays[min(index, delays.count - 1)]
        if delay > .zero {
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch where !ignoresCancellation {
                throw CancellationError()
            } catch {
                // Deliberately return late to exercise request-ID protection.
            }
        }
        switch results[min(index, results.count - 1)] {
        case let .activity(listenCount):
            return .fixture(period: period, listenCount: listenCount)
        case .noContent:
            return nil
        case .failure:
            throw URLError(.cannotConnectToHost)
        }
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    func requestCount() -> Int { requests }
}

private extension GenreActivity {
    static func fixture(
        period: ListeningActivityPeriod,
        listenCount: Int
    ) -> GenreActivity {
        GenreActivity(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [.init(genre: "Fixture Genre", hour: 20, listenCount: listenCount)]
        )
    }
}

private actor GenreActivityProvider: ListeningProvider {
    enum Result: Sendable {
        case activity(listenCount: Int)
        case noContent
        case failure
    }

    private var results: [Result]
    private var delays: [Duration]
    private let ignoresCancellation: Bool
    private var requests = 0

    init(result: Result, delay: Duration = .zero, ignoresCancellation: Bool = false) {
        self.results = [result]
        self.delays = [delay]
        self.ignoresCancellation = ignoresCancellation
    }

    init(results: [Result], delays: [Duration], ignoresCancellation: Bool) {
        self.results = results
        self.delays = delays
        self.ignoresCancellation = ignoresCancellation
    }

    func validateToken() async throws -> String { "fixture" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .distantPast, buckets: [])
    }
    func genreActivity(username: String, period: ListeningActivityPeriod) async throws -> GenreActivity? {
        let index = requests
        requests += 1
        let delay = delays[min(index, delays.count - 1)]
        if delay > .zero {
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch where !ignoresCancellation {
                throw CancellationError()
            } catch {
                // Deliberately return after cancellation to exercise the
                // model's request-ID protection.
            }
        }
        switch results[min(index, results.count - 1)] {
        case let .activity(listenCount):
            return .fixture(period: period, listenCount: listenCount)
        case .noContent:
            return nil
        case .failure:
            throw URLError(.cannotConnectToHost)
        }
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    func requestCount() -> Int { requests }
}

private actor DeleteListenProvider: ListeningProvider {
    enum DeleteResult: Sendable {
        case accepted
        case ambiguous
        case cancelled
        case definiteFailure
    }

    private let deleteResults: [DeleteResult]
    private let deleteDelay: Duration
    private let validationDelay: Duration
    private let canonicalUsername: String?
    private let recentListensFails: Bool
    private let targetMSID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
    private var deleteRequests = 0
    private var requestedUsername = "fixture-user"

    init(
        deleteResult: DeleteResult = .accepted,
        deleteDelay: Duration = .zero,
        validationDelay: Duration = .zero,
        canonicalUsername: String? = nil,
        recentListensFails: Bool = false
    ) {
        deleteResults = [deleteResult]
        self.deleteDelay = deleteDelay
        self.validationDelay = validationDelay
        self.canonicalUsername = canonicalUsername
        self.recentListensFails = recentListensFails
    }

    init(deleteResults: [DeleteResult], deleteDelay: Duration = .zero) {
        self.deleteResults = deleteResults
        self.deleteDelay = deleteDelay
        validationDelay = .zero
        canonicalUsername = nil
        recentListensFails = false
    }

    func validateToken() async throws -> String {
        if validationDelay > .zero {
            try await ContinuousClock().sleep(for: validationDelay)
        }
        return canonicalUsername ?? requestedUsername
    }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        requestedUsername = username
        if recentListensFails {
            throw URLError(.notConnectedToInternet)
        }
        let target = listen(title: "Delete me", timestamp: 1_700_000_000, msid: targetMSID)
        // Duplicate source rows can arise through overlapping history pages;
        // a confirmed deletion must hide both rather than only the tapped row.
        return [target, target, listen(title: "Keep me", timestamp: 1_699_999_000, msid: UUID())]
    }

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

    func deleteListen(listenedAt: Date, recordingMSID: UUID) async throws {
        deleteRequests += 1
        if deleteDelay > .zero {
            try await ContinuousClock().sleep(for: deleteDelay)
        }
        let result = deleteResults[min(deleteRequests - 1, deleteResults.count - 1)]
        switch result {
        case .accepted:
            return
        case .ambiguous:
            throw ProviderError.deleteListenOutcomeUnknown
        case .cancelled:
            throw CancellationError()
        case .definiteFailure:
            throw LBError.invalidJSON
        }
    }

    func deleteRequestCount() -> Int { deleteRequests }

    private func listen(title: String, timestamp: TimeInterval, msid: UUID) -> Listen {
        Listen(
            recording: Recording(
                identity: .init(mbid: nil, msid: msid),
                title: title,
                artistName: "Fixture Artist",
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: Date(timeIntervalSince1970: timestamp),
            insertedAt: nil,
            isPlayingNow: false
        )
    }
}

private actor DeleteListenTransportSpy: ListenDeletionTransport {
    private let error: LBError?
    private let waitsForCancellation: Bool
    private(set) var callCount = 0
    private(set) var hasStarted = false

    init(error: LBError? = nil, waitsForCancellation: Bool = false) {
        self.error = error
        self.waitsForCancellation = waitsForCancellation
    }

    func deleteListen(listenedAt: Date, recordingMSID: UUID) async throws {
        callCount += 1
        hasStarted = true
        if waitsForCancellation {
            try await ContinuousClock().sleep(for: .seconds(30))
        }
        if let error { throw error }
    }
}

private actor FixtureProvider: ListeningProvider {
    static let artistMBID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let releaseMBID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let recordingMBID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let activityDelay: Duration?
    private let freshReleaseDelay: Duration?
    private var activityRequests: [ListeningActivityPeriod: Int] = [:]
    private var freshReleaseRequests: [FreshReleaseScope: Int] = [:]
    private var freshReleaseQueries: [FreshReleaseQuery: Int] = [:]

    init(activityDelay: Duration? = nil, freshReleaseDelay: Duration? = nil) {
        self.activityDelay = activityDelay
        self.freshReleaseDelay = freshReleaseDelay
    }

    func validateToken() async throws -> String { "fixture-user" }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        [
            listen(title: "Fixture Track", timestamp: 1_700_000_000),
            listen(title: "Earlier Track", timestamp: 1_699_999_000),
        ]
    }

    func playingNow(username: String) async throws -> Listen? {
        listen(title: "Playing Now", timestamp: 1_700_000_500, isPlayingNow: true)
    }

    func listenCount(username: String) async throws -> Int { 42 }

    func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
        [RankedArtist(mbid: Self.artistMBID, name: "Fixture Artist", listenCount: 42)]
    }

    func topReleases(username: String, count: Int) async throws -> [RankedRelease] {
        [
            RankedRelease(
                mbid: Self.releaseMBID,
                name: "Fixture Album",
                artistName: "Fixture Artist",
                artistMBIDs: [Self.artistMBID],
                listenCount: 21
            ),
        ]
    }

    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
        [
            RankedRecording(
                mbid: Self.recordingMBID,
                releaseMBID: Self.releaseMBID,
                title: "Fixture Track",
                artistName: "Fixture Artist",
                artistMBIDs: [Self.artistMBID],
                releaseTitle: "Fixture Album",
                listenCount: 12
            ),
        ]
    }

    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        activityRequests[period, default: 0] += 1
        if let activityDelay {
            try await ContinuousClock().sleep(for: activityDelay)
        }
        return ListeningActivity(
            period: period,
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_086_400),
            lastUpdated: Date(timeIntervalSince1970: 1_700_100_000),
            buckets: [
                .init(
                    label: "Monday",
                    from: Date(timeIntervalSince1970: 1_700_000_000),
                    to: Date(timeIntervalSince1970: 1_700_043_200),
                    listenCount: 6
                ),
                .init(
                    label: "Tuesday",
                    from: Date(timeIntervalSince1970: 1_700_043_200),
                    to: Date(timeIntervalSince1970: 1_700_086_400),
                    listenCount: 9
                ),
            ]
        )
    }

    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] {
        try await freshReleases(username: username, query: .default(for: scope))
    }

    func freshReleases(username: String, query: FreshReleaseQuery) async throws -> [FreshRelease] {
        freshReleaseRequests[query.scope, default: 0] += 1
        freshReleaseQueries[query, default: 0] += 1
        if let freshReleaseDelay {
            try await ContinuousClock().sleep(for: freshReleaseDelay)
        }
        guard query.scope == .all else { return [] }
        return [
            FreshRelease(
                releaseMBID: Self.releaseMBID,
                releaseGroupMBID: nil,
                title: "Fresh Fixture",
                artistName: "Fixture Artist",
                artistMBIDs: [Self.artistMBID],
                releaseDate: "2026-9-7",
                primaryType: "Album",
                secondaryType: nil,
                tags: ["fixture"],
                confidence: nil,
                listenCount: 1,
                artworkReleaseMBID: Self.releaseMBID,
                sourcePosition: 0
            ),
        ]
    }

    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    func activityRequestCount(for period: ListeningActivityPeriod) -> Int {
        activityRequests[period, default: 0]
    }

    func freshReleaseRequestCount(for scope: FreshReleaseScope) -> Int {
        freshReleaseRequests[scope, default: 0]
    }

    func freshReleaseRequestCount(for query: FreshReleaseQuery) -> Int {
        freshReleaseQueries[query, default: 0]
    }

    func freshReleaseRequestCount() -> Int {
        freshReleaseQueries.values.reduce(0, +)
    }

    private func listen(title: String, timestamp: TimeInterval, isPlayingNow: Bool = false) -> Listen {
        Listen(
            recording: Recording(
                identity: .init(mbid: Self.recordingMBID, msid: nil),
                title: title,
                artistName: "Fixture Artist",
                artistMBIDs: [Self.artistMBID],
                releaseTitle: "Fixture Album",
                releaseMBID: Self.releaseMBID,
                releaseGroupMBID: nil,
                artworkReleaseMBID: Self.releaseMBID,
                durationMilliseconds: 180_000,
                source: "Fixture"
            ),
            listenedAt: Date(timeIntervalSince1970: timestamp),
            insertedAt: nil,
            isPlayingNow: isPlayingNow
        )
    }
}

private actor BoundaryProvider: ListeningProvider {
    private var lastBefore: Date?
    private var lastCount = 0

    func validateToken() async throws -> String { "fixture-user" }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        lastBefore = before
        lastCount = count
        if before == nil {
            return (0 ..< 39).map { index in
                listen(title: "Recent \(index)", timestamp: 2_000 - Double(index))
            } + [listen(title: "Boundary original", timestamp: 1_900)]
        }
        return [
            listen(title: "Boundary original", timestamp: 1_900),
            listen(title: "Boundary sibling", timestamp: 1_900),
            listen(title: "Older listen", timestamp: 1_899),
        ]
    }

    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 42 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        ListeningActivity(
            period: period,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            buckets: []
        )
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    func requestedBefore() -> Date? { lastBefore }
    func requestedCount() -> Int { lastCount }

    private func listen(title: String, timestamp: TimeInterval) -> Listen {
        Listen(
            recording: Recording(
                identity: .init(mbid: nil, msid: nil),
                title: title,
                artistName: "Boundary Artist",
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: "Fixture"
            ),
            listenedAt: Date(timeIntervalSince1970: timestamp),
            insertedAt: nil,
            isPlayingNow: false
        )
    }
}

private actor ReleaseGroupRankingProvider: ListeningProvider {
    private let delay: Duration?
    private let fails: Bool
    private var requests = 0
    private var cancellations = 0

    init(delay: Duration? = nil, fails: Bool = false) {
        self.delay = delay
        self.fails = fails
    }

    func validateToken() async throws -> String { "fixture-user" }
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

    func topReleaseGroups(username: String, count: Int) async throws -> [RankedReleaseGroup] {
        requests += 1
        if let delay {
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch is CancellationError {
                cancellations += 1
                throw CancellationError()
            }
        }
        if fails { throw URLError(.notConnectedToInternet) }
        return [
            .init(mbid: UUID(), name: "Mapped group", artistName: "Artist", artistMBIDs: [], listenCount: 9),
            .init(mbid: nil, name: "Unmapped group", artistName: "Artist", artistMBIDs: [], listenCount: 4),
        ]
    }

    func requestCount() -> Int { requests }
    func cancellationCount() -> Int { cancellations }
}

private actor DayHistoryProvider: ListeningProvider {
    enum Mode {
        case singleDay
        case staleSelection
        case boundarySiblings
        case repeatedCursor
        case returnsAfterCancellation
        case urlCancellation
        case stalePagination
    }
    struct Request: Sendable { let before: Date?; let after: Date? }

    private let mode: Mode
    private var requestsMade: [Request] = []
    private var requestNumber = 0
    private let recordingMBID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    init(mode: Mode) { self.mode = mode }

    func validateToken() async throws -> String { "fixture-user" }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        requestsMade.append(.init(before: before, after: after))
        requestNumber += 1
        switch mode {
        case .singleDay:
            return [listen(title: "Day listen", timestamp: 1_700_000_000, msid: nil)]
        case .staleSelection:
            if requestNumber == 1 {
                try await ContinuousClock().sleep(for: .milliseconds(60))
                return [listen(title: "Older day", timestamp: 1_700_000_000, msid: nil)]
            }
            return [listen(title: "Newer day", timestamp: 1_700_086_400, msid: nil)]
        case .boundarySiblings:
            if requestNumber == 1 {
                return (0 ..< 100).map { index in
                    listen(title: "Initial \(index)", timestamp: 2_000 - Double(index), msid: index == 99 ? UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")! : nil)
                }
            }
            return [
                listen(title: "Initial 99", timestamp: 1_901, msid: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!),
                listen(title: "Boundary sibling", timestamp: 1_901, msid: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!),
                listen(title: "Older", timestamp: 1_900, msid: nil),
            ]
        case .repeatedCursor:
            return (0 ..< 100).map { index in
                listen(title: "Repeated \(index)", timestamp: 2_000 - Double(index), msid: nil)
            }
        case .returnsAfterCancellation:
            try? await ContinuousClock().sleep(for: .seconds(1))
            return [listen(title: "Cancelled result", timestamp: 1_700_000_000, msid: nil)]
        case .urlCancellation:
            do {
                try await ContinuousClock().sleep(for: .seconds(1))
            } catch {
                throw URLError(.cancelled)
            }
            return []
        case .stalePagination:
            if requestNumber == 1 {
                return (0 ..< 100).map { index in
                    listen(title: "Initial \(index)", timestamp: 2_000 - Double(index), msid: nil)
                }
            }
            if requestNumber == 2 {
                try? await ContinuousClock().sleep(for: .milliseconds(60))
                return [listen(title: "Stale page", timestamp: 1_899, msid: nil)]
            }
            return [listen(title: "Replacement day", timestamp: 1_800, msid: nil)]
        }
    }

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
    func requests() -> [Request] { requestsMade }

    private func listen(title: String, timestamp: TimeInterval, msid: UUID?) -> Listen {
        Listen(
            recording: Recording(
                identity: .init(mbid: recordingMBID, msid: msid),
                title: title,
                artistName: "Fixture Artist",
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: Date(timeIntervalSince1970: timestamp),
            insertedAt: nil,
            isPlayingNow: false
        )
    }
}
