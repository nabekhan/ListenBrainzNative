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

private struct LivePlaylistMutationTransport: PlaylistMutationTransport {
    let client: LBClient

    func create(metadata: LBPlaylistMutationMetadata) async throws -> UUID {
        try await client.core.createPlaylist(metadata: metadata)
    }

    func edit(mbid: UUID, metadata: LBPlaylistMutationMetadata) async throws {
        try await client.core.editPlaylist(mbid: mbid, metadata: metadata)
    }
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
    case playlistUnavailable
    case rejected
    case indeterminateCreation
    case indeterminateEdit

    var isIndeterminate: Bool {
        switch self {
        case .indeterminateCreation, .indeterminateEdit: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            "Your ListenBrainz token no longer authorizes playlist changes."
        case .notOwner:
            "Only the playlist owner can change its name, description, or privacy."
        case .playlistUnavailable:
            "This playlist was removed or is no longer available to your account."
        case .rejected:
            "ListenBrainz couldn’t save these playlist details. Check the name and try again."
        case .indeterminateCreation:
            "ListenBrainz may have created this playlist, but the response was lost. Check Owned Playlists before trying again so you don’t create a duplicate."
        case .indeterminateEdit:
            "ListenBrainz may have saved this edit, but the response was lost. Close this editor and reload the playlist before trying again."
        }
    }
}
