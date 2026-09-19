import Foundation
import Observation

@MainActor
@Observable
final class UserDetailModel {
    enum Phase: Equatable {
        case idle
        case loading
        case refreshing
        case ready
        case failed(String)
    }

    enum SectionPhase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let user: SearchUser
    private let provider: any ListeningProvider
    private let cache: UserProfileCache

    private(set) var snapshot = UserProfileSnapshot.empty
    private(set) var phase: Phase = .idle
    private(set) var topArtistsPhase: SectionPhase = .idle
    private(set) var topReleasesPhase: SectionPhase = .idle
    private var didLoadOverview = false
    private var didLoadTopArtists = false
    private var topArtistsNeedRefresh = false
    private var isLoadingTopArtists = false
    private var didLoadTopReleases = false
    private var topReleasesNeedRefresh = false
    private var isLoadingTopReleases = false
    private var overviewRequestID = UUID()
    private var topArtistsRequestID = UUID()
    private var topReleasesRequestID = UUID()
    private let cacheScope: RequestGate.ReadScope

    init(
        user: SearchUser,
        token: String,
        provider: (any ListeningProvider)? = nil,
        cache: UserProfileCache = .shared
    ) {
        self.user = user
        self.provider = provider ?? ListenBrainzProvider(token: token)
        self.cache = cache
        self.cacheScope = .authenticated(token: token)
    }

    var featuredListen: Listen? { snapshot.playingNow ?? snapshot.recentListens.first }

    func load() async {
        guard !didLoadOverview else { return }
        didLoadOverview = true

        if let cached = await cache.value(for: user.username, scope: cacheScope) {
            snapshot = cached.snapshot
            if snapshot.hasLoadedTopArtists {
                didLoadTopArtists = cached.isTopArtistsFresh
                topArtistsNeedRefresh = !cached.isTopArtistsFresh
                topArtistsPhase = .ready
            }
            if snapshot.hasLoadedTopReleases {
                didLoadTopReleases = cached.isTopReleasesFresh
                topReleasesNeedRefresh = !cached.isTopReleasesFresh
                topReleasesPhase = .ready
            }
            if cached.isOverviewFresh {
                phase = .ready
                return
            }
            phase = .refreshing
        } else {
            phase = .loading
        }

        await refreshOverview()
    }

    func refresh() async {
        let shouldRefreshTopArtists = snapshot.hasLoadedTopArtists && !isLoadingTopArtists
        let shouldRefreshTopReleases = snapshot.hasLoadedTopReleases && !isLoadingTopReleases
        overviewRequestID = UUID()
        if shouldRefreshTopArtists {
            topArtistsRequestID = UUID()
            didLoadTopArtists = false
            topArtistsNeedRefresh = true
        }
        if shouldRefreshTopReleases {
            topReleasesRequestID = UUID()
            didLoadTopReleases = false
            topReleasesNeedRefresh = true
        }
        phase = snapshot.recentListens.isEmpty ? .loading : .refreshing
        await refreshOverview()
        if !Task.isCancelled, shouldRefreshTopArtists {
            await loadTopArtists(retrying: true)
        }
        if !Task.isCancelled, shouldRefreshTopReleases {
            await loadTopReleases(retrying: true)
        }
    }

