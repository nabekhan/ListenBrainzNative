import Foundation
import ListenBrainzKit
import XCTest
@testable import Brainz

@MainActor
final class PlaylistMutationTests: XCTestCase {
    func testDraftNormalizationTrimsFieldsAndDeduplicatesCollaborators() throws {
        let normalized = try PlaylistMetadataDraft(
            title: "  Night drive  ",
            annotation: "  Quiet roads.  ",
            isPublic: false,
            collaborators: [" Alice ", "alice", "LISTENER", "", "BOB"]
        ).normalized(ownerUsername: " listener ")

        XCTAssertEqual(normalized.title, "Night drive")
        XCTAssertEqual(normalized.annotation, "Quiet roads.")
        XCTAssertFalse(normalized.isPublic)
        XCTAssertEqual(normalized.collaborators, ["Alice", "BOB"])
    }

    func testProviderCreatesOneNormalizedFullMetadataSnapshot() async throws {
        let expectedID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let transport = PlaylistMutationTransportSpy(createdID: expectedID)
        let provider = ListenBrainzPlaylistMutationProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let createdID = try await provider.create(
            metadata: .init(
                title: "  A careful mix ",
                annotation: "   ",
                isPublic: false,
                collaborators: [" Friend ", "friend", "listener"]
            ),
            ownerUsername: "Listener"
        )

        XCTAssertEqual(createdID, expectedID)
        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls, [
            .create(.init(
                title: "A careful mix",
                annotation: nil,
                isPublic: false,
                collaborators: ["Friend"]
            )),
        ])
    }

    func testProviderEditSendsCompleteSnapshotIncludingExplicitClears() async throws {
        let mbid = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let transport = PlaylistMutationTransportSpy()
        let provider = ListenBrainzPlaylistMutationProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        try await provider.edit(
            mbid: mbid,
            metadata: .init(title: "Retitled", annotation: "", isPublic: true, collaborators: []),
            ownerUsername: "listener"
        )

        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls, [
            .edit(mbid, .init(
                title: "Retitled",
                annotation: nil,
                isPublic: true,
                collaborators: []
            )),
        ])
    }

    func testProviderMapsRateLimitWithoutRetryingMutation() async {
        let transport = PlaylistMutationTransportSpy(error: LBError.rateLimited(resetIn: 4))
        let provider = ListenBrainzPlaylistMutationProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        do {
            _ = try await provider.create(
                metadata: .init(title: "One attempt", isPublic: true),
                ownerUsername: "listener"
            )
            XCTFail("Expected rate limiting")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 4)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls.count, 1)
    }

    func testConfirmedEditInvalidatesEveryDetailScopeAndProfilePage() async throws {
        let mbid = UUID()
        let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let publicKey = PlaylistDetailCacheKey(mbid: mbid, accessScope: .publicOnly)
        let authenticatedKey = PlaylistDetailCacheKey(
            mbid: mbid,
            accessScope: .authenticatedViewer(.authenticated(token: "listener"))
        )
        let pageKey = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .publicOnly,
            category: .owned,
            offset: 0,
            count: 20
        )
        let cachedDetail = playlistDetail(mbid: mbid, isPublic: true)
        await detailCache.save(cachedDetail, for: publicKey)
        await detailCache.save(cachedDetail, for: authenticatedKey)
        await pageCache.save(
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
        let provider = ListenBrainzPlaylistMutationProvider(
            transport: PlaylistMutationTransportSpy(),
            gate: RequestGate(minimumInterval: .zero),
            detailCache: detailCache,
            profilePageCache: pageCache
        )

        try await provider.edit(
            mbid: mbid,
            metadata: .init(title: "Private now", isPublic: false),
            ownerUsername: "listener"
        )

        let publicValue = await detailCache.value(for: publicKey)
        let authenticatedValue = await detailCache.value(for: authenticatedKey)
        let pageValue = await pageCache.value(for: pageKey)
        XCTAssertNil(publicValue)
        XCTAssertNil(authenticatedValue)
        XCTAssertNil(pageValue)
    }

    func testLostCreateResponseIsIndeterminateNeverRetriedAndClearsListCache() async {
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let key = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "listener")),
            category: .owned,
            offset: 0,
            count: 20
        )
        await pageCache.save(
            .init(
                username: "listener",
                category: .owned,
                playlists: [],
                requestedCount: 20,
                offset: 0,
                totalCount: 0
            ),
            for: key
        )
        let transport = PlaylistMutationTransportSpy(error: PlaylistMutationFixtureError.failed)
        let provider = ListenBrainzPlaylistMutationProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: EntityDetailCache(),
            profilePageCache: pageCache
        )

        do {
            _ = try await provider.create(
                metadata: .init(title: "Possibly created"),
                ownerUsername: "listener"
            )
            XCTFail("Expected an indeterminate creation result")
        } catch let error as PlaylistMutationProviderError {
            XCTAssertTrue(error.isIndeterminate)
            XCTAssertEqual(
                error.localizedDescription,
                PlaylistMutationProviderError.indeterminateCreation.localizedDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls.count, 1)
        let cached = await pageCache.value(for: key)
        XCTAssertNil(cached)
    }

    func testCancellationAfterTransportStartsIsIndeterminateAndClearsListCache() async {
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let key = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "listener")),
            category: .owned,
            offset: 0,
            count: 20
        )
        await pageCache.save(
            .init(
                username: "listener",
                category: .owned,
                playlists: [],
                requestedCount: 20,
                offset: 0,
                totalCount: 0
            ),
            for: key
        )
        let transport = CancellationMutationTransport()
        let provider = ListenBrainzPlaylistMutationProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: EntityDetailCache(),
            profilePageCache: pageCache
        )
        let task = Task {
            try await provider.create(
                metadata: .init(title: "Possibly committed"),
                ownerUsername: "listener"
            )
        }
        while !(await transport.hasStarted) { await Task.yield() }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected an indeterminate cancellation result")
        } catch let error as PlaylistMutationProviderError {
            XCTAssertEqual(
                error.localizedDescription,
                PlaylistMutationProviderError.indeterminateCreation.localizedDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let cached = await pageCache.value(for: key)
        XCTAssertNil(cached)
    }

    func testCancellationBeforeTransportAdmissionRemainsCancellation() async throws {
        let gate = RequestGate(minimumInterval: .seconds(5))
        _ = try await gate.perform { true }
        let transport = CancellationMutationTransport()
        let provider = ListenBrainzPlaylistMutationProvider(
            transport: transport,
            gate: gate,
            detailCache: EntityDetailCache(),
            profilePageCache: EntityDetailCache()
        )
        let task = Task {
            try await provider.create(
                metadata: .init(title: "Never dispatched"),
                ownerUsername: "listener"
            )
        }
        await Task.yield()

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation before transport")
        } catch is CancellationError {
            // Expected: no POST was admitted to transport.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let didStart = await transport.hasStarted
        XCTAssertFalse(didStart)
    }

    func testConfirmedAppendUsesOneCallAndInvalidatesEveryPlaylistCacheScope() async throws {
        let playlistMBID = UUID()
        let recordingMBID = UUID()
        let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
        let publicKey = PlaylistDetailCacheKey(mbid: playlistMBID, accessScope: .publicOnly)
        let authenticatedKey = PlaylistDetailCacheKey(
            mbid: playlistMBID,
            accessScope: .authenticatedViewer(.authenticated(token: "listener"))
        )
        let pageKey = ProfilePlaylistPageKey(
            username: "listener",
            accessScope: .authenticatedViewer(.authenticated(token: "listener")),
            category: .collaborating,
            offset: 0,
            count: 20
        )
        let cachedDetail = playlistDetail(mbid: playlistMBID)
        await detailCache.save(cachedDetail, for: publicKey)
        await detailCache.save(cachedDetail, for: authenticatedKey)
        await pageCache.save(
            .init(
                username: "listener",
                category: .collaborating,
                playlists: [],
                requestedCount: 20,
                offset: 0,
                totalCount: 0
            ),
            for: pageKey
        )
        let transport = PlaylistAppendTransportSpy()
        let provider = ListenBrainzPlaylistAppendProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: detailCache,
            profilePageCache: pageCache
        )

        try await provider.append(recordingMBID: recordingMBID, to: playlistMBID)

        let calls = await transport.recordedCalls()
        let publicValue = await detailCache.value(for: publicKey)
        let authenticatedValue = await detailCache.value(for: authenticatedKey)
        let pageValue = await pageCache.value(for: pageKey)
        XCTAssertEqual(calls, [.init(playlistMBID: playlistMBID, recordingMBIDs: [recordingMBID])])
        XCTAssertNil(publicValue)
        XCTAssertNil(authenticatedValue)
        XCTAssertNil(pageValue)
    }

    func testAppendMapsRateLimitWithoutRetrying() async {
        let transport = PlaylistAppendTransportSpy(error: LBError.rateLimited(resetIn: 7))
        let provider = ListenBrainzPlaylistAppendProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: EntityDetailCache(),
            profilePageCache: EntityDetailCache()
        )

        do {
            try await provider.append(recordingMBID: UUID(), to: UUID())
            XCTFail("Expected rate limiting")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 7)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await transport.recordedCalls()
        XCTAssertEqual(calls.count, 1)
    }

    func testAppendAccessFailuresPurgePrivateDetailAndDestinationCaches() async {
        for sourceError in [LBError.invalidAuth, LBError.forbidden, LBError.notFound] {
            let playlistMBID = UUID()
            let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
            let pageCache = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>()
            let detailKey = PlaylistDetailCacheKey(
                mbid: playlistMBID,
                accessScope: .authenticatedViewer(.authenticated(token: "listener"))
            )
            let pageKey = ProfilePlaylistPageKey(
                username: "listener",
                accessScope: .authenticatedViewer(.authenticated(token: "listener")),
                category: .collaborating,
                offset: 0,
                count: 20
            )
            await detailCache.save(playlistDetail(mbid: playlistMBID, isPublic: false), for: detailKey)
            await pageCache.save(
                .init(
                    username: "listener",
                    category: .collaborating,
                    playlists: [],
                    requestedCount: 20,
                    offset: 0,
                    totalCount: 0
                ),
                for: pageKey
            )
            let transport = PlaylistAppendTransportSpy(error: sourceError)
            let provider = ListenBrainzPlaylistAppendProvider(
                transport: transport,
                gate: RequestGate(minimumInterval: .zero),
                detailCache: detailCache,
                profilePageCache: pageCache
            )

            do {
                try await provider.append(recordingMBID: UUID(), to: playlistMBID)
                XCTFail("Expected access failure")
            } catch {
                // The exact user-facing mapping is covered elsewhere; this
                // assertion protects the privacy-sensitive cache boundary.
            }

            let cachedDetail = await detailCache.value(for: detailKey)
            let cachedPage = await pageCache.value(for: pageKey)
            XCTAssertNil(cachedDetail)
            XCTAssertNil(cachedPage)
            let calls = await transport.recordedCalls()
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testAppendCancellationAfterTransportStartsIsIndeterminateAndClearsCaches() async {
        let playlistMBID = UUID()
        let detailCache = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
        let key = PlaylistDetailCacheKey(mbid: playlistMBID, accessScope: .publicOnly)
        await detailCache.save(playlistDetail(mbid: playlistMBID), for: key)
        let transport = CancellationAppendTransport()
        let provider = ListenBrainzPlaylistAppendProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            detailCache: detailCache,
            profilePageCache: EntityDetailCache()
        )
        let task = Task {
            try await provider.append(recordingMBID: UUID(), to: playlistMBID)
        }
        while !(await transport.hasStarted) { await Task.yield() }

        task.cancel()
        do {
            try await task.value
            XCTFail("Expected an indeterminate append result")
        } catch let error as PlaylistMutationProviderError {
            XCTAssertEqual(
                error.localizedDescription,
                PlaylistMutationProviderError.indeterminateAppend.localizedDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let cached = await detailCache.value(for: key)
        XCTAssertNil(cached)
    }

    func testAppendCancellationBeforeTransportAdmissionDoesNotDispatch() async throws {
        let gate = RequestGate(minimumInterval: .seconds(5))
        _ = try await gate.perform { true }
        let transport = CancellationAppendTransport()
        let provider = ListenBrainzPlaylistAppendProvider(
            transport: transport,
            gate: gate,
            detailCache: EntityDetailCache(),
            profilePageCache: EntityDetailCache()
        )
        let task = Task {
            try await provider.append(recordingMBID: UUID(), to: UUID())
        }
        await Task.yield()

        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation before transport")
        } catch is CancellationError {
            // Expected: no POST was admitted to transport.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let didStart = await transport.hasStarted
        XCTAssertFalse(didStart)
    }

    func testEditorSerializesDuplicateCreateTaps() async {
        let createdID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
        let provider = PlaylistMutationFixtureProvider(createdID: createdID, delay: .milliseconds(60))
        let model = PlaylistMetadataEditorModel(
            account: Account(username: "listener", token: "token"),
            draft: .init(title: "A new playlist", isPublic: true),
            provider: provider
        )

        async let first = model.save()
        async let second = model.save()
        let results = await [first, second]

        XCTAssertEqual(results.compactMap { $0 }, [.created(createdID)])
        let operations = await provider.recordedOperations()
        XCTAssertEqual(operations, [.create("listener", .init(title: "A new playlist", isPublic: true))])
    }

    func testEditorPreservesFullEditStateWhenSaveFails() async {
        let mbid = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
        let provider = PlaylistMutationFixtureProvider(error: PlaylistMutationFixtureError.failed)
        let detail = PlaylistDetail(
            mbid: mbid,
            title: "Before",
            creator: "listener",
            annotation: "Existing note",
            createdAt: nil,
            lastModifiedAt: nil,
            isPublic: false,
            createdFor: nil,
            collaborators: ["Alice", "Bob"],
            copiedFrom: nil,
            tracks: []
        )
        let model = PlaylistMetadataEditorModel(
            account: Account(username: "listener", token: "token"),
            detail: detail,
            provider: provider
        )
        model.title = "After"
        model.annotation = "Updated note"
        model.isPublic = true

        let result = await model.save()

        XCTAssertNil(result)
        XCTAssertEqual(model.title, "After")
        XCTAssertEqual(model.annotation, "Updated note")
        XCTAssertEqual(model.collaborators, ["Alice", "Bob"])
        XCTAssertEqual(model.errorMessage, PlaylistMutationFixtureError.failed.localizedDescription)
        let operations = await provider.recordedOperations()
        XCTAssertEqual(operations, [
            .edit(
                mbid,
                "listener",
                .init(
                    title: "After",
                    annotation: "Updated note",
                    isPublic: true,
                    collaborators: ["Alice", "Bob"]
                )
            ),
        ])
    }

    func testEditorRefusesToOverwriteMetadataChangedAfterOpening() async {
        let mbid = UUID()
        let original = playlistDetail(
            mbid: mbid,
            title: "Before",
            collaborators: ["Alice"]
        )
        let latest = playlistDetail(
            mbid: mbid,
            title: "Before",
            collaborators: ["Alice", "Bob"]
        )
        let provider = PlaylistMutationFixtureProvider()
        let model = PlaylistMetadataEditorModel(
            account: Account(username: "listener", token: "token"),
            detail: original,
            editPreflight: { latest },
            provider: provider
        )
        model.title = "My new title"

        let result = await model.save()

        XCTAssertNil(result)
        XCTAssertEqual(
            model.errorMessage,
            PlaylistMetadataEditorError.changedElsewhere.localizedDescription
        )
        let operations = await provider.recordedOperations()
        XCTAssertTrue(operations.isEmpty)
    }

    func testIndeterminateCreateDisablesAnotherSaveUntilUserReconciles() async {
        let provider = PlaylistMutationFixtureProvider(
            error: PlaylistMutationProviderError.indeterminateCreation
        )
        let model = PlaylistMetadataEditorModel(
            account: Account(username: "listener", token: "token"),
            draft: .init(title: "Could already exist"),
            provider: provider
        )

        let result = await model.save()

        XCTAssertNil(result)
        XCTAssertTrue(model.requiresReconciliation)
        XCTAssertFalse(model.canSave)
        XCTAssertEqual(
            model.errorMessage,
            PlaylistMutationProviderError.indeterminateCreation.localizedDescription
        )
        let operations = await provider.recordedOperations()
        XCTAssertEqual(operations.count, 1)
    }

    private func playlistDetail(
        mbid: UUID,
        title: String = "Playlist",
        isPublic: Bool = true,
        collaborators: [String] = []
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
            tracks: []
        )
    }
}

private actor PlaylistMutationTransportSpy: PlaylistMutationTransport {
    enum Call: Equatable, Sendable {
        case create(LBPlaylistMutationMetadata)
        case edit(UUID, LBPlaylistMutationMetadata)
    }

    private let createdID: UUID
    private let error: (any Error & Sendable)?
    private var calls: [Call] = []

    init(
        createdID: UUID = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!,
        error: (any Error & Sendable)? = nil
    ) {
        self.createdID = createdID
        self.error = error
    }

    func create(metadata: LBPlaylistMutationMetadata) async throws -> UUID {
        calls.append(.create(metadata))
        if let error { throw error }
        return createdID
    }

    func edit(mbid: UUID, metadata: LBPlaylistMutationMetadata) async throws {
        calls.append(.edit(mbid, metadata))
        if let error { throw error }
    }

    func recordedCalls() -> [Call] { calls }
}

private actor PlaylistMutationFixtureProvider: PlaylistMutationProviding {
    enum Operation: Equatable, Sendable {
        case create(String, PlaylistMetadataDraft)
        case edit(UUID, String, PlaylistMetadataDraft)
    }

    private let createdID: UUID
    private let error: (any Error & Sendable)?
    private let delay: Duration
    private var operations: [Operation] = []

    init(
        createdID: UUID = UUID(),
        error: (any Error & Sendable)? = nil,
        delay: Duration = .zero
    ) {
        self.createdID = createdID
        self.error = error
        self.delay = delay
    }

    func create(metadata: PlaylistMetadataDraft, ownerUsername: String) async throws -> UUID {
        operations.append(.create(ownerUsername, metadata))
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return createdID
    }

    func edit(mbid: UUID, metadata: PlaylistMetadataDraft, ownerUsername: String) async throws {
        operations.append(.edit(mbid, ownerUsername, metadata))
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
    }

    func recordedOperations() -> [Operation] { operations }
}

private actor CancellationMutationTransport: PlaylistMutationTransport {
    private(set) var hasStarted = false

    func create(metadata: LBPlaylistMutationMetadata) async throws -> UUID {
        hasStarted = true
        try await Task.sleep(for: .seconds(60))
        return UUID()
    }

    func edit(mbid: UUID, metadata: LBPlaylistMutationMetadata) async throws {
        hasStarted = true
        try await Task.sleep(for: .seconds(60))
    }
}

private actor PlaylistAppendTransportSpy: PlaylistAppendTransport {
    struct Call: Equatable, Sendable {
        let playlistMBID: UUID
        let recordingMBIDs: [UUID]
    }

    private let error: (any Error & Sendable)?
    private var calls: [Call] = []

    init(error: (any Error & Sendable)? = nil) {
        self.error = error
    }

    func append(recordingMBIDs: [UUID], to playlistMBID: UUID) async throws {
        calls.append(.init(playlistMBID: playlistMBID, recordingMBIDs: recordingMBIDs))
        if let error { throw error }
    }

    func recordedCalls() -> [Call] { calls }
}

private actor CancellationAppendTransport: PlaylistAppendTransport {
    private(set) var hasStarted = false

    func append(recordingMBIDs: [UUID], to playlistMBID: UUID) async throws {
        hasStarted = true
        try await Task.sleep(for: .seconds(60))
    }
}

private enum PlaylistMutationFixtureError: LocalizedError, Sendable {
    case failed
    var errorDescription: String? { "Fixture save failed." }
}
