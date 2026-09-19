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

        let relaunched = PlaylistItemRemovalJournal(directoryURL: directory)
        XCTAssertTrue(relaunched.requiresReview(username: "listener", playlistMBID: playlist))
        XCTAssertFalse(relaunched.begin(username: "listener", playlistMBID: playlist))
    }

    func testCorruptPairFailsClosedWithoutBlockingOrResettingAnotherPair() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = UUID()
        let second = UUID()
        let journal = PlaylistItemRemovalJournal(directoryURL: directory)
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: first))
        XCTAssertTrue(journal.begin(username: account.username, playlistMBID: second))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let firstFile = try XCTUnwrap(files.first { $0.lastPathComponent.contains(first.uuidString.lowercased()) })
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
    private func track(position: Int, title: String) -> PlaylistTrack {
        .init(
            position: position,
            recording: .init(
                identity: .init(mbid: UUID(), msid: nil), title: title, artistName: "Artist", artistMBIDs: [],
                releaseTitle: nil, releaseMBID: nil, releaseGroupMBID: nil, artworkReleaseMBID: nil,
                durationMilliseconds: nil, source: nil), addedAt: nil, addedBy: nil)
    }
    private func reposition(_ track: PlaylistTrack, to position: Int) -> PlaylistTrack {
        .init(position: position, recording: track.recording, addedAt: track.addedAt, addedBy: track.addedBy)
    }
}

private actor RemovalDetailProvider: PlaylistDetailProviding {
    private var values: [Result<PlaylistDetail, any Error & Sendable>]
    init(values: [Result<PlaylistDetail, any Error & Sendable>]) { self.values = values }
    func playlist(mbid: UUID) async throws -> PlaylistDetail { try next() }
    func playlistForMutationInspection(mbid: UUID) async throws -> PlaylistDetail { try next() }
    private func next() throws -> PlaylistDetail {
        guard !values.isEmpty else { throw RemovalFixtureError.failed }
        return try values.removeFirst().get()
    }
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

private enum RemovalFixtureError: LocalizedError, Sendable {
    case failed
    var errorDescription: String? { "Fixture inspection failed." }
}
