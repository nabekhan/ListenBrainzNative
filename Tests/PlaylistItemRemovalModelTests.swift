import CryptoKit
import Foundation
import XCTest

@testable import Brainz

@MainActor
final class PlaylistItemRemovalModelTests: XCTestCase {
    private let account = Account(username: " Listener ", token: "fixture-token")

    func testRelaunchBarrierAndRecordContainNoCredentialOrTrackMetadata() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let playlist = UUID()
        let journal = PlaylistItemRemovalJournal(directoryURL: directory)
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: playlist))

        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains("fixture-token"))
        XCTAssertFalse(text.contains("Listener"))
        XCTAssertFalse(text.contains("Track"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains(playlist.uuidString))
        XCTAssertFalse(file.lastPathComponent.localizedCaseInsensitiveContains(playlist.uuidString))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["digest", "version"])

        let relaunched = PlaylistItemRemovalJournal(directoryURL: directory)
        XCTAssertTrue(relaunched.requiresReview(username: "listener", playlistMBID: playlist))
        XCTAssertFalse(relaunched.begin(username: "listener", playlistMBID: playlist))
    }

    func testLegacyRemovalBarrierIsLoadedAndDurablyRemovedAfterReview() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let currentDirectory = root.appending(path: "playlist-item-mutations-v2", directoryHint: .isDirectory)
        let legacyDirectory = root.appending(path: "playlist-item-removals-v1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let playlist = UUID()
        let normalizedUsername = "listener"
        let usernameDigest = SHA256.hash(data: Data(normalizedUsername.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let legacyFile = legacyDirectory.appending(
            path: "\(usernameDigest).\(playlist.uuidString.lowercased()).json"
        )
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "playlistMBID": playlist.uuidString,
            "attemptedAt": 0.0,
        ])
        try legacyData.write(to: legacyFile)

        let journal = PlaylistItemMutationJournal(directoryURL: currentDirectory)
        XCTAssertTrue(journal.requiresReview(username: account.username, playlistMBID: playlist))
        XCTAssertFalse(journal.requiresRecovery(username: account.username, playlistMBID: playlist))
        XCTAssertTrue(journal.resolveAfterInspection(username: account.username, playlistMBID: playlist))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyFile.path()))
        XCTAssertFalse(journal.requiresReview(username: account.username, playlistMBID: playlist))
    }

    func testCorruptLegacyBarrierFailsClosedUntilPairScopedReset() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let currentDirectory = root.appending(path: "playlist-item-mutations-v2", directoryHint: .isDirectory)
        let legacyDirectory = root.appending(path: "playlist-item-removals-v1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let playlist = UUID()
        let usernameDigest = SHA256.hash(data: Data("listener".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let legacyFile = legacyDirectory.appending(
            path: "\(usernameDigest).\(playlist.uuidString.lowercased()).json"
        )
        try Data("not json".utf8).write(to: legacyFile)

        let journal = PlaylistItemMutationJournal(directoryURL: currentDirectory)

        XCTAssertTrue(journal.requiresRecovery(username: account.username, playlistMBID: playlist))
        XCTAssertFalse(journal.begin(username: account.username, playlistMBID: playlist))
        XCTAssertTrue(journal.resetRecovery(username: account.username, playlistMBID: playlist))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyFile.path()))
        XCTAssertFalse(journal.requiresReview(username: account.username, playlistMBID: playlist))
    }

    func testCorruptPairFailsClosedWithoutBlockingOrResettingAnotherPair() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = UUID()
        let second = UUID()
        let journal = PlaylistItemRemovalJournal(directoryURL: directory)
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: first))
        let firstFile = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: second))
        try Data("not json".utf8).write(to: firstFile)

        let relaunched = PlaylistItemRemovalJournal(directoryURL: directory)
        XCTAssertTrue(relaunched.requiresRecovery(username: account.username, playlistMBID: first))
        XCTAssertTrue(relaunched.requiresReview(username: account.username, playlistMBID: second))
        XCTAssertFalse(relaunched.resetRecovery(username: account.username, playlistMBID: second))
        XCTAssertTrue(relaunched.resetRecovery(username: account.username, playlistMBID: first))
        XCTAssertFalse(relaunched.requiresReview(username: account.username, playlistMBID: first))
        XCTAssertTrue(relaunched.requiresReview(username: account.username, playlistMBID: second))
    }

    func testBeginDefensivelyLoadsExistingFileAndBlocksDuplicateAttempt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let playlist = UUID()
        XCTAssertTrue(
            PlaylistItemRemovalJournal(directoryURL: directory).begin(
                username: account.username, playlistMBID: playlist))
        XCTAssertFalse(
            PlaylistItemRemovalJournal(directoryURL: directory).begin(
                username: account.username, playlistMBID: playlist))
    }

    func testUnwritableSafetyStorageBlocksProviderBeforeDispatch() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let notADirectory = parent.appending(path: "not-a-directory")
        try Data().write(to: notADirectory)
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let transport = RemovalProviderSpy()
        let model = removalModel(
            detail: RemovalDetailProvider(values: [.success(before)]), provider: transport,
            journal: .init(directoryURL: notADirectory))

        let returned = await model.remove(selected, from: before)
        XCTAssertEqual(returned, before)
        let calls = await transport.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(model.requiresRecovery(playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected recovery notice") }
    }

    func testOwnerAndCaseInsensitiveCollaboratorMayRemoveButOutsiderCannot() {
        let detail = playlist(creator: "Owner", collaborators: ["CoLlAbOrAtOr"])
        XCTAssertTrue(PlaylistItemRemovalModel.canRemove(account: .init(username: "owner", token: "x"), detail: detail))
        XCTAssertTrue(
            PlaylistItemRemovalModel.canRemove(account: .init(username: "collaborator", token: "x"), detail: detail))
        XCTAssertFalse(
            PlaylistItemRemovalModel.canRemove(account: .init(username: "other", token: "x"), detail: detail))
    }

    func testPreflightStalePositionDispatchesZeroPost() async {
        let id = UUID()
        let selected = track(position: 2, title: "Second")
        let seed = playlist(mbid: id, tracks: [track(position: 1, title: "First"), selected])
        let changed = playlist(
            mbid: id, tracks: [track(position: 1, title: "First"), track(position: 2, title: "Replacement")])
        let transport = RemovalProviderSpy()
        let model = removalModel(detail: RemovalDetailProvider(values: [.success(changed)]), provider: transport)
        let returned = await model.remove(selected, from: seed)
        XCTAssertEqual(returned, changed)
        let calls = await transport.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.notice, .stale)
    }

    func testExactCanonicalRemovalConfirmsAndClearsBarrier() async {
        let id = UUID()
        let first = track(position: 1, title: "First")
        let selected = track(position: 2, title: "Second")
        let before = playlist(mbid: id, tracks: [first, selected])
        let canonical = playlist(mbid: id, tracks: [reposition(first, to: 1)])
        let journal = PlaylistItemRemovalJournal()
        let transport = RemovalProviderSpy()
        let model = removalModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(canonical)]), provider: transport,
            journal: journal)
        let returned = await model.remove(selected, from: before)
        let calls = await transport.callCount()
        XCTAssertEqual(returned, canonical)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(model.requiresReview(playlistMBID: id))
        guard case .confirmed = model.notice else { return XCTFail("Expected confirmed removal") }
    }

    func testCanonicalMismatchRetainsBarrierAndNeverClaimsSuccess() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected, track(position: 2, title: "Second")])
        let mismatch = playlist(mbid: id, tracks: [track(position: 1, title: "Other")])
        let model = removalModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(mismatch)]),
            provider: RemovalProviderSpy())
        let returned = await model.remove(selected, from: before)
        XCTAssertEqual(returned, mismatch)
        XCTAssertTrue(model.requiresReview(playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected review notice") }
    }

    func testFreshReviewClearsValidUnresolvedBarrier() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let current = playlist(mbid: id, tracks: [selected])
        let journal = PlaylistItemRemovalJournal()
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: id))
        let model = removalModel(
            detail: RemovalDetailProvider(values: [.success(current)]),
            provider: RemovalProviderSpy(),
            journal: journal
        )

        let returned = await model.refreshAfterReview(playlistMBID: id)

        XCTAssertEqual(returned, current)
        XCTAssertFalse(model.requiresReview(playlistMBID: id))
        XCTAssertEqual(model.notice, .refreshed)
    }

    func testFreshReviewOfDifferentPlaylistRetainsSharedBarrier() async {
        let id = UUID()
        let journal = PlaylistItemMutationJournal()
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: id))
        let model = removalModel(
            detail: RemovalDetailProvider(values: [
                .success(playlist(mbid: UUID(), tracks: [track(position: 1, title: "Other")]))
            ]),
            provider: RemovalProviderSpy(),
            journal: journal
        )

        let result = await model.refreshAfterReview(playlistMBID: id)

        XCTAssertNil(result)
        XCTAssertTrue(journal.requiresReview(username: account.username, playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected review state") }
    }

    func testCorruptRecordRequiresFreshReviewBeforePairScopedReset() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let current = playlist(mbid: id, tracks: [selected])
        let original = PlaylistItemRemovalJournal(directoryURL: directory)
        XCTAssertTrue(original.begin(username: account.username, playlistMBID: id))
        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        try Data("corrupt".utf8).write(to: file)
        let relaunched = PlaylistItemRemovalJournal(directoryURL: directory)
        let model = removalModel(
            detail: RemovalDetailProvider(values: [.success(current)]),
            provider: RemovalProviderSpy(),
            journal: relaunched
        )

        XCTAssertTrue(model.requiresRecovery(playlistMBID: id))
        XCTAssertFalse(model.resetSafetyRecord(playlistMBID: id))
        let refreshed = await model.refreshAfterReview(playlistMBID: id)
        XCTAssertNotNil(refreshed)
        XCTAssertTrue(model.canResetSafetyRecord(playlistMBID: id))
        XCTAssertTrue(model.resetSafetyRecord(playlistMBID: id))
        XCTAssertFalse(model.requiresReview(playlistMBID: id))
    }

    func testDefiniteProviderRejectionClearsBarrier() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let transport = RemovalProviderSpy(error: PlaylistMutationProviderError.rejected)
        let model = removalModel(
            detail: RemovalDetailProvider(values: [.success(before)]),
            provider: transport
        )

        let returned = await model.remove(selected, from: before)
        let callCount = await transport.callCount()
        XCTAssertNil(returned)
        XCTAssertFalse(model.requiresReview(playlistMBID: id))
        XCTAssertEqual(callCount, 1)
        guard case .failed = model.notice else { return XCTFail("Expected definite failure") }
    }

    func testCanonicalRefreshFailureRetainsBarrier() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let model = removalModel(
            detail: RemovalDetailProvider(values: [.success(before), .failure(RemovalFixtureError.failed)]),
            provider: RemovalProviderSpy())
        let returned = await model.remove(selected, from: before)
        XCTAssertNil(returned)
        XCTAssertTrue(model.requiresReview(playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected review notice") }
    }

    func testPreflightAccessLossProducesStructuredOutcome() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let provider = RemovalDetailProvider(values: [.failure(PlaylistMutationProviderError.playlistUnavailable)])
        let mutationJournal = PlaylistMutationJournal()
        let model = removalModel(
            detail: provider,
            provider: RemovalProviderSpy(),
            mutationJournal: mutationJournal
        )
        let returned = await model.remove(selected, from: before)
        XCTAssertNil(returned)
        guard case .accessLost = model.notice else { return XCTFail("Expected access-loss outcome") }
        guard case .accessLoss(let event) = mutationJournal.entries(after: 0).first?.event else {
            return XCTFail("Expected a cross-tab access-loss event")
        }
        XCTAssertEqual(event.viewerUsername, "listener")
        XCTAssertEqual(event.sourceMBID, id)
        XCTAssertEqual(event.reason, .sourceVisibility)
    }

    func testPostDispatchAmbiguityUsesOneCallAndRetainsBarrier() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let transport = RemovalProviderSpy(error: PlaylistMutationProviderError.indeterminateRemoval)
        let model = removalModel(detail: RemovalDetailProvider(values: [.success(before)]), provider: transport)
        let returned = await model.remove(selected, from: before)
        let calls = await transport.callCount()
        XCTAssertEqual(returned, before)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.requiresReview(playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected review notice") }
    }

    func testMutationPermissionLossKeepsFreshReadablePlaylist() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let readable = playlist(
            mbid: id,
            creator: "someone-else",
            tracks: [selected]
        )
        let transport = RemovalProviderSpy(error: PlaylistMutationProviderError.notCollaborator)
        let model = removalModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(readable)]),
            provider: transport
        )

        let returned = await model.remove(selected, from: before)

        XCTAssertEqual(returned, readable)
        XCTAssertFalse(model.requiresReview(playlistMBID: id))
        XCTAssertFalse(model.canAttemptRemoval(from: readable))
        guard case .failed = model.notice else { return XCTFail("Expected permission failure") }
    }

    func testMutationPermissionLossPurgesOnlyWhenReadInspectionConfirmsAccessLoss() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let transport = RemovalProviderSpy(error: PlaylistMutationProviderError.notCollaborator)
        let model = removalModel(
            detail: RemovalDetailProvider(values: [
                .success(before),
                .failure(MediaDetailError.playlistUnavailable),
            ]),
            provider: transport
        )

        let returned = await model.remove(selected, from: before)
        XCTAssertNil(returned)
        XCTAssertFalse(model.requiresReview(playlistMBID: id))
        guard case .accessLost = model.notice else { return XCTFail("Expected confirmed access loss") }
    }

    func testMutationPermissionLossKeepsBarrierWhenReadInspectionIsInconclusive() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let transport = RemovalProviderSpy(error: PlaylistMutationProviderError.notCollaborator)
        let model = removalModel(
            detail: RemovalDetailProvider(values: [
                .success(before),
                .failure(RemovalFixtureError.failed),
            ]),
            provider: transport
        )

        let returned = await model.remove(selected, from: before)

        XCTAssertEqual(returned, before)
        XCTAssertTrue(model.requiresReview(playlistMBID: id))
        XCTAssertFalse(model.canAttemptRemoval(from: before))
        guard case .needsReview = model.notice else { return XCTFail("Expected review notice") }
    }

    func testConcurrentScenesShareReservationAndProduceOnePost() async {
        let id = UUID()
        let selected = track(position: 1, title: "First")
        let before = playlist(mbid: id, tracks: [selected])
        let journal = PlaylistItemRemovalJournal()
        let transport = RemovalProviderSpy(error: PlaylistMutationProviderError.indeterminateRemoval)
        let one = removalModel(
            detail: RemovalDetailProvider(values: [.success(before)]), provider: transport, journal: journal)
        let two = removalModel(
            detail: RemovalDetailProvider(values: [.success(before)]), provider: transport, journal: journal)
        async let first: PlaylistDetail? = one.remove(selected, from: before)
        await Task.yield()
        async let second: PlaylistDetail? = two.remove(selected, from: before)
        _ = await (first, second)
        let calls = await transport.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testReorderUsesPreflightPostAndExactCanonicalOrder() async {
        let id = UUID()
        let one = track(position: 1, title: "One")
        let two = track(position: 2, title: "Two")
        let three = track(position: 3, title: "Three")
        let before = playlist(mbid: id, tracks: [one, two, three])
        let canonical = playlist(mbid: id, tracks: [reposition(two, to: 1), reposition(three, to: 2), reposition(one, to: 3)])
        let provider = ReorderProviderSpy()
        let detail = RemovalDetailProvider(values: [.success(before), .success(canonical)])
        let model = reorderModel(detail: detail, provider: provider)

        let result = await model.save(baseline: before, from: 0, to: 2)

        XCTAssertEqual(result, canonical)
        let reads = await detail.callCount()
        XCTAssertEqual(reads, 2)
        let calls = await provider.calls()
        XCTAssertEqual(calls.map { "\($0.0.uuidString):\($0.1):\($0.2):\($0.3.uuidString)" }, ["\(one.recording.identity.mbid!.uuidString):0:2:\(id.uuidString)"])
        XCTAssertFalse(model.canAttemptReorder(canonical) == false)
        XCTAssertEqual(model.notice, .confirmed)
    }

    func testReorderStaleWholeSequenceSendsZeroPost() async {
        let id = UUID()
        let before = playlist(mbid: id, tracks: [track(position: 1, title: "One"), track(position: 2, title: "Two")])
        let changed = playlist(mbid: id, tracks: [track(position: 1, title: "Other"), before.tracks[1]])
        let provider = ReorderProviderSpy()
        let model = reorderModel(detail: RemovalDetailProvider(values: [.success(changed)]), provider: provider)
        let result = await model.save(baseline: before, from: 0, to: 1)
        let calls = await provider.calls()
        XCTAssertEqual(result, changed)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(model.notice, .stale)
    }

    func testRemovalAndReorderShareOneReservation() async {
        let id = UUID()
        let first = track(position: 1, title: "One")
        let second = track(position: 2, title: "Two")
        let before = playlist(mbid: id, tracks: [first, second])
        let journal = PlaylistItemMutationJournal()
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: id))
        let reorder = reorderModel(detail: RemovalDetailProvider(values: [.success(before)]), provider: ReorderProviderSpy(), journal: journal)
        let removal = removalModel(detail: RemovalDetailProvider(values: [.success(before)]), provider: RemovalProviderSpy(), journal: journal)
        let reordered = await reorder.save(baseline: before, from: 0, to: 1)
        let removed = await removal.remove(first, from: before)
        XCTAssertNil(reordered)
        XCTAssertNil(removed)
    }

    func testReorderNoOpAndUnmappedPlaylistDispatchNothing() async {
        let id = UUID()
        let mapped = track(position: 1, title: "Mapped")
        let other = track(position: 2, title: "Other")
        let mappedPlaylist = playlist(mbid: id, tracks: [mapped, other])
        let noOpProvider = ReorderProviderSpy()
        let noOpModel = reorderModel(
            detail: RemovalDetailProvider(values: [.success(mappedPlaylist)]),
            provider: noOpProvider
        )

        let noOpResult = await noOpModel.save(baseline: mappedPlaylist, from: 0, to: 0)
        let noOpCalls = await noOpProvider.calls()
        XCTAssertNil(noOpResult)
        XCTAssertTrue(noOpCalls.isEmpty)

        let unmapped = PlaylistTrack(
            position: 1,
            recording: Recording(
                identity: .init(mbid: nil, msid: UUID()),
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
            addedAt: nil,
            addedBy: nil
        )
        let unmappedPlaylist = playlist(
            mbid: UUID(),
            tracks: [unmapped, reposition(other, to: 2)]
        )
        let unmappedProvider = ReorderProviderSpy()
        let unmappedModel = reorderModel(
            detail: RemovalDetailProvider(values: [.success(unmappedPlaylist)]),
            provider: unmappedProvider
        )

        XCTAssertFalse(unmappedModel.canAttemptReorder(unmappedPlaylist))
        let unmappedResult = await unmappedModel.save(baseline: unmappedPlaylist, from: 0, to: 1)
        let unmappedCalls = await unmappedProvider.calls()
        XCTAssertNil(unmappedResult)
        XCTAssertTrue(unmappedCalls.isEmpty)
    }

    func testReorderDefiniteRejectionClearsBarrierWithoutPostflight() async {
        let id = UUID()
        let before = playlist(
            mbid: id,
            tracks: [track(position: 1, title: "One"), track(position: 2, title: "Two")]
        )
        let journal = PlaylistItemMutationJournal()
        let provider = ReorderProviderSpy(error: PlaylistMutationProviderError.reorderRejected)
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [.success(before)]),
            provider: provider,
            journal: journal
        )

        let result = await model.save(baseline: before, from: 0, to: 1)
        let calls = await provider.calls()
        XCTAssertNil(result)
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(journal.requiresReview(username: account.username, playlistMBID: id))
        guard case .failed = model.notice else { return XCTFail("Expected a definite failure") }
    }

    func testReorderRateLimitClearsBarrierWithoutPostflight() async {
        let id = UUID()
        let before = playlist(
            mbid: id,
            tracks: [track(position: 1, title: "One"), track(position: 2, title: "Two")]
        )
        let journal = PlaylistItemMutationJournal()
        let detail = RemovalDetailProvider(values: [.success(before)])
        let model = reorderModel(
            detail: detail,
            provider: ReorderProviderSpy(error: ProviderError.rateLimited(retryAfterSeconds: 7)),
            journal: journal
        )

        let result = await model.save(baseline: before, from: 0, to: 1)

        let reads = await detail.callCount()
        XCTAssertNil(result)
        XCTAssertEqual(reads, 1)
        XCTAssertFalse(journal.requiresReview(username: account.username, playlistMBID: id))
        XCTAssertEqual(
            model.notice,
            .failed("ListenBrainz is busy. Try again in about 7 seconds.")
        )
    }

    func testReorderRejectsMismatchedPreflightPlaylistIdentityWithoutPost() async {
        let id = UUID()
        let before = playlist(
            mbid: id,
            tracks: [track(position: 1, title: "One"), track(position: 2, title: "Two")]
        )
        let wrongPlaylist = playlist(mbid: UUID(), tracks: before.tracks)
        let provider = ReorderProviderSpy()
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [.success(wrongPlaylist)]),
            provider: provider
        )

        let result = await model.save(baseline: before, from: 0, to: 1)

        let calls = await provider.calls()
        XCTAssertEqual(result, wrongPlaylist)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(model.notice, .stale)
    }

    func testReorderRejectsMismatchedPostflightPlaylistIdentityAndRetainsBarrier() async {
        let id = UUID()
        let one = track(position: 1, title: "One")
        let two = track(position: 2, title: "Two")
        let before = playlist(mbid: id, tracks: [one, two])
        let wrongCanonical = playlist(
            mbid: UUID(),
            tracks: [reposition(two, to: 1), reposition(one, to: 2)]
        )
        let journal = PlaylistItemMutationJournal()
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(wrongCanonical)]),
            provider: ReorderProviderSpy(),
            journal: journal
        )

        let result = await model.save(baseline: before, from: 0, to: 1)

        XCTAssertEqual(result, wrongCanonical)
        XCTAssertTrue(journal.requiresReview(username: account.username, playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected review state") }
    }

    func testReorderAmbiguousResponseCanConfirmOnlyThroughExactPostflight() async {
        let id = UUID()
        let one = track(position: 1, title: "One")
        let two = track(position: 2, title: "Two")
        let before = playlist(mbid: id, tracks: [one, two])
        let canonical = playlist(mbid: id, tracks: [reposition(two, to: 1), reposition(one, to: 2)])
        let journal = PlaylistItemMutationJournal()
        let provider = ReorderProviderSpy(error: PlaylistMutationProviderError.indeterminateReorder)
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(canonical)]),
            provider: provider,
            journal: journal
        )

        let result = await model.save(baseline: before, from: 0, to: 1)

        XCTAssertEqual(result, canonical)
        XCTAssertEqual(model.notice, .confirmed)
        XCTAssertFalse(journal.requiresReview(username: account.username, playlistMBID: id))
    }

    func testReorderPartialServerResultRetainsBarrierAndNeverClaimsSuccess() async {
        let id = UUID()
        let one = track(position: 1, title: "One")
        let two = track(position: 2, title: "Two")
        let three = track(position: 3, title: "Three")
        let before = playlist(mbid: id, tracks: [one, two, three])
        let partiallyDeleted = playlist(
            mbid: id,
            tracks: [reposition(two, to: 1), reposition(three, to: 2)]
        )
        let journal = PlaylistItemMutationJournal()
        let provider = ReorderProviderSpy(error: PlaylistMutationProviderError.indeterminateReorder)
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(partiallyDeleted)]),
            provider: provider,
            journal: journal
        )

        let result = await model.save(baseline: before, from: 0, to: 2)

        XCTAssertEqual(result, partiallyDeleted)
        XCTAssertTrue(journal.requiresReview(username: account.username, playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected review state") }
    }

    func testReorderPermissionLossWithReadablePlaylistClearsBarrierAndDisablesAnotherMove() async {
        let id = UUID()
        let one = track(position: 1, title: "One")
        let two = track(position: 2, title: "Two")
        let before = playlist(mbid: id, tracks: [one, two])
        let readable = playlist(mbid: id, creator: "someone-else", tracks: [one, two])
        let journal = PlaylistItemMutationJournal()
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(readable)]),
            provider: ReorderProviderSpy(error: PlaylistMutationProviderError.notCollaborator),
            journal: journal
        )

        let result = await model.save(baseline: before, from: 0, to: 1)

        XCTAssertEqual(result, readable)
        XCTAssertFalse(journal.requiresReview(username: account.username, playlistMBID: id))
        XCTAssertFalse(model.canAttemptReorder(readable))
        guard case .failed = model.notice else { return XCTFail("Expected permission failure") }
    }

    func testReorderPermissionLossWithMismatchedInspectionRetainsBarrier() async {
        let id = UUID()
        let one = track(position: 1, title: "One")
        let two = track(position: 2, title: "Two")
        let before = playlist(mbid: id, tracks: [one, two])
        let wrongPlaylist = playlist(mbid: UUID(), creator: "someone-else", tracks: [one, two])
        let journal = PlaylistItemMutationJournal()
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(wrongPlaylist)]),
            provider: ReorderProviderSpy(error: PlaylistMutationProviderError.notCollaborator),
            journal: journal
        )

        let result = await model.save(baseline: before, from: 0, to: 1)

        XCTAssertEqual(result, before)
        XCTAssertTrue(journal.requiresReview(username: account.username, playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected review state") }
    }

    func testReorderPostflightAccessLossRetainsBarrierAndPublishesPurgeEvent() async {
        let id = UUID()
        let one = track(position: 1, title: "One")
        let two = track(position: 2, title: "Two")
        let before = playlist(mbid: id, tracks: [one, two])
        let journal = PlaylistItemMutationJournal()
        let mutationJournal = PlaylistMutationJournal()
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [
                .success(before),
                .failure(PlaylistMutationProviderError.playlistUnavailable),
            ]),
            provider: ReorderProviderSpy(),
            journal: journal,
            mutationJournal: mutationJournal
        )

        let result = await model.save(baseline: before, from: 0, to: 1)

        XCTAssertNil(result)
        XCTAssertTrue(journal.requiresReview(username: account.username, playlistMBID: id))
        guard case .accessLost = model.notice else { return XCTFail("Expected access-loss outcome") }
        guard case .accessLoss(let event) = mutationJournal.entries(after: 0).first?.event else {
            return XCTFail("Expected a cross-tab access-loss event")
        }
        XCTAssertEqual(event.sourceMBID, id)
        XCTAssertEqual(event.viewerUsername, "listener")
    }

    func testReorderRecoveryOfDifferentPlaylistRetainsBarrier() async {
        let id = UUID()
        let journal = PlaylistItemMutationJournal()
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: id))
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [
                .success(playlist(mbid: UUID(), tracks: [
                    track(position: 1, title: "One"),
                    track(position: 2, title: "Two"),
                ]))
            ]),
            provider: ReorderProviderSpy(),
            journal: journal
        )

        let result = await model.refreshAfterReview(playlistMBID: id)

        XCTAssertNil(result)
        XCTAssertTrue(journal.requiresReview(username: account.username, playlistMBID: id))
        guard case .needsReview = model.notice else { return XCTFail("Expected review state") }
    }

    func testReorderExactDuplicateFingerprintsAreObservationallyEquivalent() async {
        let id = UUID()
        let duplicateMBID = UUID()
        let first = track(position: 1, title: "First display title", mbid: duplicateMBID)
        let second = track(position: 2, title: "Second display title", mbid: duplicateMBID)
        let before = playlist(mbid: id, tracks: [first, second])
        let canonical = playlist(mbid: id, tracks: [reposition(first, to: 1), reposition(second, to: 2)])
        let model = reorderModel(
            detail: RemovalDetailProvider(values: [.success(before), .success(canonical)]),
            provider: ReorderProviderSpy()
        )

        let result = await model.save(baseline: before, from: 0, to: 1)

        XCTAssertEqual(result, canonical)
        XCTAssertEqual(model.notice, .confirmed)
    }

    private func removalModel(
        detail: any PlaylistDetailProviding,
        provider: any PlaylistItemRemovalProviding,
        journal: PlaylistItemRemovalJournal = .init(),
        mutationJournal: PlaylistMutationJournal = .init()
    ) -> PlaylistItemRemovalModel {
        .init(
            account: account,
            detailProvider: detail,
            provider: provider,
            journal: journal,
            mutationJournal: mutationJournal
        )
    }
    private func reorderModel(
        detail: any PlaylistDetailProviding,
        provider: any PlaylistItemReorderingProviding,
        journal: PlaylistItemMutationJournal = .init(),
        mutationJournal: PlaylistMutationJournal = .init()
    ) -> PlaylistItemReorderModel {
        .init(
            account: account,
            detailProvider: detail,
            provider: provider,
            journal: journal,
            mutationJournal: mutationJournal
        )
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "playlist-removal-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func playlist(
        mbid: UUID = UUID(), creator: String = "listener", collaborators: [String] = [], tracks: [PlaylistTrack] = []
    ) -> PlaylistDetail {
        .init(
            mbid: mbid, title: "Playlist", creator: creator, annotation: nil, createdAt: nil, lastModifiedAt: nil,
            isPublic: true, createdFor: nil, collaborators: collaborators, copiedFrom: nil, tracks: tracks)
    }
    private func track(position: Int, title: String, mbid: UUID = UUID()) -> PlaylistTrack {
        .init(
            position: position,
            recording: .init(
                identity: .init(mbid: mbid, msid: nil), title: title, artistName: "Artist", artistMBIDs: [],
                releaseTitle: nil, releaseMBID: nil, releaseGroupMBID: nil, artworkReleaseMBID: nil,
                durationMilliseconds: nil, source: nil), addedAt: nil, addedBy: nil)
    }
    private func reposition(_ track: PlaylistTrack, to position: Int) -> PlaylistTrack {
        .init(position: position, recording: track.recording, addedAt: track.addedAt, addedBy: track.addedBy)
    }
}

