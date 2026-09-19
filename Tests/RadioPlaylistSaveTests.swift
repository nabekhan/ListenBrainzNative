import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class RadioPlaylistSaveTests: XCTestCase {
    func testProviderSendsOneNormalizedPrivatePayloadInRadioOrderIncludingDuplicates() async throws {
        let first = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let second = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let transport = RadioPlaylistSaveTransportSpy()
        let provider = ListenBrainzRadioPlaylistSaveProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        _ = try await provider.save(
            metadata: .init(
                title: "  Radio at night  ",
                annotation: "  Keep the repeats.  ",
                isPublic: true,
                collaborators: ["friend"]
            ),
            recordingMBIDs: [first, second, first],
            ownerUsername: "listener"
        )

        let calls = await transport.calls()
        XCTAssertEqual(
            calls,
            [
                .init(
                    metadata: .init(
                        title: "Radio at night", annotation: "Keep the repeats.", isPublic: false, collaborators: []),
                    recordingMBIDs: [first, second, first]
                )
            ])
    }

    func testMixGatingKeepsOnlyCanonicalMBIDsAndPreservesOccurrences() {
        let first = UUID()
        let second = UUID()
        let mix = fixtureMix(mbids: [first, nil, second, first])
        XCTAssertEqual(RadioPlaylistSaveModel.recordingMBIDs(in: mix), [first, second, first])
        XCTAssertEqual(RadioPlaylistSaveModel.excludedTrackCount(in: mix), 1)
        XCTAssertTrue(RadioPlaylistSaveModel.recordingMBIDs(in: fixtureMix(mbids: [nil])).isEmpty)
    }

    func testDuplicateSaveTapMakesOneRequestAndBuildsPrivateDestination() async {
        let id = UUID()
        let provider = RadioPlaylistSaveProviderSpy(delay: .milliseconds(30), createdID: id)
        let model = RadioPlaylistSaveModel(account: account, provider: provider, journal: .init())
        let mix = fixtureMix(mbids: [UUID(), nil])

        async let first: Void = model.save(mix)
        await Task.yield()
        async let second: Void = model.save(mix)
        _ = await (first, second)

        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
        guard case .saved(let playlist) = model.notice else { return XCTFail("Expected saved notice") }
        XCTAssertFalse(playlist.isPublic)
        XCTAssertEqual(playlist.playlistMBID, id)
        XCTAssertFalse(model.requiresReview)
    }

    func testDefiniteRejectionClearsBarrierAndReportsFailure() async {
        let model = RadioPlaylistSaveModel(
            account: account,
            provider: RadioPlaylistSaveProviderSpy(error: PlaylistMutationProviderError.rejected),
            journal: .init()
        )
        await model.save(fixtureMix(mbids: [UUID()]))
        XCTAssertFalse(model.requiresReview)
        guard case .failed = model.notice else { return XCTFail("Expected definite failure") }
    }

    func testCancellationBeforeTransportAdmissionClearsBarrier() async {
        let blocker = GateBlocker()
        let gate = RequestGate(minimumInterval: .zero)
        let blockingTask = Task {
            try await gate.perform { await blocker.run() }
        }
        while !(await blocker.started()) { await Task.yield() }
        let transport = RadioPlaylistSaveTransportSpy()
        let provider = ListenBrainzRadioPlaylistSaveProvider(
            transport: transport,
            gate: gate
        )
        let model = RadioPlaylistSaveModel(account: account, provider: provider, journal: .init())
        let task = Task { await model.save(fixtureMix(mbids: [UUID()])) }
        while await gate.queuedRequestCountForTesting() == 0 { await Task.yield() }
        task.cancel()
        await task.value
        await blocker.release()
        _ = try? await blockingTask.value
        XCTAssertFalse(model.requiresReview)
        XCTAssertNil(model.notice)
        let calls = await transport.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testCancellationAfterDispatchRequiresDurableReviewAcrossRelaunch() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = RadioPlaylistSaveJournal(directoryURL: directory)
        let transport = RadioPlaylistSaveCancellationTransport()
        let provider = ListenBrainzRadioPlaylistSaveProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let model = RadioPlaylistSaveModel(account: account, provider: provider, journal: journal)
        let task = Task { await model.save(fixtureMix(mbids: [UUID()])) }
        for _ in 0..<20 {
            if await transport.started() { break }
            await Task.yield()
        }
        task.cancel()
        await task.value

        XCTAssertTrue(model.requiresReview)
        guard case .needsReview = model.notice else { return XCTFail("Expected review notice") }
        let reopened = RadioPlaylistSaveJournal(directoryURL: directory)
        XCTAssertTrue(reopened.requiresReview(username: account.username))
    }

    func testTransportFailureKeepsDurableBarrierAcrossRelaunch() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = RadioPlaylistSaveModel(
            account: account,
            provider: RadioPlaylistSaveProviderSpy(error: FixtureError.transportLost),
            journal: RadioPlaylistSaveJournal(directoryURL: directory)
        )

        await model.save(fixtureMix(mbids: [UUID()]))

        guard case .needsReview = model.notice else { return XCTFail("Expected review notice") }
        let reopened = RadioPlaylistSaveJournal(directoryURL: directory)
        XCTAssertTrue(reopened.requiresReview(username: account.username))
    }

    func testMalformedCreateResponseKeepsDurableBarrier() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = ListenBrainzRadioPlaylistSaveProvider(
            transport: ThrowingRadioPlaylistSaveTransport(error: LBError.invalidResponse),
            gate: RequestGate(minimumInterval: .zero)
        )
        let model = RadioPlaylistSaveModel(
            account: account,
            provider: provider,
            journal: RadioPlaylistSaveJournal(directoryURL: directory)
        )

        await model.save(fixtureMix(mbids: [UUID()]))

        XCTAssertTrue(model.requiresReview)
        guard case .needsReview = model.notice else { return XCTFail("Expected review notice") }
    }

    func testCorruptBarrierFailsClosedUntilFreshReviewAndExplicitReset() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = RadioPlaylistSaveJournal(directoryURL: directory)
        XCTAssertTrue(journal.begin(username: account.username, at: .now))
        let recordURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        try Data("not-json".utf8).write(to: recordURL)

        let reopened = RadioPlaylistSaveJournal(directoryURL: directory)
        XCTAssertTrue(reopened.requiresReview(username: account.username))
        XCTAssertTrue(reopened.requiresRecovery(username: account.username))
        XCTAssertFalse(reopened.begin(username: account.username, at: .now))

        let profile = ProfilePlaylistsProviderSpy()
        let model = RadioPlaylistSaveModel(
            account: account,
            provider: RadioPlaylistSaveProviderSpy(),
            profileProvider: profile,
            journal: reopened
        )
        await model.reviewOwnedPlaylists()
        XCTAssertTrue(model.canResetAfterReview)
        model.resetAfterReview()
        XCTAssertFalse(model.requiresReview)
        XCTAssertFalse(model.requiresStorageRecovery)
    }

    func testDurableBarrierIsScopedToNormalizedAccount() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = RadioPlaylistSaveJournal(directoryURL: directory)

        XCTAssertTrue(journal.begin(username: " Listener ", at: .now))
        XCTAssertTrue(journal.requiresReview(username: "listener"))
        XCTAssertFalse(journal.requiresReview(username: "someone-else"))
        XCTAssertFalse(journal.begin(username: "LISTENER", at: .now))
    }

    func testUnwritableBarrierPreventsTransport() async throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let blockedDirectory = parent.appending(path: "not-a-directory")
        try Data("file".utf8).write(to: blockedDirectory)
        let provider = RadioPlaylistSaveProviderSpy()
        let model = RadioPlaylistSaveModel(
            account: account,
            provider: provider,
            journal: RadioPlaylistSaveJournal(directoryURL: blockedDirectory)
        )

        await model.save(fixtureMix(mbids: [UUID()]))

        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(model.requiresReview)
        XCTAssertTrue(model.requiresStorageRecovery)
        guard case .needsReview = model.notice else { return XCTFail("Expected fail-closed notice") }
    }

    func testOwnedPlaylistReviewThenExplicitResetAllowsAnotherSave() async {
        let journal = RadioPlaylistSaveJournal()
        journal.begin(username: account.username, at: .now)
        let profile = ProfilePlaylistsProviderSpy()
        let model = RadioPlaylistSaveModel(
            account: account,
            provider: RadioPlaylistSaveProviderSpy(),
            profileProvider: profile,
            journal: journal
        )
        XCTAssertTrue(model.requiresReview)
        await model.reviewOwnedPlaylists()
        XCTAssertTrue(model.canResetAfterReview)
        XCTAssertEqual(model.reviewedPlaylists.map(\.title), ["Newest private mix"])
        let reviewCallCount = await profile.callCount()
        XCTAssertEqual(reviewCallCount, 1)
        let freshCallCount = await profile.freshCallCount()
        XCTAssertEqual(freshCallCount, 1)
        model.resetAfterReview()
        XCTAssertFalse(model.requiresReview)
    }

    func testConfirmedSaveInvalidatesDetailAndProfileCaches() async throws {
        let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let key = PlaylistDetailCacheKey(mbid: UUID(), accessScope: .publicOnly)
        await detailCache.save(
            .init(
                mbid: key.mbid,
                title: "Cached playlist",
                creator: "listener",
                annotation: nil,
                createdAt: nil,
                lastModifiedAt: nil,
                isPublic: true,
                createdFor: nil,
                collaborators: [],
                copiedFrom: nil,
                tracks: []
            ),
            for: key
        )
        let pageKey = ProfilePlaylistPageKey(
            username: "listener", accessScope: .publicOnly, category: .owned, offset: 0, count: 20)
        await pageCache.save(
            .init(username: "listener", category: .owned, playlists: [], requestedCount: 20, offset: 0, totalCount: 0),
            for: pageKey)
        let provider = ListenBrainzRadioPlaylistSaveProvider(
            transport: RadioPlaylistSaveTransportSpy(),
            gate: RequestGate(minimumInterval: .zero),
            detailCache: detailCache,
            profilePageCache: pageCache
        )
        _ = try await provider.save(
            metadata: .init(title: "Saved mix"), recordingMBIDs: [UUID()], ownerUsername: "listener")
        let cachedDetail = await detailCache.value(for: key)
        let cachedPage = await pageCache.value(for: pageKey)
        XCTAssertNil(cachedDetail)
        XCTAssertNil(cachedPage)
    }

    private var account: Account { .init(username: "listener", token: "fixture-token") }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "RadioPlaylistSaveTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func fixtureMix(mbids: [UUID?]) -> RadioMix {
        let tracks = mbids.enumerated().map { index, mbid in
            PlaylistTrack(
                position: index,
                recording: Recording(
                    identity: .init(mbid: mbid, msid: nil),
                    title: "Track \(index)",
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
        }
        return RadioMix(
            options: .init(prompt: "#ambient", mode: .easy)!,
            title: "  Generated radio  ",
            annotation: "  Night listening.  ",
            feedback: [],
            tracks: tracks,
            metadataEnrichmentFailed: false,
            generatedAt: .now
        )
    }
}

