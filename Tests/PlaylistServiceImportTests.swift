import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

private let primaryPlaylistServiceImportItem = PlaylistServiceImportItem(
    service: .spotify,
    externalID: "4NHQUGzhtTLFvgF5SZesLK",
    title: "Soft focus",
    summary: nil,
    artworkURL: nil,
    ownerName: "listener",
    trackCount: 42,
    isPublic: false,
    isCollaborative: false
)

@MainActor
final class PlaylistServiceImportModelTests: XCTestCase {
    private let importedMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    func testLoadingIsExplicitAndSearchNeverStartsAnotherRead() async {
        let provider = PlaylistServiceImportFixtureProvider(mode: .success)
        let model = makeModel(provider: provider)

        XCTAssertEqual(model.phase, .idle)
        var listCallCount = await provider.listCallCount()
        XCTAssertEqual(listCallCount, 0)

        await model.load()
        model.searchText = "prairie"
        XCTAssertEqual(model.filteredPlaylists.map(\.title), ["Prairie drives"])
        await model.load()

        listCallCount = await provider.listCallCount()
        let importCallCount = await provider.importCallCount()
        XCTAssertEqual(listCallCount, 1)
        XCTAssertEqual(importCallCount, 0)
    }

    func testFreshAccountScopedCacheServesASecondModelWithoutAnotherRead() async {
        let provider = PlaylistServiceImportFixtureProvider(mode: .success)
        let cache = EntityDetailCache<PlaylistServiceImportCacheKey, PlaylistServiceImportList>(
            timeToLive: 600,
            maximumEntryCount: 4
        )
        let scope = RequestGate.ReadScope.isolated()
        let account = Account(username: "listener", token: "token")
        let first = PlaylistServiceImportModel(
            account: account,
            scope: scope,
            provider: provider,
            cache: cache,
            journal: .init()
        )
        let second = PlaylistServiceImportModel(
            account: account,
            scope: scope,
            provider: provider,
            cache: cache,
            journal: .init()
        )

        await first.load()
        await second.load()

        let callCount = await provider.listCallCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(second.loadedList?.playlists.count, 2)
    }

    func testMissingSpotifyPermissionsHaveActionableRecoveryCopy() async {
        let provider = PlaylistServiceImportFixtureProvider(mode: .listBadRequest)
        let model = makeModel(provider: provider)

        await model.load()

        guard case let .failed(message) = model.phase else {
            return XCTFail("Expected a list failure")
        }
        XCTAssertTrue(message.contains("Reconnect Spotify"))
        let callCount = await provider.listCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testConfirmedImportKeepsBarrierUntilResultIsAcknowledged() async {
        let provider = PlaylistServiceImportFixtureProvider(mode: .success)
        let journal = PlaylistServiceImportJournal()
        let model = makeModel(provider: provider, journal: journal)
        let playlist = primaryPlaylistServiceImportItem

        await model.importPlaylist(playlist)

        XCTAssertTrue(model.requiresReview(for: playlist))
        guard case let .confirmed(_, confirmed, playlistMBID) = model.notice else {
            return XCTFail("Expected confirmed import")
        }
        XCTAssertEqual(confirmed, playlist)
        XCTAssertEqual(playlistMBID, importedMBID)
        let callCount = await provider.importCallCount()
        XCTAssertEqual(callCount, 1)

        XCTAssertTrue(model.acknowledgeConfirmedImport(playlist))
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.requiresReview(for: playlist))
    }

