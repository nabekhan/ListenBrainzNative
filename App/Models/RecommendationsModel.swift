import Foundation
import Observation

enum RecommendationsPhase: Equatable {
    case idle
    case loading
    case refreshing
    case ready
    case unavailable
    case failed(String)
}

struct RecommendationPageKey: Hashable, Sendable {
    let username: String
    let offset: Int
    let count: Int
}

enum RecommendationCaches {
    static let recordingPages = EntityDetailCache<RecommendationPageKey, RecordingRecommendationPage>(
        timeToLive: 10 * 60,
        maximumEntryCount: 40
    )
    static let playlists = EntityDetailCache<String, [SearchPlaylist]>(
        timeToLive: 10 * 60,
        maximumEntryCount: 40
    )
}

@MainActor
@Observable
final class RecommendationsModel {
    let account: Account

    private let provider: any RecommendationsProviding
    private let recordingCache: EntityDetailCache<RecommendationPageKey, RecordingRecommendationPage>
    private let playlistCache: EntityDetailCache<String, [SearchPlaylist]>
    private let pageSize: Int

    private(set) var recommendations: [RecommendedRecording] = []
    private(set) var playlists: [SearchPlaylist] = []
    private(set) var recordingPhase: RecommendationsPhase = .idle
    private(set) var playlistPhase: RecommendationsPhase = .idle
    private(set) var lastUpdated: Date?
    private(set) var totalCount = 0
    private(set) var nextOffset = 0
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?
    private(set) var recordingRefreshMessage: String?
    private(set) var playlistRefreshMessage: String?

    private var recordingRequestID = UUID()
    private var playlistRequestID = UUID()

    init(
        account: Account,
        provider: (any RecommendationsProviding)? = nil,
        recordingCache: EntityDetailCache<RecommendationPageKey, RecordingRecommendationPage> = RecommendationCaches.recordingPages,
        playlistCache: EntityDetailCache<String, [SearchPlaylist]> = RecommendationCaches.playlists,
        pageSize: Int = 25
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzRecommendationsProvider(token: account.token)
        self.recordingCache = recordingCache
        self.playlistCache = playlistCache
        self.pageSize = max(1, pageSize)
    }

    var hasMoreRecommendations: Bool {
        nextOffset < totalCount
    }

    func loadRecommendations() async {
        guard recordingPhase == .idle else { return }
        await loadRecommendationPage(offset: 0, force: false)
    }

    func refreshRecommendations() async {
        guard !isLoadingMore,
              recordingPhase != .loading,
              recordingPhase != .refreshing
        else { return }
        recordingRequestID = UUID()
        loadMoreError = nil
        recordingRefreshMessage = nil
        await loadRecommendationPage(offset: 0, force: true)
    }

    func loadMoreRecommendations() async {
        guard recordingPhase == .ready,
              hasMoreRecommendations,
              !isLoadingMore
        else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        await loadRecommendationPage(offset: nextOffset, force: false, appending: true)
    }

    func loadPlaylists() async {
        guard playlistPhase == .idle else { return }
        await fetchPlaylists(force: false)
    }

    func refreshPlaylists() async {
        guard playlistPhase != .loading,
              playlistPhase != .refreshing
        else { return }
        playlistRequestID = UUID()
        playlistRefreshMessage = nil
        await fetchPlaylists(force: true)
    }

    private func loadRecommendationPage(
        offset: Int,
        force: Bool,
        appending: Bool = false
    ) async {
        let key = RecommendationPageKey(
            username: account.username.lowercased(),
            offset: offset,
            count: pageSize
        )

        if !force, let cached = await recordingCache.value(for: key) {
            apply(cached.value, appending: appending)
            if cached.isFresh {
                recordingPhase = .ready
                return
            }
        }

        if !appending {
            recordingPhase = recommendations.isEmpty ? .loading : .refreshing
        }
        let requestID = UUID()
        recordingRequestID = requestID

        do {
            let page = try await provider.recordingRecommendations(
                username: account.username,
                offset: offset,
                count: pageSize
            )
            try Task.checkCancellation()
            guard recordingRequestID == requestID else { return }

            guard let page else {
                if !appending {
                    recommendations = []
                    lastUpdated = nil
                    totalCount = 0
                    nextOffset = 0
                    recordingPhase = .unavailable
                }
                return
            }

            apply(page, appending: appending)
            recordingRefreshMessage = nil
            loadMoreError = nil
            recordingPhase = .ready
            await recordingCache.save(page, for: key)
        } catch is CancellationError {
            guard recordingRequestID == requestID else { return }
            recordingPhase = recommendations.isEmpty ? .idle : .ready
        } catch {
            guard recordingRequestID == requestID else { return }
            if appending {
                loadMoreError = error.localizedDescription
            } else if recommendations.isEmpty {
                recordingPhase = .failed(error.localizedDescription)
            } else {
                recordingRefreshMessage = error.localizedDescription
                recordingPhase = .ready
            }
        }
    }

    private func apply(_ page: RecordingRecommendationPage, appending: Bool) {
        if appending {
            var seen = Set(recommendations.map(\.id))
            recommendations.append(contentsOf: page.recommendations.filter { seen.insert($0.id).inserted })
        } else {
            recommendations = page.recommendations
        }
        lastUpdated = page.lastUpdated
        totalCount = page.totalCount
        nextOffset = max(nextOffset, page.nextOffset)
        if !appending { nextOffset = page.nextOffset }
    }

    private func fetchPlaylists(force: Bool) async {
        let key = account.username.lowercased()
        if !force, let cached = await playlistCache.value(for: key) {
            playlists = cached.value
            if cached.isFresh {
                playlistPhase = .ready
                return
            }
        }

        playlistPhase = playlists.isEmpty ? .loading : .refreshing
        let requestID = UUID()
        playlistRequestID = requestID
        do {
            let values = try await provider.recommendationPlaylists(username: account.username)
            try Task.checkCancellation()
            guard playlistRequestID == requestID else { return }
            playlists = values
            playlistRefreshMessage = nil
            playlistPhase = .ready
            await playlistCache.save(values, for: key)
        } catch is CancellationError {
            guard playlistRequestID == requestID else { return }
            playlistPhase = playlists.isEmpty ? .idle : .ready
        } catch {
            guard playlistRequestID == requestID else { return }
            if playlists.isEmpty {
                playlistPhase = .failed(error.localizedDescription)
            } else {
                playlistRefreshMessage = error.localizedDescription
                playlistPhase = .ready
            }
        }
    }
}