    func loadTopArtists(retrying: Bool = false) async {
        let needsNetworkLoad = retrying || topArtistsNeedRefresh || !snapshot.hasLoadedTopArtists
        if !needsNetworkLoad {
            topArtistsPhase = .ready
            return
        }
        guard !isLoadingTopArtists else { return }
        guard !didLoadTopArtists || retrying else { return }
        didLoadTopArtists = true
        isLoadingTopArtists = true
        topArtistsPhase = snapshot.topArtists.isEmpty ? .loading : .ready
        let requestID = UUID()
        topArtistsRequestID = requestID
        defer {
            if topArtistsRequestID == requestID {
                isLoadingTopArtists = false
            }
        }

        do {
            let artists = try await provider.topArtists(username: user.username, count: 12)
            guard topArtistsRequestID == requestID else { return }
            snapshot.topArtists = artists
            snapshot.hasLoadedTopArtists = true
            snapshot.savedAt = .now
            topArtistsNeedRefresh = false
            topArtistsPhase = .ready
            await cache.saveTopArtists(snapshot, for: user.username, scope: cacheScope)
        } catch is CancellationError {
            guard topArtistsRequestID == requestID else { return }
            didLoadTopArtists = false
            topArtistsPhase = snapshot.hasLoadedTopArtists ? .ready : .idle
        } catch {
            guard topArtistsRequestID == requestID else { return }
            didLoadTopArtists = false
            topArtistsPhase = snapshot.topArtists.isEmpty
                ? .failed(error.localizedDescription)
                : .ready
        }
    }

    func loadTopReleases(retrying: Bool = false) async {
        let needsNetworkLoad = retrying || topReleasesNeedRefresh || !snapshot.hasLoadedTopReleases
        if !needsNetworkLoad {
            topReleasesPhase = .ready
            return
        }
        guard !isLoadingTopReleases else { return }
        guard !didLoadTopReleases || retrying else { return }
        didLoadTopReleases = true
        isLoadingTopReleases = true
        topReleasesPhase = snapshot.topReleases.isEmpty ? .loading : .ready
        let requestID = UUID()
        topReleasesRequestID = requestID
        defer {
            if topReleasesRequestID == requestID {
                isLoadingTopReleases = false
            }
        }

        do {
            let releases = try await provider.topReleases(username: user.username, count: 6)
            guard topReleasesRequestID == requestID else { return }
            snapshot.topReleases = releases
            snapshot.hasLoadedTopReleases = true
            snapshot.savedAt = .now
            topReleasesNeedRefresh = false
            topReleasesPhase = .ready
            await cache.saveTopReleases(snapshot, for: user.username, scope: cacheScope)
        } catch is CancellationError {
            guard topReleasesRequestID == requestID else { return }
            didLoadTopReleases = false
            topReleasesPhase = snapshot.hasLoadedTopReleases ? .ready : .idle
        } catch {
            guard topReleasesRequestID == requestID else { return }
            didLoadTopReleases = false
            topReleasesPhase = snapshot.topReleases.isEmpty
                ? .failed(error.localizedDescription)
                : .ready
        }
    }

    private func refreshOverview() async {
        let requestID = UUID()
        overviewRequestID = requestID
        snapshot.hasLoadedOverview = false

        do {
            let listens = try await provider.recentListens(
                username: user.username,
                before: nil,
                count: 12
            )
            try Task.checkCancellation()
            guard overviewRequestID == requestID else { return }
            snapshot.recentListens = listens
            snapshot.savedAt = .now
            phase = .ready
            await cache.saveOverview(snapshot, for: user.username, scope: cacheScope)

            do {
                let playingNow = try await provider.playingNow(username: user.username)
                try Task.checkCancellation()
                guard overviewRequestID == requestID else { return }
                snapshot.playingNow = playingNow
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Playing Now is optional context; loaded history remains useful.
            }

            do {
                let listenCount = try await provider.listenCount(username: user.username)
                try Task.checkCancellation()
                guard overviewRequestID == requestID else { return }
                snapshot.listenCount = listenCount
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A missing count should not hide a successfully loaded profile.
            }

            guard overviewRequestID == requestID else { return }
            snapshot.hasLoadedOverview = true
            snapshot.savedAt = .now
            phase = .ready
            await cache.saveOverview(snapshot, for: user.username, scope: cacheScope)
        } catch is CancellationError {
            guard overviewRequestID == requestID else { return }
            didLoadOverview = false
            phase = snapshot.recentListens.isEmpty ? .idle : .ready
        } catch {
            guard overviewRequestID == requestID else { return }
            phase = snapshot.recentListens.isEmpty
                ? .failed(error.localizedDescription)
                : .ready
        }
    }
}