private actor RadioPlaylistSaveTransportSpy: RadioPlaylistSaveTransport {
    struct Call: Equatable, Sendable {
        let metadata: LBPlaylistMutationMetadata
        let recordingMBIDs: [UUID]
    }
    private var values: [Call] = []
    func create(metadata: LBPlaylistMutationMetadata, recordingMBIDs: [UUID]) async throws -> UUID {
        values.append(.init(metadata: metadata, recordingMBIDs: recordingMBIDs))
        return UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!
    }
    func calls() -> [Call] { values }
}

private actor RadioPlaylistSaveProviderSpy: RadioPlaylistSaveProviding {
    private let delay: Duration
    private let createdID: UUID
    private let error: (any Error & Sendable)?
    private var values: [(PlaylistMetadataDraft, [UUID], String)] = []
    init(delay: Duration = .zero, createdID: UUID = UUID(), error: (any Error & Sendable)? = nil) {
        self.delay = delay
        self.createdID = createdID
        self.error = error
    }
    func save(metadata: PlaylistMetadataDraft, recordingMBIDs: [UUID], ownerUsername: String) async throws -> UUID {
        values.append((metadata, recordingMBIDs, ownerUsername))
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return createdID
    }
    func callCount() -> Int { values.count }
}

private actor RadioPlaylistSaveCancellationTransport: RadioPlaylistSaveTransport {
    private var didStart = false
    func create(metadata: LBPlaylistMutationMetadata, recordingMBIDs: [UUID]) async throws -> UUID {
        didStart = true
        try await Task.sleep(for: .seconds(60))
        return UUID()
    }
    func started() -> Bool { didStart }
}

