import Foundation
import Observation

enum EntityDetailPhase: Equatable {
    case idle
    case loading
    case refreshing
    case ready
    case unavailable
    case failed(String)
}

@MainActor
@Observable
final class ReleaseDetailModel {
    let seed: ReleaseSeed
    private let provider: any ConcreteReleaseDetailProviding
    private let cache: EntityDetailCache<UUID, ReleaseDetail>

    private(set) var detail: ReleaseDetail?
    private(set) var phase: EntityDetailPhase = .idle
    private(set) var refreshMessage: String?
    private var didLoad = false
    private var requestID = UUID()

    init(
        seed: ReleaseSeed,
        provider: (any ConcreteReleaseDetailProviding)? = nil,
        cache: EntityDetailCache<UUID, ReleaseDetail> = EntityDetailCaches.releases
    ) {
        self.seed = seed
        self.provider = provider ?? MusicBrainzReleaseDetailProvider()
        self.cache = cache
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        if let cached = await cache.value(for: seed.mbid) {
            detail = cached.value
            if cached.isFresh {
                phase = .ready
                return
            }
            phase = .refreshing
        } else {
            phase = .loading
        }
        await fetch()
    }

    func refresh() async {
        requestID = UUID()
        refreshMessage = nil
        phase = detail == nil ? .loading : .refreshing
        await fetch()
    }

    private func fetch() async {
        let id = UUID()
        requestID = id
        do {
            let value = try await provider.release(seed: seed)
            try Task.checkCancellation()
            guard requestID == id else { return }
            detail = value
            refreshMessage = nil
            phase = .ready
            await cache.save(value, for: seed.mbid)
        } catch is CancellationError {
            guard requestID == id else { return }
            didLoad = false
            phase = detail == nil ? .idle : .ready
        } catch {
            guard requestID == id else { return }
            if detail == nil {
                phase = .failed(error.localizedDescription)
            } else {
                refreshMessage = error.localizedDescription
                phase = .ready
            }
        }
    }
}

@MainActor
@Observable
final class ReleaseGroupDetailModel {
    let seed: SearchReleaseGroup
    private let provider: any ReleaseDetailProviding
    private let cache: EntityDetailCache<UUID, ReleaseGroupDetail>

    private(set) var detail: ReleaseGroupDetail?
    private(set) var phase: EntityDetailPhase = .idle
    private(set) var refreshMessage: String?
    private var didLoad = false
    private var requestID = UUID()

    init(
        seed: SearchReleaseGroup,
        token: String,
        provider: (any ReleaseDetailProviding)? = nil,
        cache: EntityDetailCache<UUID, ReleaseGroupDetail> = EntityDetailCaches.releaseGroups
    ) {
        self.seed = seed
        self.provider = provider ?? ListenBrainzMediaDetailProvider(token: token)
        self.cache = cache
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true

        if let cached = await cache.value(for: seed.mbid) {
            detail = cached.value
            if cached.isFresh {
                phase = .ready
                return
            }
            phase = .refreshing
        } else {
            phase = .loading
        }
        await fetch()
    }

    func refresh() async {
        requestID = UUID()
        refreshMessage = nil
        phase = detail == nil ? .loading : .refreshing
        await fetch()
    }

    private func fetch() async {
        let id = UUID()
        requestID = id
        do {
            let value = try await provider.releaseGroup(mbid: seed.mbid)
            try Task.checkCancellation()
            guard requestID == id else { return }
            guard let value else {
                phase = detail == nil ? .unavailable : .ready
                return
            }
            detail = value
            refreshMessage = nil
            phase = .ready
            await cache.save(value, for: seed.mbid)
        } catch is CancellationError {
            guard requestID == id else { return }
            didLoad = false
            phase = detail == nil ? .idle : .ready
        } catch {
            guard requestID == id else { return }
            if detail == nil {
                phase = .failed(error.localizedDescription)
            } else {
                refreshMessage = error.localizedDescription
                phase = .ready
            }
        }
    }
}

@MainActor
@Observable
final class PlaylistDetailModel {
    let seed: SearchPlaylist
    let account: Account
    private let provider: any PlaylistDetailProviding
    private let cache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>

    private(set) var detail: PlaylistDetail?
    private(set) var phase: EntityDetailPhase = .idle
    private(set) var refreshMessage: String?
    private var didLoad = false
    private var requestID = UUID()

    init(
        seed: SearchPlaylist,
        account: Account,
        provider: (any PlaylistDetailProviding)? = nil,
        cache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists
    ) {
        self.seed = seed
        self.account = account
        self.provider = provider ?? ListenBrainzMediaDetailProvider(token: account.token)
        self.cache = cache
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        guard let mbid = seed.playlistMBID else {
            phase = .failed(MediaDetailError.invalidPlaylistIdentifier.localizedDescription)
            return
        }

        if let cached = await cache.value(for: cacheKey(mbid: mbid)) {
            detail = cached.value
            if cached.isFresh {
                phase = .ready
                return
            }
            phase = .refreshing
        } else {
            phase = .loading
        }
        await fetch(mbid: mbid)
    }

