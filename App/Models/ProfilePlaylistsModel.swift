import Foundation
import Observation

enum ProfilePlaylistsPhase: Equatable {
    case idle
    case loading
    case refreshing
    case ready
    case failed(String)
}

struct ProfilePlaylistCategoryState: Equatable {
    var playlists: [SearchPlaylist] = []
    var phase: ProfilePlaylistsPhase = .idle
    var totalCount: Int?
    var nextOffset = 0
    var hasMore = false
    var isLoadingMore = false
    var loadMoreError: String?
    var refreshMessage: String?
    var loadMoreRetryOffset: Int?
}

enum ProfilePlaylistAccessScope: Hashable, Sendable {
    case publicOnly
    case authenticatedViewer(String)
}

struct ProfilePlaylistPageKey: Hashable, Sendable {
    let username: String
    let accessScope: ProfilePlaylistAccessScope
    let category: ProfilePlaylistCategory
    let offset: Int
    let count: Int
}

enum ProfilePlaylistCaches {
    static let pages = EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>(
        timeToLive: 10 * 60,
        maximumEntryCount: 100
    )
}

@MainActor
@Observable
final class ProfilePlaylistsModel {
    let account: Account

    private let provider: any ProfilePlaylistsProviding
    private let cache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>
    private let pageSize: Int
    @ObservationIgnored private let mutationJournal: PlaylistMutationJournal
    private var requestIDs: [ProfilePlaylistCategory: UUID] = [:]
    private var requestedOffsets: [ProfilePlaylistCategory: Set<Int>] = [:]
    private var lastProcessedJournalRevision = 0
    private var isReconcilingJournal = false
    private var loadWaiters: [
        ProfilePlaylistCategory: [UUID: CheckedContinuation<Void, Never>]
    ] = [:]

    private(set) var states: [ProfilePlaylistCategory: ProfilePlaylistCategoryState] = Dictionary(
        uniqueKeysWithValues: ProfilePlaylistCategory.allCases.map { ($0, .init()) }
    )

    init(
        account: Account,
        provider: (any ProfilePlaylistsProviding)? = nil,
        cache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages,
        pageSize: Int = 20,
        mutationJournal: PlaylistMutationJournal? = nil
    ) {
        let resolvedJournal = mutationJournal ?? .shared
        self.account = account
        self.provider = provider ?? ListenBrainzProfilePlaylistsProvider(token: account.token)
        self.cache = cache
        self.pageSize = min(max(pageSize, 1), 100)
        self.mutationJournal = resolvedJournal
        lastProcessedJournalRevision = resolvedJournal.revision
    }

    func state(for category: ProfilePlaylistCategory) -> ProfilePlaylistCategoryState {
        states[category] ?? .init()
    }

    /// Revoked authentication or playlist visibility must remove both cached
    /// and currently rendered private destinations. Ordinary network failures
    /// intentionally retain stale values instead.
    func discardAccessSensitiveState(message: String) async {
        requestIDs.removeAll()
        requestedOffsets.removeAll()
        for category in ProfilePlaylistCategory.allCases {
            var cleared = ProfilePlaylistCategoryState()
            cleared.phase = .failed(message)
            states[category] = cleared
            resumeLoadWaiters(category: category)
        }
        await cache.removeAll()
    }

    /// Categories intentionally load independently so visiting a profile does
    /// not make an extra request for a tab that the user never opens.
    func load(category: ProfilePlaylistCategory) async {
        if state(for: category).phase == .loading {
            await waitForLoadToSettle(category: category)
            guard !Task.isCancelled else { return }
            if state(for: category).phase == .idle {
                await load(category: category)
            }
            return
        }
        guard state(for: category).phase == .idle else { return }
        var current = state(for: category)
        current.phase = .loading
        current.refreshMessage = nil
        states[category] = current
        await fetch(category: category, offset: 0, force: false, appending: false)
    }