private actor RemovalDetailProvider: PlaylistDetailProviding {
    private var values: [Result<PlaylistDetail, any Error & Sendable>]
    private var requests = 0
    init(values: [Result<PlaylistDetail, any Error & Sendable>]) { self.values = values }
    func playlist(mbid: UUID) async throws -> PlaylistDetail { try next() }
    func playlistForMutationInspection(mbid: UUID) async throws -> PlaylistDetail { try next() }
    private func next() throws -> PlaylistDetail {
        requests += 1
        guard !values.isEmpty else { throw RemovalFixtureError.failed }
        return try values.removeFirst().get()
    }
    func callCount() -> Int { requests }
}

private actor RemovalProviderSpy: PlaylistItemRemovalProviding {
    private let error: (any Error & Sendable)?
    private var calls = 0
    init(error: (any Error & Sendable)? = nil) { self.error = error }
    func removeItem(at index: Int, from playlistMBID: UUID) async throws {
        calls += 1
        if let error { throw error }
    }
    func callCount() -> Int { calls }
}

private actor ReorderProviderSpy: PlaylistItemReorderingProviding {
    private let error: (any Error & Sendable)?
    private var recorded: [(UUID, Int, Int, UUID)] = []
    init(error: (any Error & Sendable)? = nil) { self.error = error }
    func moveItem(recordingMBID: UUID, from: Int, to: Int, in playlistMBID: UUID) async throws {
        recorded.append((recordingMBID, from, to, playlistMBID))
        if let error { throw error }
    }
    func calls() -> [(UUID, Int, Int, UUID)] { recorded }
}

private enum RemovalFixtureError: LocalizedError, Sendable {
    case failed
    var errorDescription: String? { "Fixture inspection failed." }
}