    /// Editing a full metadata snapshot must start from a network-confirmed
    /// value, not a fresh-looking cache entry. The editor calls this again at
    /// save time and refuses to overwrite metadata that changed meanwhile.
    func revalidateForEditing() async throws -> PlaylistDetail {
        guard let mbid = seed.playlistMBID else {
            let error = MediaDetailError.invalidPlaylistIdentifier
            phase = .failed(error.localizedDescription)
            throw error
        }

        let id = UUID()
        requestID = id
        refreshMessage = nil
        phase = detail == nil ? .loading : .refreshing
        do {
            let value = try await provider.playlist(mbid: mbid)
            try Task.checkCancellation()
            guard requestID == id else { throw CancellationError() }
            detail = value
            phase = .ready
            await removePublicCacheIfPrivate(value)
            await cache.save(value, for: cacheKey(mbid: mbid))
            return value
        } catch is CancellationError {
            guard requestID == id else { throw CancellationError() }
            didLoad = false
            phase = detail == nil ? .idle : .ready
            throw CancellationError()
        } catch {
            guard requestID == id else { throw CancellationError() }
            if detail == nil {
                phase = .failed(error.localizedDescription)
            } else {
                refreshMessage = error.localizedDescription
                phase = .ready
            }
            throw error
        }
    }

    func refresh() async {
        guard let mbid = seed.playlistMBID else {
            phase = .failed(MediaDetailError.invalidPlaylistIdentifier.localizedDescription)
            return
        }
        requestID = UUID()
        refreshMessage = nil
        phase = detail == nil ? .loading : .refreshing
        await fetch(mbid: mbid)
    }

    func reconcileAfterConfirmedEdit(_ draft: PlaylistMetadataDraft) async {
        guard let current = detail else { return }
        let normalized: PlaylistMetadataDraft
        do {
            normalized = try draft.normalized(ownerUsername: account.username)
        } catch {
            refreshMessage = error.localizedDescription
            return
        }

        let confirmed = PlaylistDetail(
            mbid: current.mbid,
            title: normalized.title,
            creator: current.creator,
            annotation: normalized.optionalAnnotation,
            createdAt: current.createdAt,
            lastModifiedAt: current.lastModifiedAt,
            isPublic: normalized.isPublic,
            createdFor: current.createdFor,
            collaborators: normalized.collaborators,
            copiedFrom: current.copiedFrom,
            tracks: current.tracks
        )
        detail = confirmed
        phase = .ready
        refreshMessage = nil
        // A public-to-private edit must not leave any viewer scope with a
        // formerly public copy. The authenticated confirmed value is restored
        // only after every scope has been discarded.
        await cache.removeAll()
        await cache.save(confirmed, for: cacheKey(mbid: current.mbid))
        await refresh()
    }

    private func fetch(mbid: UUID) async {
        let id = UUID()
        requestID = id
        do {
            let value = try await provider.playlist(mbid: mbid)
            try Task.checkCancellation()
            guard requestID == id else { return }
            detail = value
            refreshMessage = nil
            phase = .ready
            await removePublicCacheIfPrivate(value)
            await cache.save(value, for: cacheKey(mbid: mbid))
        } catch is CancellationError {
            guard requestID == id else { return }
            didLoad = false
            phase = detail == nil ? .idle : .ready
        } catch {
            guard requestID == id else { return }
            if detail == nil {
                phase = .failed(error.localizedDescription)
            } else {
                refreshMessage = error.localizedDescription
                phase = .ready
            }
        }
    }


    private func cacheKey(mbid: UUID) -> PlaylistDetailCacheKey {
        PlaylistDetailCacheKey(mbid: mbid, accessScope: .init(account: account))
    }

    private func removePublicCacheIfPrivate(_ value: PlaylistDetail) async {
        guard account.isAuthenticated, !value.isPublic else { return }
        await cache.removeValue(for: PlaylistDetailCacheKey(
            mbid: value.mbid,
            accessScope: .publicOnly
        ))
    }
}

enum PlaylistDetailAccessScope: Hashable, Sendable {
    case publicOnly
    case authenticatedViewer(String)

    init(account: Account) {
        if account.isAuthenticated {
            self = .authenticatedViewer(
                account.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        } else {
            self = .publicOnly
        }
    }
}

struct PlaylistDetailCacheKey: Hashable, Sendable {
    let mbid: UUID
    let accessScope: PlaylistDetailAccessScope
}