    func refresh(category: ProfilePlaylistCategory) async {
        var current = state(for: category)
        guard current.phase != .loading,
              current.phase != .refreshing,
              !current.isLoadingMore
        else { return }
        requestIDs[category] = UUID() // invalidates an in-flight initial load
        requestedOffsets[category] = []
        current.phase = current.playlists.isEmpty ? .loading : .refreshing
        current.loadMoreRetryOffset = nil
        current.loadMoreError = nil
        current.refreshMessage = nil
        states[category] = current
        await fetch(category: category, offset: 0, force: true, appending: false)
    }

    func refreshAfterMutation() async {
        await cache.removeAll()
        if state(for: .owned).phase == .idle {
            await load(category: .owned)
        } else {
            await refresh(category: .owned)
        }
    }

    func reconcileAfterConfirmedEdit(_ edit: ConfirmedPlaylistMetadataEdit) async {
        guard account.isAuthenticated,
              Self.normalized(account.username) == Self.normalized(edit.ownerUsername),
              let draft = try? edit.draft.normalized(ownerUsername: account.username)
        else { return }

        // Every cached page can contain this row at a different offset. Clear
        // the account-scoped page source, then update already-visible state so
        // returning from detail never flashes stale privacy or metadata.
        await cache.removeAll()
        for category in ProfilePlaylistCategory.allCases {
            var current = state(for: category)
            current.playlists = current.playlists.map { playlist in
                guard playlist.playlistMBID == edit.mbid else { return playlist }
                return SearchPlaylist(
                    title: draft.title,
                    creator: playlist.creator,
                    annotation: draft.optionalAnnotation,
                    identifier: playlist.identifier,
                    isPublic: draft.isPublic,
                    lastModifiedAt: playlist.lastModifiedAt,
                    createdAt: playlist.createdAt,
                    durationMilliseconds: playlist.durationMilliseconds,
                    createdFor: playlist.createdFor,
                    collaborators: draft.collaborators,
                    copiedFrom: playlist.copiedFrom,
                    recommendationType: playlist.recommendationType,
                    expiresAt: playlist.expiresAt
                )
            }
            states[category] = current
        }
    }

    func reconcileAfterConfirmedCopy(_ copy: ConfirmedPlaylistCopy) async {
        guard account.isAuthenticated,
              Self.normalized(account.username) == Self.normalized(copy.ownerUsername)
        else { return }

        await cache.removeAll()
        var owned = state(for: .owned)
        // Preserve lazy loading: an unseen Owned tab will fetch the canonical
        // server page later. An already-loaded tab receives the confirmed row
        // immediately so navigating back cannot show a stale list.
        guard owned.phase != .idle else { return }
        if !owned.playlists.contains(where: { $0.playlistMBID == copy.playlist.playlistMBID }) {
            owned.playlists.insert(copy.playlist, at: 0)
            if let totalCount = owned.totalCount {
                owned.totalCount = totalCount + 1
            }
        }
        if case .failed = owned.phase {
            owned.phase = .ready
        }
        states[.owned] = owned
    }

    func reconcileAfterJournalEvent(_ event: PlaylistJournalEvent) async {
        switch event {
        case let .edit(edit):
            await reconcileAfterConfirmedEdit(edit)
        case let .copy(copy):
            await reconcileAfterConfirmedCopy(copy)
        case let .accessLoss(accessLoss):
            await reconcileAfterAccessLoss(accessLoss)
        }
    }

    /// SwiftUI restarts revision-keyed tasks when another event arrives. Keep
    /// draining in one model-owned loop so a cancelled predecessor cannot
    /// replay an older copy event after a later access-loss purge.
    func reconcileJournal() async {
        guard !isReconcilingJournal else { return }
        isReconcilingJournal = true
        defer { isReconcilingJournal = false }

        while true {
            let pending = mutationJournal.entries(after: lastProcessedJournalRevision)
            guard !pending.isEmpty else { return }
            for entry in pending {
                await reconcileAfterJournalEvent(entry.event)
                lastProcessedJournalRevision = entry.revision
            }
        }
    }

