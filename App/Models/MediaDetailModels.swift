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
    private let provider: any PlaylistDetailProviding
    private let cache: EntityDetailCache<UUID, PlaylistDetail>

    private(set) var detail: PlaylistDetail?
    private(set) var phase: EntityDetailPhase = .idle
    private(set) var refreshMessage: String?
    private var didLoad = false
    private var requestID = UUID()

    init(
        seed: SearchPlaylist,
        token: String,
        provider: (any PlaylistDetailProviding)? = nil,
        cache: EntityDetailCache<UUID, PlaylistDetail> = EntityDetailCaches.playlists
    ) {
        self.seed = seed
        self.provider = provider ?? ListenBrainzMediaDetailProvider(token: token)
        self.cache = cache
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        guard let mbid = seed.playlistMBID else {
            phase = .failed(MediaDetailError.invalidPlaylistIdentifier.localizedDescription)
            return
        }

        if let cached = await cache.value(for: mbid) {
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
            await cache.save(value, for: mbid)
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
