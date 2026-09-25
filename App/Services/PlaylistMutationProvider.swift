import Foundation
import ListenBrainzKit

protocol PlaylistMutationProviding: Sendable {
    func create(metadata: PlaylistMetadataDraft, ownerUsername: String) async throws -> UUID
    func edit(mbid: UUID, metadata: PlaylistMetadataDraft, ownerUsername: String) async throws
}

protocol PlaylistMutationTransport: Sendable {
    func create(metadata: LBPlaylistMutationMetadata) async throws -> UUID
    func edit(mbid: UUID, metadata: LBPlaylistMutationMetadata) async throws
}

protocol PlaylistAppendProviding: Sendable {
    func append(recordingMBID: UUID, to playlistMBID: UUID) async throws
}

protocol PlaylistAppendTransport: Sendable {
    func append(recordingMBIDs: [UUID], to playlistMBID: UUID) async throws
}

protocol PlaylistItemRemovalProviding: Sendable {
    /// A raw `CancellationError` means transport did not begin. Live providers
    /// translate cancellation after dispatch into an indeterminate mutation.
    func removeItems(at index: Int, count: Int, from playlistMBID: UUID) async throws
}

protocol PlaylistItemRemovalTransport: Sendable {
    func removeItems(at index: Int, count: Int, from playlistMBID: UUID) async throws
}

extension PlaylistItemRemovalProviding {
    func removeItem(at index: Int, from playlistMBID: UUID) async throws {
        try await removeItems(at: index, count: 1, from: playlistMBID)
    }
}

/// A positional move is deliberately a one-shot operation. A raw
/// `CancellationError` means the transport never started; providers translate
/// cancellation after dispatch into `.indeterminateReorder`.
protocol PlaylistItemReorderingProviding: Sendable {
    func moveItem(recordingMBID: UUID, from: Int, to: Int, in playlistMBID: UUID) async throws
}

protocol PlaylistItemReorderingTransport: Sendable {
    func moveItem(recordingMBID: UUID, from: Int, to: Int, in playlistMBID: UUID) async throws
}

protocol PlaylistCopyProviding: Sendable {
    func copy(mbid: UUID) async throws -> UUID
}

protocol PlaylistCopyTransport: Sendable {
    func copy(mbid: UUID) async throws -> UUID
}

protocol PlaylistDeletionProviding: Sendable {
    func delete(mbid: UUID) async throws
}

protocol PlaylistDeletionTransport: Sendable {
    func delete(mbid: UUID) async throws
}

private struct LivePlaylistMutationTransport: PlaylistMutationTransport {
    let client: LBClient

    func create(metadata: LBPlaylistMutationMetadata) async throws -> UUID {
        try await client.core.createPlaylist(metadata: metadata)
    }

    func edit(mbid: UUID, metadata: LBPlaylistMutationMetadata) async throws {
        try await client.core.editPlaylist(mbid: mbid, metadata: metadata)
    }
}

private struct LivePlaylistAppendTransport: PlaylistAppendTransport {
    let client: LBClient

    func append(recordingMBIDs: [UUID], to playlistMBID: UUID) async throws {
        try await client.core.addPlaylistItems(mbid: playlistMBID, recordingMBIDs: recordingMBIDs)
    }
}

private struct LivePlaylistItemRemovalTransport: PlaylistItemRemovalTransport {
    let client: LBClient

    func removeItems(at index: Int, count: Int, from playlistMBID: UUID) async throws {
        try await client.core.removePlaylistItems(mbid: playlistMBID, index: index, count: count)
    }
}

private struct LivePlaylistItemReorderingTransport: PlaylistItemReorderingTransport {
    let client: LBClient

    func moveItem(recordingMBID: UUID, from: Int, to: Int, in playlistMBID: UUID) async throws {
        try await client.core.movePlaylistItems(
            mbid: playlistMBID, recordingMBID: recordingMBID, from: from, to: to, count: 1)
    }
}

private struct LivePlaylistCopyTransport: PlaylistCopyTransport {
    let client: LBClient

    func copy(mbid: UUID) async throws -> UUID {
        try await client.core.copyPlaylist(mbid: mbid)
    }
}

private struct LivePlaylistDeletionTransport: PlaylistDeletionTransport {
    let client: LBClient

    func delete(mbid: UUID) async throws {
        try await client.core.deletePlaylist(mbid: mbid)
    }
}