    func testConfirmedImportStaysVisibleWhenBarrierCannotBeCleared() async throws {
        let root = temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: root.path()
            )
            try? FileManager.default.removeItem(at: root)
        }
        let journal = PlaylistServiceImportJournal(directoryURL: root)
        let model = makeModel(
            provider: PlaylistServiceImportFixtureProvider(mode: .success),
            journal: journal
        )

        await model.importPlaylist(primaryPlaylistServiceImportItem)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: root.path()
        )

        XCTAssertFalse(model.acknowledgeConfirmedImport(primaryPlaylistServiceImportItem))
        guard case let .confirmedRecoveryNeeded(_, playlist, message) = model.notice else {
            return XCTFail("Expected confirmed import recovery guidance")
        }
        XCTAssertEqual(playlist, primaryPlaylistServiceImportItem)
        XCTAssertTrue(message.contains("was added"))
        XCTAssertFalse(message.contains("didn’t import"))
        XCTAssertTrue(model.requiresReview(for: primaryPlaylistServiceImportItem))

        model.acknowledgeConfirmedRecoveryNotice()
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.requiresReview(for: primaryPlaylistServiceImportItem))
    }

    func testConcurrentAndCooldownRefreshesDoNotAmplifyListingRequests() async {
        let provider = SuspendingListPlaylistServiceImportProvider()
        let model = PlaylistServiceImportModel(
            account: .init(username: "listener", token: "secret-token"),
            provider: provider,
            cache: EntityDetailCache(),
            journal: .init(),
            refreshCooldown: .seconds(30)
        )
        let first = Task { await model.load() }
        while !(await provider.started()) { await Task.yield() }

        await model.refresh()
        XCTAssertTrue(model.isListing)
        var callCount = await provider.listCallCount()
        XCTAssertEqual(callCount, 1)

        await provider.finish()
        await first.value
        XCTAssertFalse(model.isListing)
        XCTAssertTrue(model.isRefreshCoolingDown)

        await model.refresh()
        callCount = await provider.listCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testStorageFailurePreventsImportDispatch() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileInsteadOfDirectory = root.appending(path: "occupied")
        try Data("not a directory".utf8).write(to: fileInsteadOfDirectory)
        let provider = PlaylistServiceImportFixtureProvider(mode: .success)
        let model = makeModel(
            provider: provider,
            journal: PlaylistServiceImportJournal(directoryURL: fileInsteadOfDirectory)
        )

        await model.importPlaylist(primaryPlaylistServiceImportItem)

        let callCount = await provider.importCallCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(model.requiresReview(for: primaryPlaylistServiceImportItem))
        guard case let .failed(_, message) = model.notice else {
            return XCTFail("Expected safe storage failure")
        }
        XCTAssertTrue(message.contains("didn’t start"))
    }

    func testIndeterminateImportBlocksAutomaticAndManualReplayUntilReview() async {
        let provider = PlaylistServiceImportFixtureProvider(mode: .indeterminate)
        let model = makeModel(provider: provider)

        await model.importPlaylist(primaryPlaylistServiceImportItem)
        await model.importPlaylist(primaryPlaylistServiceImportItem)

        let callCount = await provider.importCallCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(model.requiresReview(for: primaryPlaylistServiceImportItem))
        guard case let .verificationNeeded(_, playlist, message) = model.notice else {
            return XCTFail("Expected verification guidance")
        }
        XCTAssertEqual(playlist, primaryPlaylistServiceImportItem)
        XCTAssertTrue(message.contains("Owned Playlists"))

        model.acknowledgeVerificationNotice()
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.requiresReview(for: primaryPlaylistServiceImportItem))
        model.clearAfterUserReview(primaryPlaylistServiceImportItem)
        XCTAssertFalse(model.requiresReview(for: primaryPlaylistServiceImportItem))
    }

    func testPreTransportCancellationClearsBarrier() async {
        let provider = PlaylistServiceImportFixtureProvider(mode: .cancelledBeforeTransport)
        let model = makeModel(provider: provider)

        await model.importPlaylist(primaryPlaylistServiceImportItem)

        XCTAssertFalse(model.requiresReview(for: primaryPlaylistServiceImportItem))
        XCTAssertNil(model.notice)
    }

    func testGenericCancellationAfterProviderAdmissionRemainsBlocked() async {
        let provider = PlaylistServiceImportFixtureProvider(mode: .genericCancellation)
        let model = makeModel(provider: provider)

        await model.importPlaylist(primaryPlaylistServiceImportItem)

        XCTAssertTrue(model.requiresReview(for: primaryPlaylistServiceImportItem))
        guard case .verificationNeeded = model.notice else {
            return XCTFail("Expected ambiguous cancellation")
        }
    }

    func testSecondModelCannotClearOrReplayAnActiveAttempt() async {
        let journal = PlaylistServiceImportJournal()
        let firstProvider = SuspendingPlaylistServiceImportProvider()
        let secondProvider = PlaylistServiceImportFixtureProvider(mode: .success)
        let account = Account(username: "listener", token: "token")
        let first = PlaylistServiceImportModel(
            account: account,
            provider: firstProvider,
            cache: EntityDetailCache(),
            journal: journal
        )
        let second = PlaylistServiceImportModel(
            account: account,
            provider: secondProvider,
            cache: EntityDetailCache(),
            journal: journal
        )
        let task = Task { await first.importPlaylist(primaryPlaylistServiceImportItem) }
        while !(await firstProvider.started()) { await Task.yield() }

        XCTAssertTrue(second.requiresReview(for: primaryPlaylistServiceImportItem))
        second.clearAfterUserReview(primaryPlaylistServiceImportItem)
        XCTAssertTrue(second.requiresReview(for: primaryPlaylistServiceImportItem))
        await second.importPlaylist(primaryPlaylistServiceImportItem)
        let secondCallCount = await secondProvider.importCallCount()
        XCTAssertEqual(secondCallCount, 0)

        await firstProvider.finish(with: importedMBID)
        await task.value
        XCTAssertTrue(first.requiresReview(for: primaryPlaylistServiceImportItem))
    }

    func testJournalPersistsOnlyTimestampBehindOpaqueFilename() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = PlaylistServiceImportJournal(directoryURL: directory)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(journal.beginAttempt(
            username: " Listener ",
            service: .spotify,
            externalPlaylistID: primaryPlaylistServiceImportItem.externalID,
            at: date
        ))

        let reopened = PlaylistServiceImportJournal(directoryURL: directory)
        XCTAssertEqual(reopened.record(
            username: "listener",
            service: .spotify,
            externalPlaylistID: primaryPlaylistServiceImportItem.externalID
        )?.attemptedAt, date)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        let filename = files[0].lastPathComponent
        let contents = String(decoding: try Data(contentsOf: files[0]), as: UTF8.self)
        for sensitive in ["listener", "spotify", primaryPlaylistServiceImportItem.externalID, "secret-token"] {
            XCTAssertFalse(filename.contains(sensitive))
            XCTAssertFalse(contents.contains(sensitive))
        }
    }

    func testCorruptJournalFailsClosedUntilExplicitReview() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = PlaylistServiceImportJournal(directoryURL: directory)
        XCTAssertTrue(original.beginAttempt(
            username: "listener",
            service: .spotify,
            externalPlaylistID: primaryPlaylistServiceImportItem.externalID,
            at: .now
        ))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).first)
        try Data("not-json".utf8).write(to: file)

        let reopened = PlaylistServiceImportJournal(directoryURL: directory)
        XCTAssertTrue(reopened.requiresRecovery(
            username: "listener",
            service: .spotify,
            externalPlaylistID: primaryPlaylistServiceImportItem.externalID
        ))
        XCTAssertFalse(reopened.beginAttempt(
            username: "listener",
            service: .spotify,
            externalPlaylistID: primaryPlaylistServiceImportItem.externalID,
            at: .now
        ))
        XCTAssertTrue(reopened.resolveAfterReview(
            username: "listener",
            service: .spotify,
            externalPlaylistID: primaryPlaylistServiceImportItem.externalID
        ))
        XCTAssertFalse(reopened.requiresReview(
            username: "listener",
            service: .spotify,
            externalPlaylistID: primaryPlaylistServiceImportItem.externalID
        ))
    }

    private func makeModel(
        provider: PlaylistServiceImportFixtureProvider,
        journal: PlaylistServiceImportJournal = .init()
    ) -> PlaylistServiceImportModel {
        PlaylistServiceImportModel(
            account: .init(username: "listener", token: "secret-token"),
            provider: provider,
            cache: EntityDetailCache(),
            journal: journal,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "PlaylistServiceImportTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

}

final class PlaylistServiceImportProviderTests: XCTestCase {
    private let importedMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    func testListReadCoalescesAndPreservesTruncationMetadata() async throws {
        let transport = PlaylistServiceImportTransportFixture(mode: .slowList)
        let provider = ListenBrainzPlaylistServiceImportProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            readScope: .isolated()
        )

        async let first = provider.playlists(from: .spotify)
        async let second = provider.playlists(from: .spotify)
        let values = try await [first, second]

        XCTAssertEqual(values.count, 2)
        XCTAssertTrue(values.allSatisfy(\.isTruncated))
        let callCount = await transport.listCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testListMappingBoundsUntrustedDisplayMetadata() async throws {
        let transport = PlaylistServiceImportTransportFixture(mode: .success)
        let provider = ListenBrainzPlaylistServiceImportProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let result = try await provider.playlists(from: .spotify)
        let playlist = try XCTUnwrap(result.playlists.first)

        XCTAssertEqual(playlist.title.count, 256)
        XCTAssertEqual(playlist.summary?.count, 500)
        XCTAssertEqual(playlist.ownerName?.count, 128)
        XCTAssertNil(playlist.trackCount)
        XCTAssertNil(playlist.artworkURL)
        XCTAssertTrue(result.isTruncated)
    }

    func testListMappingUsesReadableFallbackForBlankTitle() async throws {
        let transport = PlaylistServiceImportTransportFixture(mode: .blankTitle)
        let provider = ListenBrainzPlaylistServiceImportProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let result = try await provider.playlists(from: .spotify)

        XCTAssertEqual(result.playlists.first?.title, "Untitled Spotify playlist")
    }

    func testImportDispatchesExactlyOnceAndReturnsCreatedMBID() async throws {
        let transport = PlaylistServiceImportTransportFixture(mode: .success)
        let provider = ListenBrainzPlaylistServiceImportProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let result = try await provider.importPlaylist(primaryPlaylistServiceImportItem)

        XCTAssertEqual(result, importedMBID)
        let callCount = await transport.importCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testUnsafeIdentifierFailsBeforeTransport() async {
        let transport = PlaylistServiceImportTransportFixture(mode: .success)
        let provider = ListenBrainzPlaylistServiceImportProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let unsafe = PlaylistServiceImportItem(
            service: .spotify,
            externalID: "../playlist",
            title: "Unsafe",
            summary: nil,
            artworkURL: nil,
            ownerName: nil,
            trackCount: nil,
            isPublic: nil,
            isCollaborative: false
        )

        do {
            _ = try await provider.importPlaylist(unsafe)
            XCTFail("Expected validation failure")
        } catch let error as PlaylistServiceImportProviderError {
            XCTAssertEqual(error, .invalidPlaylistIdentifier)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await transport.importCallCount()
        XCTAssertEqual(callCount, 0)
    }

    func testEveryPostDispatchFailureIsIndeterminate() async {
        for mode in PlaylistServiceImportTransportFixture.Mode.importFailureCases {
            let provider = ListenBrainzPlaylistServiceImportProvider(
                transport: PlaylistServiceImportTransportFixture(mode: mode),
                gate: RequestGate(minimumInterval: .zero)
            )
            do {
                _ = try await provider.importPlaylist(primaryPlaylistServiceImportItem)
                XCTFail("Expected indeterminate result for \(mode)")
            } catch let error as PlaylistServiceImportProviderError {
                XCTAssertEqual(error, .indeterminateImport)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCancellationAfterDispatchIsIndeterminate() async {
        let transport = PlaylistServiceImportTransportFixture(mode: .suspendingImport)
        let provider = ListenBrainzPlaylistServiceImportProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let task = Task {
            try await provider.importPlaylist(primaryPlaylistServiceImportItem)
        }
        while await transport.importCallCount() == 0 { await Task.yield() }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected an indeterminate result")
        } catch let error as PlaylistServiceImportProviderError {
            XCTAssertEqual(error, .indeterminateImport)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQueuedCancellationNeverStartsImportTransport() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        let blocker = PlaylistImportGateBlocker()
        let blockingTask = Task {
            try await gate.perform {
                await blocker.markStarted()
                try await Task.sleep(for: .seconds(30))
            }
        }
        while !(await blocker.started()) { await Task.yield() }

        let transport = PlaylistServiceImportTransportFixture(mode: .success)
        let provider = ListenBrainzPlaylistServiceImportProvider(
            transport: transport,
            gate: gate
        )
        let queued = Task {
            try await provider.importPlaylist(primaryPlaylistServiceImportItem)
        }
        while await gate.queuedRequestCountForTesting() == 0 { await Task.yield() }

        queued.cancel()

        do {
            _ = try await queued.value
            XCTFail("Expected cancellation before transport")
        } catch let error as PlaylistServiceImportProviderError {
            XCTAssertEqual(error, .cancelledBeforeTransport)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await transport.importCallCount()
        XCTAssertEqual(callCount, 0)
        blockingTask.cancel()
        _ = try? await blockingTask.value
    }
}

private actor SuspendingPlaylistServiceImportProvider: PlaylistServiceImportProviding {
    private var continuation: CheckedContinuation<UUID, any Error>?

    func playlists(from service: PlaylistExternalService) async throws -> PlaylistServiceImportList {
        .init(service: .spotify, playlists: [primaryPlaylistServiceImportItem], isTruncated: false)
    }

    func importPlaylist(_ playlist: PlaylistServiceImportItem) async throws -> UUID {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func started() -> Bool { continuation != nil }

    func finish(with mbid: UUID) {
        continuation?.resume(returning: mbid)
        continuation = nil
    }
}

private actor SuspendingListPlaylistServiceImportProvider: PlaylistServiceImportProviding {
    private var continuation: CheckedContinuation<Void, Never>?
    private var listCalls = 0

    func playlists(from service: PlaylistExternalService) async throws -> PlaylistServiceImportList {
        listCalls += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return .init(service: .spotify, playlists: [primaryPlaylistServiceImportItem], isTruncated: false)
    }

    func importPlaylist(_ playlist: PlaylistServiceImportItem) async throws -> UUID {
        UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    }

    func started() -> Bool { continuation != nil }
    func listCallCount() -> Int { listCalls }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private actor PlaylistServiceImportFixtureProvider: PlaylistServiceImportProviding {
    enum Mode: Sendable {
        case success
        case listBadRequest
        case indeterminate
        case cancelledBeforeTransport
        case genericCancellation
    }

    private let mode: Mode
    private var listCalls = 0
    private var importCalls = 0

    init(mode: Mode) { self.mode = mode }

    func playlists(from service: PlaylistExternalService) async throws -> PlaylistServiceImportList {
        listCalls += 1
        if mode == .listBadRequest { throw LBError.badRequest }
        return PlaylistServiceImportList(
            service: .spotify,
            playlists: [
                primaryPlaylistServiceImportItem,
                PlaylistServiceImportItem(
                    service: .spotify,
                    externalID: "37i9dQZF1DX4WYpdgoIcn6",
                    title: "Prairie drives",
                    summary: nil,
                    artworkURL: nil,
                    ownerName: "listener",
                    trackCount: 18,
                    isPublic: true,
                    isCollaborative: false
                ),
            ],
            isTruncated: false
        )
    }

    func importPlaylist(_ playlist: PlaylistServiceImportItem) async throws -> UUID {
        importCalls += 1
        switch mode {
        case .success, .listBadRequest:
            return UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        case .indeterminate:
            throw PlaylistServiceImportProviderError.indeterminateImport
        case .cancelledBeforeTransport:
            throw PlaylistServiceImportProviderError.cancelledBeforeTransport
        case .genericCancellation:
            throw CancellationError()
        }
    }

    func listCallCount() -> Int { listCalls }
    func importCallCount() -> Int { importCalls }
}

private actor PlaylistServiceImportTransportFixture: PlaylistServiceImportTransport {
    enum Mode: Sendable {
        case success
        case blankTitle
        case slowList
        case badRequest
        case invalidAuth
        case forbidden
        case notFound
        case rateLimited
        case invalidResponse
        case suspendingImport

        static let importFailureCases: [Mode] = [
            .badRequest, .invalidAuth, .forbidden, .notFound, .rateLimited, .invalidResponse,
        ]

    }

    private let mode: Mode
    private var listCalls = 0
    private var importCalls = 0

    init(mode: Mode) { self.mode = mode }

    func spotifyPlaylists() async throws -> LBSpotifyPlaylistImportList {
        listCalls += 1
        if mode == .slowList { try await Task.sleep(for: .milliseconds(100)) }
        let summary = try LBSpotifyPlaylistSummary(
            id: primaryPlaylistServiceImportItem.externalID,
            title: mode == .blankTitle ? "  \n  " : String(repeating: "T", count: 300),
            description: String(repeating: "D", count: 600),
            artworkURL: URL(string: "http://example.com/art.jpg"),
            ownerName: String(repeating: "O", count: 180),
            trackCount: 10_001,
            isPublic: true,
            isCollaborative: false
        )
        return .init(playlists: [summary], isTruncated: true)
    }

    func importSpotifyPlaylist(id: String) async throws -> UUID {
        importCalls += 1
        switch mode {
        case .success, .blankTitle, .slowList:
            return UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        case .badRequest:
            throw LBError.badRequest
        case .invalidAuth:
            throw LBError.invalidAuth
        case .forbidden:
            throw LBError.forbidden
        case .notFound:
            throw LBError.notFound
        case .rateLimited:
            throw LBError.rateLimited(resetIn: 3)
        case .invalidResponse:
            throw LBError.invalidResponse
        case .suspendingImport:
            try await Task.sleep(for: .seconds(30))
            return UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        }
    }

    func listCallCount() -> Int { listCalls }
    func importCallCount() -> Int { importCalls }
}

private actor PlaylistImportGateBlocker {
    private var value = false
    func markStarted() { value = true }
    func started() -> Bool { value }
}