    func reconcileAfterAccessLoss(_ event: PlaylistAccessLossEvent) async {
        guard account.isAuthenticated,
              Self.normalized(account.username) == Self.normalized(event.viewerUsername)
        else { return }

        switch event.reason {
        case .authentication:
            await discardAccessSensitiveState(message: event.message)
        case .sourceVisibility:
            // The source may have appeared in either category. Remove only
            // that row from rendered state. Every in-flight request and page
            // cursor is invalidated first: a server row may have shifted at
            // any offset, and an older request must not restore private data.
            for category in ProfilePlaylistCategory.allCases {
                requestIDs[category] = UUID()
                requestedOffsets[category] = []
                var current = state(for: category)
                let originalCount = current.playlists.count
                current.playlists.removeAll { $0.playlistMBID == event.sourceMBID }
                let removedCount = originalCount - current.playlists.count
                if removedCount > 0, let totalCount = current.totalCount {
                    current.totalCount = max(0, totalCount - removedCount)
                } else if removedCount == 0, current.phase != .idle {
                    current.totalCount = nil
                }
                if current.phase != .idle {
                    current.phase = .ready
                    current.nextOffset = 0
                    current.hasMore = false
                    current.isLoadingMore = false
                    current.loadMoreError = nil
                    current.loadMoreRetryOffset = nil
                    current.refreshMessage = "Playlist access changed. Refresh to load the latest list."
                }
                states[category] = current
                resumeLoadWaiters(category: category)
            }
            await cache.removeAll()
        }
    }

    func loadMore(category: ProfilePlaylistCategory) async {
        var current = state(for: category)
        let offset = current.loadMoreRetryOffset ?? current.nextOffset
        guard current.phase == .ready,
              current.loadMoreRetryOffset != nil || current.hasMore,
              !current.isLoadingMore,
              !requestedOffsets[category, default: []].contains(offset)
        else { return }
        current.isLoadingMore = true
        current.loadMoreError = nil
        states[category] = current
        defer {
            var completed = state(for: category)
            completed.isLoadingMore = false
            states[category] = completed
        }
        await fetch(category: category, offset: offset, force: false, appending: true)
    }

    private func fetch(
        category: ProfilePlaylistCategory,
        offset: Int,
        force: Bool,
        appending: Bool
    ) async {
        let key = ProfilePlaylistPageKey(
            username: Self.normalized(account.username),
            accessScope: accessScope,
            category: category,
            offset: max(offset, 0),
            count: pageSize
        )

        if !force, let cached = await cache.value(for: key) {
            if cached.isFresh {
                apply(cached.value, category: category, requestedOffset: offset, appending: appending)
                var ready = state(for: category)
                ready.phase = .ready
                ready.refreshMessage = nil
                ready.loadMoreError = nil
                ready.loadMoreRetryOffset = nil
                states[category] = ready
                if !appending { resumeLoadWaiters(category: category) }
                return
            }
            // A stale first page is useful immediately while it revalidates.
            // A stale appended page is not: applying it would move the cursor
            // before revalidation and could retain rows the server removed.
            if !appending {
                apply(cached.value, category: category, requestedOffset: offset, appending: false)
            }
        }

        var current = state(for: category)
        if appending {
            current.phase = .ready
        } else {
            current.phase = current.playlists.isEmpty ? .loading : .refreshing
            current.refreshMessage = nil
        }
        states[category] = current

        let requestID = UUID()
        requestIDs[category] = requestID
        requestedOffsets[category, default: []].insert(offset)
        do {
            let page = try await provider.page(
                username: account.username,
                category: category,
                offset: offset,
                count: pageSize
            )
            try Task.checkCancellation()
            guard requestIDs[category] == requestID else { return }
            apply(page, category: category, requestedOffset: offset, appending: appending)
            var completed = state(for: category)
            completed.phase = .ready
            completed.refreshMessage = nil
            completed.loadMoreError = nil
            completed.loadMoreRetryOffset = nil
            states[category] = completed
            if !appending { resumeLoadWaiters(category: category) }
            await cache.save(page, for: key)
        } catch is CancellationError {
            guard requestIDs[category] == requestID else { return }
            requestedOffsets[category, default: []].remove(offset)
            var cancelled = state(for: category)
            cancelled.phase = cancelled.playlists.isEmpty ? .idle : .ready
            if appending { cancelled.loadMoreRetryOffset = offset }
            states[category] = cancelled
            if !appending { resumeLoadWaiters(category: category) }
        } catch {
            guard requestIDs[category] == requestID else { return }
            if PlaylistAccessFailurePolicy.requiresPurge(error) {
                await discardAccessSensitiveState(message: error.localizedDescription)
                return
            }
            // A transient failure must not turn a valid next page into a
            // permanently visited offset; the UI can safely offer Retry.
            requestedOffsets[category, default: []].remove(offset)
            var failed = state(for: category)
            if appending {
                failed.loadMoreError = error.localizedDescription
                failed.loadMoreRetryOffset = offset
                failed.phase = .ready
            } else if failed.playlists.isEmpty {
                failed.phase = .failed(error.localizedDescription)
            } else {
                failed.refreshMessage = error.localizedDescription
                failed.phase = .ready
            }
            states[category] = failed
            if !appending { resumeLoadWaiters(category: category) }
        }
    }