/// A serialized, one-shot deletion boundary. The post is never replayed: a
/// transport failure after dispatch cannot establish whether the playlist was
/// permanently deleted.
struct ListenBrainzPlaylistDeletionProvider: PlaylistDeletionProviding {
    private let transport: any PlaylistDeletionTransport
    private let gate: RequestGate
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>
    private let profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>

    init(token: String, gate: RequestGate = .shared,
         detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
         profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages) {
        transport = LivePlaylistDeletionTransport(client: LBClient(token: token, userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"))
        self.gate = gate; self.detailCache = detailCache; self.profilePageCache = profilePageCache
    }

    init(transport: some PlaylistDeletionTransport, gate: RequestGate,
         detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
         profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages) {
        self.transport = transport; self.gate = gate; self.detailCache = detailCache; self.profilePageCache = profilePageCache
    }

    func delete(mbid: UUID) async throws {
        let attempt = MutationAttemptState()
        do {
            try await gate.perform({
                await attempt.markTransportStarted()
                try await transport.delete(mbid: mbid)
            }) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            await invalidateCaches()
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.noToken {
            await invalidateCaches(); throw PlaylistMutationProviderError.invalidAuthentication
        } catch LBError.forbidden {
            await invalidateCaches(); throw PlaylistMutationProviderError.deleteNotOwner
        } catch LBError.notFound {
            await invalidateCaches(); throw PlaylistMutationProviderError.playlistUnavailable
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam {
            throw PlaylistMutationProviderError.deleteRejected
        } catch is CancellationError {
            if await attempt.didStartTransport { await invalidateCaches(); throw PlaylistMutationProviderError.indeterminateDeletion }
            throw CancellationError()
        } catch {
            await invalidateCaches(); throw PlaylistMutationProviderError.indeterminateDeletion
        }
    }

    private func invalidateCaches() async { await detailCache.removeAll(); await profilePageCache.removeAll() }
    private actor MutationAttemptState { private(set) var didStartTransport = false; func markTransportStarted() { didStartTransport = true } }
}

/// A one-shot copy boundary. ListenBrainz creates a distinct playlist for
/// every successful POST and exposes no idempotency key, so a request that may
/// have reached the server is never replayed automatically.
struct ListenBrainzPlaylistCopyProvider: PlaylistCopyProviding {
    private let transport: any PlaylistCopyTransport
    private let gate: RequestGate
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>
    private let profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>

    init(
        token: String,
        gate: RequestGate = .shared,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        transport = LivePlaylistCopyTransport(client: LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        ))
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    init(
        transport: some PlaylistCopyTransport,
        gate: RequestGate,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        self.transport = transport
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    func copy(mbid: UUID) async throws -> UUID {
        let attempt = MutationAttemptState()
        do {
            let copiedMBID = try await gate.perform({
                await attempt.markTransportStarted()
                return try await transport.copy(mbid: mbid)
            }) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            await profilePageCache.removeAll()
            return copiedMBID
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.noToken {
            await invalidateAccessSensitiveCaches()
            throw PlaylistMutationProviderError.invalidAuthentication
        } catch LBError.forbidden, LBError.notFound {
            await invalidateAccessSensitiveCaches()
            throw PlaylistMutationProviderError.playlistUnavailable
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam {
            throw PlaylistMutationProviderError.copyRejected
        } catch LBError.invalidResponse, LBError.noContent, LBError.unknownError {
            await profilePageCache.removeAll()
            throw PlaylistMutationProviderError.indeterminateCopy
        } catch is CancellationError {
            guard await attempt.didStartTransport else { throw CancellationError() }
            await profilePageCache.removeAll()
            throw PlaylistMutationProviderError.indeterminateCopy
        } catch {
            // A connection failure after dispatch cannot prove that the server
            // did not commit the copy. Clear list snapshots and prohibit replay.
            await profilePageCache.removeAll()
            throw PlaylistMutationProviderError.indeterminateCopy
        }
    }

    private func invalidateAccessSensitiveCaches() async {
        await detailCache.removeAll()
        await profilePageCache.removeAll()
    }

    private actor MutationAttemptState {
        private(set) var didStartTransport = false

        func markTransportStarted() {
            didStartTransport = true
        }
    }
}

/// A non-retrying append boundary. The server permits duplicates and does not
/// provide an idempotency key, so callers reconcile the canonical detail after
/// any ambiguous result instead of replaying the POST.
struct ListenBrainzPlaylistAppendProvider: PlaylistAppendProviding {
    private let transport: any PlaylistAppendTransport
    private let gate: RequestGate
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>
    private let profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>

    init(
        token: String,
        gate: RequestGate = .shared,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        transport = LivePlaylistAppendTransport(client: LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        ))
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    init(
        transport: some PlaylistAppendTransport,
        gate: RequestGate,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        self.transport = transport
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    func append(recordingMBID: UUID, to playlistMBID: UUID) async throws {
        let attempt = MutationAttemptState()
        do {
            try await gate.perform({
                await attempt.markTransportStarted()
                try await transport.append(recordingMBIDs: [recordingMBID], to: playlistMBID)
            }) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            await invalidateCaches()
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.noToken {
            await invalidateCaches()
            throw PlaylistMutationProviderError.invalidAuthentication
        } catch LBError.forbidden {
            await invalidateCaches()
            throw PlaylistMutationProviderError.notCollaborator
        } catch LBError.notFound {
            await invalidateCaches()
            throw PlaylistMutationProviderError.playlistUnavailable
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam {
            throw PlaylistMutationProviderError.rejected
        } catch LBError.invalidResponse, LBError.noContent, LBError.unknownError {
            await invalidateCaches()
            throw PlaylistMutationProviderError.indeterminateAppend
        } catch is CancellationError {
            if await attempt.didStartTransport {
                await invalidateCaches()
                throw PlaylistMutationProviderError.indeterminateAppend
            }
            throw CancellationError()
        } catch {
            await invalidateCaches()
            throw PlaylistMutationProviderError.indeterminateAppend
        }
    }

    private func invalidateCaches() async {
        await detailCache.removeAll()
        await profilePageCache.removeAll()
    }

    private actor MutationAttemptState {
        private(set) var didStartTransport = false

        func markTransportStarted() {
            didStartTransport = true
        }
    }
}

/// A one-shot positional removal boundary. A lost response cannot establish
/// whether that index was deleted, so it is deliberately never retried.
struct ListenBrainzPlaylistItemRemovalProvider: PlaylistItemRemovalProviding {
    private let transport: any PlaylistItemRemovalTransport
    private let gate: RequestGate
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>
    private let profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>

    init(token: String, gate: RequestGate = .shared,
         detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
         profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages) {
        transport = LivePlaylistItemRemovalTransport(client: LBClient(token: token, userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"))
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    init(transport: some PlaylistItemRemovalTransport, gate: RequestGate,
         detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
         profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages) {
        self.transport = transport
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    func removeItems(at index: Int, count: Int, from playlistMBID: UUID) async throws {
        guard index >= 0, count > 0 else { throw PlaylistMutationProviderError.removalRejected }
        let attempt = MutationAttemptState()
        do {
            try await gate.perform({
                await attempt.markTransportStarted()
                try await transport.removeItems(at: index, count: count, from: playlistMBID)
            }) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            await invalidateCaches()
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.noToken {
            await invalidateCaches(); throw PlaylistMutationProviderError.invalidAuthentication
        } catch LBError.forbidden {
            await invalidateCaches(); throw PlaylistMutationProviderError.notCollaborator
        } catch LBError.notFound {
            await invalidateCaches(); throw PlaylistMutationProviderError.playlistUnavailable
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam {
            throw PlaylistMutationProviderError.removalRejected
        } catch is CancellationError {
            if await attempt.didStartTransport { await invalidateCaches(); throw PlaylistMutationProviderError.indeterminateRemoval }
            throw CancellationError()
        } catch {
            await invalidateCaches(); throw PlaylistMutationProviderError.indeterminateRemoval
        }
    }

    private func invalidateCaches() async { await detailCache.removeAll(); await profilePageCache.removeAll() }
    private actor MutationAttemptState { private(set) var didStartTransport = false; func markTransportStarted() { didStartTransport = true } }
}

/// Serialized, non-retrying wrapper around ListenBrainz's positional move
/// endpoint. Cache invalidation happens after every dispatched request because
/// a missing response cannot prove the order stayed unchanged.
struct ListenBrainzPlaylistItemReorderingProvider: PlaylistItemReorderingProviding {
    private let transport: any PlaylistItemReorderingTransport
    private let gate: RequestGate
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>
    private let profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>

    init(token: String, gate: RequestGate = .shared,
         detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
         profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages) {
        transport = LivePlaylistItemReorderingTransport(client: LBClient(token: token, userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"))
        self.gate = gate; self.detailCache = detailCache; self.profilePageCache = profilePageCache
    }

    init(transport: some PlaylistItemReorderingTransport, gate: RequestGate,
         detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
         profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages) {
        self.transport = transport; self.gate = gate; self.detailCache = detailCache; self.profilePageCache = profilePageCache
    }

    func moveItem(recordingMBID: UUID, from: Int, to: Int, in playlistMBID: UUID) async throws {
        guard from >= 0, to >= 0, from != to else { throw PlaylistMutationProviderError.reorderRejected }
        let attempt = MutationAttemptState()
        do {
            try await gate.perform({
                await attempt.markTransportStarted()
                try await transport.moveItem(recordingMBID: recordingMBID, from: from, to: to, in: playlistMBID)
            }) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            await invalidateCaches()
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.noToken {
            await invalidateCaches(); throw PlaylistMutationProviderError.invalidAuthentication
        } catch LBError.forbidden {
            await invalidateCaches(); throw PlaylistMutationProviderError.notCollaborator
        } catch LBError.notFound {
            await invalidateCaches(); throw PlaylistMutationProviderError.playlistUnavailable
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam {
            throw PlaylistMutationProviderError.reorderRejected
        } catch is CancellationError {
            if await attempt.didStartTransport { await invalidateCaches(); throw PlaylistMutationProviderError.indeterminateReorder }
            throw CancellationError()
        } catch {
            await invalidateCaches(); throw PlaylistMutationProviderError.indeterminateReorder
        }
    }

    private func invalidateCaches() async { await detailCache.removeAll(); await profilePageCache.removeAll() }
    private actor MutationAttemptState { private(set) var didStartTransport = false; func markTransportStarted() { didStartTransport = true } }
}

struct ListenBrainzPlaylistMutationProvider: PlaylistMutationProviding {
    private let transport: any PlaylistMutationTransport
    private let gate: RequestGate
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>
    private let profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>

    init(
        token: String,
        gate: RequestGate = .shared,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        transport = LivePlaylistMutationTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    init(
        transport: some PlaylistMutationTransport,
        gate: RequestGate,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        self.transport = transport
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    func create(metadata: PlaylistMetadataDraft, ownerUsername: String) async throws -> UUID {
        let metadata = try Self.transportMetadata(metadata, ownerUsername: ownerUsername)
        do {
            let mbid = try await performMutation(kind: .create) {
                try await transport.create(metadata: metadata)
            }
            await invalidateCaches(for: .create)
            return mbid
        } catch {
            if Self.requiresReconciliation(error) {
                await invalidateCaches(for: .create)
            }
            throw error
        }
    }

    func edit(mbid: UUID, metadata: PlaylistMetadataDraft, ownerUsername: String) async throws {
        let metadata = try Self.transportMetadata(metadata, ownerUsername: ownerUsername)
        do {
            try await performMutation(kind: .edit) {
                try await transport.edit(mbid: mbid, metadata: metadata)
            }
            await invalidateCaches(for: .edit)
        } catch {
            if Self.requiresReconciliation(error) {
                await invalidateCaches(for: .edit)
            }
            throw error
        }
    }

    private func performMutation<Result: Sendable>(
        kind: MutationKind,
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        let attempt = MutationAttemptState()
        do {
            // RequestGate serializes this attempt with every other ListenBrainz
            // request. Mutations are never retried automatically: create/edit
            // endpoints do not expose idempotency keys.
            return try await gate.perform({
                await attempt.markTransportStarted()
                return try await operation()
            }) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.noToken {
            throw PlaylistMutationProviderError.invalidAuthentication
        } catch LBError.forbidden {
            throw PlaylistMutationProviderError.notOwner
        } catch LBError.notFound {
            throw PlaylistMutationProviderError.playlistUnavailable
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam {
            throw PlaylistMutationProviderError.rejected
        } catch LBError.invalidResponse, LBError.noContent, LBError.unknownError {
            throw kind.indeterminateError
        } catch is CancellationError {
            if await attempt.didStartTransport {
                // URLSession cancellation does not prove that a POST was never
                // committed. Once transport begins, force reconciliation and
                // prohibit an immediate duplicate mutation.
                throw kind.indeterminateError
            }
            throw CancellationError()
        } catch {
            // A transport failure can arrive after the server committed the
            // POST. Never label that as a definite failure or retry it.
            throw kind.indeterminateError
        }
    }

    private func invalidateCaches(for kind: MutationKind) async {
        if kind == .edit {
            // Privacy may have changed, so every public/authenticated detail
            // scope must be discarded before another viewer can read it.
            await detailCache.removeAll()
        }
        // Create and edit both change profile playlist metadata/list contents.
        await profilePageCache.removeAll()
    }

    private static func requiresReconciliation(_ error: any Error) -> Bool {
        guard let error = error as? PlaylistMutationProviderError else { return false }
        return error.isIndeterminate
    }

    private static func transportMetadata(
        _ draft: PlaylistMetadataDraft,
        ownerUsername: String
    ) throws -> LBPlaylistMutationMetadata {
        let draft = try draft.normalized(ownerUsername: ownerUsername)
        return LBPlaylistMutationMetadata(
            title: draft.title,
            annotation: draft.optionalAnnotation,
            isPublic: draft.isPublic,
            collaborators: draft.collaborators
        )
    }

    private enum MutationKind {
        case create
        case edit

        var indeterminateError: PlaylistMutationProviderError {
            switch self {
            case .create: .indeterminateCreation
            case .edit: .indeterminateEdit
            }
        }
    }

    private actor MutationAttemptState {
        private(set) var didStartTransport = false

        func markTransportStarted() {
            didStartTransport = true
        }
    }
}

enum PlaylistMutationProviderError: LocalizedError, Sendable {
    case invalidAuthentication
    case notOwner
    case deleteNotOwner
    case notCollaborator
    case playlistUnavailable
    case rejected
    case removalRejected
    case copyRejected
    case indeterminateCreation
    case indeterminateEdit
    case indeterminateAppend
    case indeterminateCopy
    case indeterminateRemoval
    case reorderRejected
    case indeterminateReorder
    case deleteRejected
    case indeterminateDeletion

    var isIndeterminate: Bool {
        switch self {
        case .indeterminateCreation, .indeterminateEdit, .indeterminateAppend, .indeterminateCopy, .indeterminateRemoval, .indeterminateReorder, .indeterminateDeletion: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            String(localized: "Your ListenBrainz token no longer authorizes playlist changes.")
        case .notOwner:
            String(localized: "Only the playlist owner can change its name, description, or privacy.")
        case .deleteNotOwner:
            String(localized: "Only the playlist owner can delete it.")
        case .notCollaborator:
            String(localized: "Only a playlist owner or collaborator can change its tracks.")
        case .playlistUnavailable:
            String(localized: "This playlist was removed or is no longer available to your account.")
        case .rejected:
            String(localized: "ListenBrainz couldn’t save these playlist details. Check the name and try again.")
        case .removalRejected:
            String(localized: "ListenBrainz couldn’t remove the selected tracks. Refresh the playlist and try again.")
        case .copyRejected:
            String(localized: "ListenBrainz couldn’t duplicate this playlist. Reload it and try again.")
        case .indeterminateCreation:
            String(localized: "ListenBrainz may have created this playlist, but the response was lost. Check Owned Playlists before trying again so you don’t create a duplicate.")
        case .indeterminateEdit:
            String(localized: "ListenBrainz may have saved this edit, but the response was lost. Close this editor and reload the playlist before trying again.")
        case .indeterminateAppend:
            String(localized: "ListenBrainz may have added this recording, but the response was lost. Inspect the playlist before trying again so you don’t add a duplicate.")
        case .indeterminateCopy:
            String(localized: "ListenBrainz may have duplicated this playlist, but the response was lost. Check Owned Playlists before trying again so you don’t create another copy.")
        case .indeterminateRemoval:
            String(localized: "ListenBrainz may have completed the removal, but the response was lost. Refresh the playlist before removing more tracks.")
        case .reorderRejected:
            String(localized: "ListenBrainz couldn’t save this track order. Refresh the playlist and try again.")
        case .indeterminateReorder:
            String(localized: "Track changes need review. ListenBrainz may have moved or removed a track, so refresh the playlist before changing it again.")
        case .deleteRejected:
            String(localized: "ListenBrainz couldn’t delete this playlist. Check it and try again.")
        case .indeterminateDeletion:
            String(localized: "ListenBrainz may have deleted this playlist, but the response was lost. Check again before trying to delete it.")
        }
    }
}
