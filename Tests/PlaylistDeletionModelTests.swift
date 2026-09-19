import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class PlaylistDeletionModelTests: XCTestCase {
    private let account = Account(username: " Listener ", token: "fixture-token")

    func testRelaunchBarrierContainsNoCredentialUsernameOrPlaylistMetadata() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let playlistMBID = UUID()
        let journal = PlaylistDeletionJournal(directoryURL: directory)

        XCTAssertTrue(
            journal.begin(
                username: account.username,
                playlistMBID: playlistMBID
            )
        )

        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        let fileText = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(file.lastPathComponent.localizedCaseInsensitiveContains("Listener"))
        XCTAssertFalse(file.lastPathComponent.contains(playlistMBID.uuidString.lowercased()))
        XCTAssertFalse(fileText.localizedCaseInsensitiveContains("Listener"))
        XCTAssertFalse(fileText.contains("fixture-token"))
        XCTAssertFalse(fileText.contains("Careful mix"))
        XCTAssertFalse(fileText.contains(playlistMBID.uuidString.lowercased()))
        let resourceValues = try file.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: file.path()
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let directoryValues = try directory.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(directoryValues.isExcludedFromBackup, true)
        let directoryPermissions = try FileManager.default.attributesOfItem(
            atPath: directory.path()
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)

        let relaunched = PlaylistDeletionJournal(directoryURL: directory)
        XCTAssertTrue(
            relaunched.requiresReview(
                username: "listener",
                playlistMBID: playlistMBID
            )
        )
        XCTAssertFalse(
            relaunched.begin(
                username: "listener",
                playlistMBID: playlistMBID
            )
        )
        XCTAssertTrue(
            relaunched.begin(
                username: "another-account",
                playlistMBID: playlistMBID
            )
        )
    }

    func testFirstUseCreatesEachNestedJournalDirectoryAndPersistsBarrier() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appending(
            path: "Brainz/playlist-deletions-v1",
            directoryHint: .isDirectory
        )
        let playlistMBID = UUID()
        let journal = PlaylistDeletionJournal(directoryURL: nested)

        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path()))
        XCTAssertTrue(
            journal.begin(
                username: account.username,
                playlistMBID: playlistMBID
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path()))

        let relaunched = PlaylistDeletionJournal(directoryURL: nested)
        XCTAssertTrue(
            relaunched.requiresReview(
                username: account.username,
                playlistMBID: playlistMBID
            )
        )
    }

    func testCorruptPairFailsClosedAndCanResetOnlyAfterFreshInspection() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let playlistMBID = UUID()
        let detail = playlist(mbid: playlistMBID)
        let original = PlaylistDeletionJournal(directoryURL: directory)
        XCTAssertTrue(
            original.begin(
                username: account.username,
                playlistMBID: playlistMBID
            )
        )
        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        try Data("corrupt".utf8).write(to: file)

        let relaunched = PlaylistDeletionJournal(directoryURL: directory)
        let post = DeletionProviderSpy()
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: post,
            journal: relaunched
        )

        XCTAssertTrue(model.requiresRecovery(playlistMBID: playlistMBID))
        let resetBeforeInspection = await model.resetSafetyRecord(
            playlistMBID: playlistMBID
        )
        XCTAssertFalse(resetBeforeInspection)
        let didConfirmDeletion = await model.checkAgain(
            playlistMBID: playlistMBID
        )
        XCTAssertFalse(didConfirmDeletion)
        XCTAssertTrue(model.canResetSafetyRecord(playlistMBID: playlistMBID))
        let didReset = await model.resetSafetyRecord(
            playlistMBID: playlistMBID
        )
        XCTAssertTrue(didReset)
        XCTAssertFalse(model.requiresReview(playlistMBID: playlistMBID))
        XCTAssertTrue(model.canAttemptDelete(detail))
        let postCalls = await post.callCount()
        XCTAssertEqual(postCalls, 0)
    }

    func testUnwritableSafetyStorageBlocksPostAfterPreflight() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let notADirectory = parent.appending(path: "not-a-directory")
        try Data().write(to: notADirectory)
        let detail = playlist()
        let post = DeletionProviderSpy()
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: post,
            journal: PlaylistDeletionJournal(directoryURL: notADirectory)
        )

        let didDelete = await model.delete(detail)
        let postCalls = await post.callCount()
        XCTAssertFalse(didDelete)
        XCTAssertEqual(postCalls, 0)
        XCTAssertTrue(model.requiresRecovery(playlistMBID: detail.mbid))
        guard case .needsReview = model.notice else {
            return XCTFail("Expected a fail-closed recovery notice")
        }
    }

    func testOnlyAuthenticatedExactCreatorCanDelete() {
        let detail = playlist(creator: "OwNeR")
        XCTAssertTrue(
            PlaylistDeletionModel.canDelete(
                account: .init(username: " owner ", token: "token"),
                detail: detail
            )
        )
        XCTAssertFalse(
            PlaylistDeletionModel.canDelete(
                account: .init(username: "collaborator", token: "token"),
                detail: detail
            )
        )
        XCTAssertFalse(
            PlaylistDeletionModel.canDelete(
                account: .init(username: "owner", token: ""),
                detail: detail
            )
        )
    }

    func testFreshOwnerPreflightThenSuccessRecordsSemanticDeletion() async {
        let detail = playlist(title: "Careful mix")
        let post = DeletionProviderSpy()
        let mutations = PlaylistMutationJournal()
        let inspection = DeletionDetailSpy(values: [.success(detail)])
        let model = makeModel(
            detailProvider: inspection,
            provider: post,
            mutationJournal: mutations
        )

        let didDelete = await model.delete(detail)
        let inspectionCalls = await inspection.inspectionCount()
        let postCalls = await post.callCount()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(inspectionCalls, 1)
        XCTAssertEqual(postCalls, 1)
        XCTAssertFalse(model.requiresReview(playlistMBID: detail.mbid))
        XCTAssertEqual(
            model.notice,
            .confirmed(.deleted(title: "Careful mix"))
        )
        XCTAssertEqual(
            mutations.events.last?.event,
            .deletion(.init(
                ownerUsername: "listener",
                playlistMBID: detail.mbid
            ))
        )
    }

    func testMismatchedOrNonOwnerPreflightNeverDispatches() async {
        let seed = playlist()
        let wrongID = playlist(mbid: UUID())
        let wrongOwner = playlist(mbid: seed.mbid, creator: "other")

        for canonical in [wrongID, wrongOwner] {
            let post = DeletionProviderSpy()
            let model = makeModel(
                detailProvider: DeletionDetailSpy(
                    values: [.success(canonical)]
                ),
                provider: post
            )
            let didDelete = await model.delete(seed)
            let postCalls = await post.callCount()
            XCTAssertFalse(didDelete)
            XCTAssertEqual(postCalls, 0)
        }
    }

    func testTwoConcurrentModelsSharingJournalDispatchOnePost() async {
        let detail = playlist()
        let journal = PlaylistDeletionJournal()
        let post = DeletionProviderSpy(delay: .milliseconds(40))
        let inspection = DeletionDetailSpy(
            values: [.success(detail), .success(detail)]
        )
        let first = makeModel(
            detailProvider: inspection,
            provider: post,
            journal: journal
        )
        let second = makeModel(
            detailProvider: inspection,
            provider: post,
            journal: journal
        )

        async let firstResult = first.delete(detail)
        async let secondResult = second.delete(detail)
        let results = await [firstResult, secondResult]

        XCTAssertEqual(results.filter { $0 }.count, 1)
        let postCalls = await post.callCount()
        XCTAssertEqual(postCalls, 1)
    }

    func testIndeterminatePostRetainsBarrierAndNeverReplays() async {
        let detail = playlist()
        let post = DeletionProviderSpy(
            error: PlaylistMutationProviderError.indeterminateDeletion
        )
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: post
        )

        let firstAttempt = await model.delete(detail)
        XCTAssertFalse(firstAttempt)
        XCTAssertTrue(model.requiresReview(playlistMBID: detail.mbid))
        let secondAttempt = await model.delete(detail)
        let postCalls = await post.callCount()
        XCTAssertFalse(secondAttempt)
        XCTAssertEqual(postCalls, 1)
        guard case .needsReview = model.notice else {
            return XCTFail("Expected an indeterminate review notice")
        }
    }

    func testProviderCancellationRetainsBarrierBecauseDispatchIsUnknown() async {
        let detail = playlist()
        let post = DeletionProviderSpy(error: CancellationError())
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: post
        )

        let didDelete = await model.delete(detail)
        XCTAssertFalse(didDelete)
        XCTAssertTrue(model.requiresReview(playlistMBID: detail.mbid))
        let postCalls = await post.callCount()
        XCTAssertEqual(postCalls, 1)
        guard case .needsReview = model.notice else {
            return XCTFail("Expected a conservative cancellation review")
        }
    }

    func testNotFoundAfterOwnerPreflightConfirmsOnlyDesiredEndState() async {
        let detail = playlist()
        let mutations = PlaylistMutationJournal()
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: DeletionProviderSpy(
                error: PlaylistMutationProviderError.playlistUnavailable
            ),
            mutationJournal: mutations
        )

        let didDelete = await model.delete(detail)
        XCTAssertTrue(didDelete)
        XCTAssertEqual(model.notice, .confirmed(.noLongerAvailable))
        XCTAssertFalse(model.requiresReview(playlistMBID: detail.mbid))
        guard case .deletion = mutations.events.last?.event else {
            return XCTFail("Expected confirmed-absence journal event")
        }
    }

    func testForbiddenPostClearsBarrierAndDeniesFurtherSessionAttempts() async {
        let detail = playlist()
        let post = DeletionProviderSpy(
            error: PlaylistMutationProviderError.deleteNotOwner
        )
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: post
        )

        let firstAttempt = await model.delete(detail)
        XCTAssertFalse(firstAttempt)
        XCTAssertFalse(model.requiresReview(playlistMBID: detail.mbid))
        XCTAssertFalse(model.canAttemptDelete(detail))
        let secondAttempt = await model.delete(detail)
        let postCalls = await post.callCount()
        XCTAssertFalse(secondAttempt)
        XCTAssertEqual(postCalls, 1)
    }

    func testForbiddenDenialSurvivesReopeningDetailInSameSession() async {
        let detail = playlist()
        let registry = PlaylistDeletionDenialRegistry()
        let firstPost = DeletionProviderSpy(
            error: PlaylistMutationProviderError.deleteNotOwner
        )
        let firstModel = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: firstPost,
            denialRegistry: registry
        )

        let firstResult = await firstModel.delete(detail)
        XCTAssertFalse(firstResult)

        let reopenedInspection = DeletionDetailSpy(values: [])
        let reopenedPost = DeletionProviderSpy()
        let reopenedModel = makeModel(
            detailProvider: reopenedInspection,
            provider: reopenedPost,
            denialRegistry: registry
        )
        XCTAssertFalse(reopenedModel.canAttemptDelete(detail))
        let reopenedResult = await reopenedModel.delete(detail)
        let reopenedInspectionCount = await reopenedInspection.inspectionCount()
        let reopenedPostCount = await reopenedPost.callCount()
        XCTAssertFalse(reopenedResult)
        XCTAssertEqual(reopenedInspectionCount, 0)
        XCTAssertEqual(reopenedPostCount, 0)
    }

    func testAuthenticationFailureClearsBarrierAndPublishesAccessLoss() async {
        let detail = playlist()
        let mutations = PlaylistMutationJournal()
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: DeletionProviderSpy(
                error: PlaylistMutationProviderError.invalidAuthentication
            ),
            mutationJournal: mutations
        )

        let didDelete = await model.delete(detail)
        XCTAssertFalse(didDelete)
        XCTAssertFalse(model.requiresReview(playlistMBID: detail.mbid))
        XCTAssertEqual(model.accessLossReason, .authentication)
        guard case let .accessLoss(event) = mutations.events.last?.event else {
            return XCTFail("Expected authentication-loss journal event")
        }
        XCTAssertEqual(event.sourceMBID, detail.mbid)
        XCTAssertEqual(event.reason, .authentication)
    }

    func testRateLimitIsDefiniteAndClearsBarrier() async {
        let detail = playlist()
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: DeletionProviderSpy(
                error: ProviderError.rateLimited(retryAfterSeconds: 8)
            )
        )

        let didDelete = await model.delete(detail)
        XCTAssertFalse(didDelete)
        XCTAssertFalse(model.requiresReview(playlistMBID: detail.mbid))
        guard case .failed = model.notice else {
            return XCTFail("Expected visible rate-limit failure")
        }
    }

    func testCheckAgainExistingPlaylistClearsBarrierAndAllowsExplicitRetry() async {
        let detail = playlist()
        let journal = PlaylistDeletionJournal()
        XCTAssertTrue(
            journal.begin(
                username: account.username,
                playlistMBID: detail.mbid
            )
        )
        let model = makeModel(
            detailProvider: DeletionDetailSpy(values: [.success(detail)]),
            provider: DeletionProviderSpy(),
            journal: journal
        )

        let didConfirmDeletion = await model.checkAgain(
            playlistMBID: detail.mbid
        )
        XCTAssertFalse(didConfirmDeletion)
        XCTAssertFalse(model.requiresReview(playlistMBID: detail.mbid))
        XCTAssertTrue(model.canAttemptDelete(detail))
        guard case .failed = model.notice else {
            return XCTFail("Expected an exists-again outcome")
        }
    }

    func testCheckAgainUnavailableConfirmsAbsenceWithoutAttribution() async {
        let detail = playlist()
        let journal = PlaylistDeletionJournal()
        let mutations = PlaylistMutationJournal()
        XCTAssertTrue(
            journal.begin(
                username: account.username,
                playlistMBID: detail.mbid
            )
        )
        let model = makeModel(
            detailProvider: DeletionDetailSpy(
                values: [.failure(MediaDetailError.playlistUnavailable)]
            ),
            provider: DeletionProviderSpy(),
            journal: journal,
            mutationJournal: mutations
        )

        let didConfirmDeletion = await model.checkAgain(
            playlistMBID: detail.mbid
        )
        XCTAssertTrue(didConfirmDeletion)
        XCTAssertFalse(model.requiresReview(playlistMBID: detail.mbid))
        XCTAssertEqual(model.notice, .confirmed(.noLongerAvailable))
        guard case .deletion = mutations.events.last?.event else {
            return XCTFail("Expected confirmed-absence event")
        }
    }

    func testRecoveryConfirmedAbsenceEvictsDetailAndProfileCaches() async {
        let detail = playlist()
        let journal = PlaylistDeletionJournal()
        XCTAssertTrue(
            journal.begin(
                username: account.username,
                playlistMBID: detail.mbid
            )
        )
        let details = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let pages = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let detailKey = PlaylistDetailCacheKey(
            mbid: detail.mbid,
            accessScope: .authenticatedViewer(.authenticated(token: "viewer"))
        )
        let pageKey = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "viewer")),
            category: .owned,
            offset: 0,
            count: 20
        )
        await details.save(detail, for: detailKey)
        await pages.save(
            .init(
                username: "listener",
                category: .owned,
                playlists: [],
                requestedCount: 20,
                offset: 0,
                totalCount: 1
            ),
            for: pageKey
        )
        let model = makeModel(
            detailProvider: DeletionDetailSpy(
                values: [.failure(MediaDetailError.playlistUnavailable)]
            ),
            provider: DeletionProviderSpy(),
            journal: journal,
            detailCache: details,
            profilePageCache: pages
        )

        let result = await model.checkAgain(playlistMBID: detail.mbid)
        let cachedDetail = await details.value(for: detailKey)
        let cachedPage = await pages.value(for: pageKey)

        XCTAssertTrue(result)
        XCTAssertNil(cachedDetail)
        XCTAssertNil(cachedPage)
    }

    func testCheckAgainTransientOrAuthenticationFailureRetainsBarrier() async {
        let detail = playlist()
        for error in [
            DeletionFixtureError.offline as any Error & Sendable,
            ProviderError.invalidToken as any Error & Sendable,
        ] {
            let journal = PlaylistDeletionJournal()
            let mutations = PlaylistMutationJournal()
            XCTAssertTrue(
                journal.begin(
                    username: account.username,
                    playlistMBID: detail.mbid
                )
            )
            let model = makeModel(
                detailProvider: DeletionDetailSpy(values: [.failure(error)]),
                provider: DeletionProviderSpy(),
                journal: journal,
                mutationJournal: mutations
            )

            let didConfirmDeletion = await model.checkAgain(
                playlistMBID: detail.mbid
            )
            XCTAssertFalse(didConfirmDeletion)
            XCTAssertTrue(model.requiresReview(playlistMBID: detail.mbid))
        }
    }

    func testProviderSuccessDispatchesOnceAndEvictsAllPlaylistCaches() async throws {
        let playlistMBID = UUID()
        let details = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let pages = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let publicKey = PlaylistDetailCacheKey(
            mbid: playlistMBID,
            accessScope: .publicOnly
        )
        let privateKey = PlaylistDetailCacheKey(
            mbid: playlistMBID,
            accessScope: .authenticatedViewer(.authenticated(token: "viewer"))
        )
        let pageKey = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "viewer")),
            category: .owned,
            offset: 0,
            count: 20
        )
        let cached = playlist(mbid: playlistMBID)
        await details.save(cached, for: publicKey)
        await details.save(cached, for: privateKey)
        await pages.save(
            .init(
                username: "listener",
                category: .owned,
                playlists: [],
                requestedCount: 20,
                offset: 0,
                totalCount: 0
            ),
            for: pageKey
        )
        let transport = DeletionTransportSpy()
        let provider = ListenBrainzPlaylistDeletionProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: details,
            profilePageCache: pages
        )

        try await provider.delete(mbid: playlistMBID)

        let transportCalls = await transport.callCount()
        let publicValue = await details.value(for: publicKey)
        let privateValue = await details.value(for: privateKey)
        let pageValue = await pages.value(for: pageKey)
        XCTAssertEqual(transportCalls, 1)
        XCTAssertNil(publicValue)
        XCTAssertNil(privateValue)
        XCTAssertNil(pageValue)
    }

    func testProviderMapsRateLimitWithoutRetrying() async {
        let transport = DeletionTransportSpy(
            error: LBError.rateLimited(resetIn: 7)
        )
        let provider = ListenBrainzPlaylistDeletionProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: EntityDetailCache(),
            profilePageCache: EntityDetailCache()
        )

        do {
            try await provider.delete(mbid: UUID())
            XCTFail("Expected rate limiting")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 7)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let transportCalls = await transport.callCount()
        XCTAssertEqual(transportCalls, 1)
    }

    func testProviderMapsForbiddenNotFoundAndLostResponsePrecisely() async {
        let cases: [(LBError, PlaylistMutationProviderError)] = [
            (.forbidden, .deleteNotOwner),
            (.notFound, .playlistUnavailable),
            (.invalidResponse, .indeterminateDeletion),
        ]

        for (source, expected) in cases {
            let transport = DeletionTransportSpy(error: source)
            let provider = ListenBrainzPlaylistDeletionProvider(
                transport: transport,
                gate: RequestGate(minimumInterval: .zero),
                detailCache: EntityDetailCache(),
                profilePageCache: EntityDetailCache()
            )
            do {
                try await provider.delete(mbid: UUID())
                XCTFail("Expected mapped deletion failure")
            } catch let error as PlaylistMutationProviderError {
                XCTAssertEqual(
                    error.localizedDescription,
                    expected.localizedDescription
                )
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            let transportCalls = await transport.callCount()
            XCTAssertEqual(transportCalls, 1)
        }
    }

    func testProviderCancellationBeforeAdmissionDoesNotDispatch() async throws {
        let gate = RequestGate(minimumInterval: .seconds(5))
        _ = try await gate.perform { true }
        let transport = CancellationDeletionTransport()
        let provider = ListenBrainzPlaylistDeletionProvider(
            transport: transport,
            gate: gate,
            detailCache: EntityDetailCache(),
            profilePageCache: EntityDetailCache()
        )
        let task = Task { try await provider.delete(mbid: UUID()) }
        await Task.yield()
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected cancellation before transport")
        } catch is CancellationError {
            // The deletion transport was never admitted.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let didStart = await transport.hasStarted
        XCTAssertFalse(didStart)
    }

    func testProviderCancellationAfterTransportStartsIsIndeterminate() async {
        let transport = CancellationDeletionTransport()
        let provider = ListenBrainzPlaylistDeletionProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: EntityDetailCache(),
            profilePageCache: EntityDetailCache()
        )
        let task = Task { try await provider.delete(mbid: UUID()) }
        while !(await transport.hasStarted) { await Task.yield() }
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected an indeterminate deletion")
        } catch PlaylistMutationProviderError.indeterminateDeletion {
            // A dispatched POST is never replayed automatically.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeModel(
        detailProvider: some PlaylistDetailProviding,
        provider: some PlaylistDeletionProviding,
        journal: PlaylistDeletionJournal = .init(),
        mutationJournal: PlaylistMutationJournal = .init(),
        denialRegistry: PlaylistDeletionDenialRegistry = .init(),
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = .init(),
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = .init()
    ) -> PlaylistDeletionModel {
        PlaylistDeletionModel(
            account: account,
            detailProvider: detailProvider,
            provider: provider,
            journal: journal,
            mutationJournal: mutationJournal,
            denialRegistry: denialRegistry,
            detailCache: detailCache,
            profilePageCache: profilePageCache
        )
    }

    private func playlist(
        mbid: UUID = UUID(),
        title: String = "Careful mix",
        creator: String = "listener"
    ) -> PlaylistDetail {
        PlaylistDetail(
            mbid: mbid,
            title: title,
            creator: creator,
            annotation: nil,
            createdAt: nil,
            lastModifiedAt: nil,
            isPublic: false,
            createdFor: nil,
            collaborators: ["friend"],
            copiedFrom: nil,
            tracks: []
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "playlist-deletion-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private actor DeletionDetailSpy: PlaylistDetailProviding {
    private var values: [Result<PlaylistDetail, any Error & Sendable>]
    private var inspections = 0

    init(values: [Result<PlaylistDetail, any Error & Sendable>]) {
        self.values = values
    }

    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        try next()
    }

    func playlistForMutationInspection(mbid: UUID) async throws -> PlaylistDetail {
        inspections += 1
        return try next()
    }

    func inspectionCount() -> Int { inspections }

    private func next() throws -> PlaylistDetail {
        guard !values.isEmpty else { throw DeletionFixtureError.missingFixture }
        return try values.removeFirst().get()
    }
}

private actor DeletionProviderSpy: PlaylistDeletionProviding {
    private let error: (any Error & Sendable)?
    private let delay: Duration
    private var calls = 0

    init(
        error: (any Error & Sendable)? = nil,
        delay: Duration = .zero
    ) {
        self.error = error
        self.delay = delay
    }

    func delete(mbid: UUID) async throws {
        calls += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
    }

    func callCount() -> Int { calls }
}

private actor DeletionTransportSpy: PlaylistDeletionTransport {
    private let error: (any Error & Sendable)?
    private var calls = 0

    init(error: (any Error & Sendable)? = nil) {
        self.error = error
    }

    func delete(mbid: UUID) async throws {
        calls += 1
        if let error { throw error }
    }

    func callCount() -> Int { calls }
}

private actor CancellationDeletionTransport: PlaylistDeletionTransport {
    private(set) var hasStarted = false

    func delete(mbid: UUID) async throws {
        hasStarted = true
        try await Task.sleep(for: .seconds(60))
    }
}

private enum DeletionFixtureError: LocalizedError, Sendable {
    case offline
    case missingFixture

    var errorDescription: String? {
        switch self {
        case .offline: "Offline"
        case .missingFixture: "Missing fixture"
        }
    }
}