private struct ThrowingRadioPlaylistSaveTransport: RadioPlaylistSaveTransport {
    let error: LBError

    func create(metadata: LBPlaylistMutationMetadata, recordingMBIDs: [UUID]) async throws -> UUID {
        throw error
    }
}

private actor ProfilePlaylistsProviderSpy: ProfilePlaylistsProviding {
    private var calls = 0
    private var freshCalls = 0
    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> ProfilePlaylistPage
    {
        calls += 1
        return .init(
            username: username, category: category, playlists: [], requestedCount: count, offset: offset, totalCount: 0)
    }

    func freshPage(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws
        -> ProfilePlaylistPage
    {
        calls += 1
        freshCalls += 1
        return .init(
            username: username,
            category: category,
            playlists: [
                SearchPlaylist(
                    title: "Newest private mix",
                    creator: username,
                    annotation: nil,
                    identifier: "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    isPublic: false,
                    lastModifiedAt: .now,
                    createdAt: .now
                )
            ],
            requestedCount: count,
            offset: offset,
            totalCount: 1
        )
    }

    func callCount() -> Int { calls }
    func freshCallCount() -> Int { freshCalls }
}

private actor GateBlocker {
    private var didStart = false
    private var continuation: CheckedContinuation<Void, Never>?

    func run() async {
        didStart = true
        await withCheckedContinuation { continuation = $0 }
    }

    func started() -> Bool { didStart }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private enum FixtureError: Error, Sendable {
    case transportLost
}