    private func apply(
        _ page: ProfilePlaylistPage,
        category: ProfilePlaylistCategory,
        requestedOffset: Int,
        appending: Bool
    ) {
        var state = state(for: category)
        let serverOffset = max(page.offset ?? requestedOffset, 0)
        let rawRowCount = page.playlists.count
        let nextOffset = serverOffset + rawRowCount

        if appending {
            var seen = Set(state.playlists.map(\.id))
            state.playlists.append(contentsOf: page.playlists.filter { seen.insert($0.id).inserted })
        } else {
            state.playlists = deduplicated(page.playlists)
        }

        state.totalCount = appending ? (page.totalCount ?? state.totalCount) : page.totalCount
        state.nextOffset = nextOffset
        let requestSize = max(page.requestedCount ?? pageSize, 1)
        let serverClaimsMore = state.totalCount.map { nextOffset < $0 } ?? (rawRowCount >= requestSize)
        // Never retry an offset that the server did not advance beyond. This
        // protects the profile UI from malformed or overlapping page metadata.
        state.hasMore = serverClaimsMore
            && rawRowCount > 0
            && nextOffset > requestedOffset
            && !requestedOffsets[category, default: []].contains(nextOffset)
        if !state.hasMore { state.loadMoreError = nil }
        states[category] = state
    }

    private func deduplicated(_ playlists: [SearchPlaylist]) -> [SearchPlaylist] {
        var seen = Set<String>()
        return playlists.filter { seen.insert($0.id).inserted }
    }

    private static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var accessScope: ProfilePlaylistAccessScope {
        guard account.isAuthenticated else { return .publicOnly }
        return .authenticatedViewer(Self.normalized(account.username))
    }

    private func waitForLoadToSettle(category: ProfilePlaylistCategory) async {
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                loadWaiters[category, default: [:]][waiterID] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelLoadWaiter(waiterID, category: category)
            }
        }
    }

    private func resumeLoadWaiters(category: ProfilePlaylistCategory) {
        guard let waiters = loadWaiters.removeValue(forKey: category) else { return }
        waiters.values.forEach { $0.resume() }
    }

    private func cancelLoadWaiter(_ waiterID: UUID, category: ProfilePlaylistCategory) {
        guard let continuation = loadWaiters[category]?.removeValue(forKey: waiterID) else { return }
        if loadWaiters[category]?.isEmpty == true {
            loadWaiters.removeValue(forKey: category)
        }
        continuation.resume()
    }
}
