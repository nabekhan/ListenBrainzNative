import Foundation
import Observation

enum RecommendationPreferencesPhase: Equatable {
    case idle
    case loading
    case refreshing
    case ready
    case failed(String)
}

struct RecommendationPreferencesState: Equatable {
    var items: [RecommendationPreference] = []
    var phase: RecommendationPreferencesPhase = .idle
    var totalCount = 0
    var nextOffset = 0
    var hasMore = false
    var isLoadingMore = false
    var refreshMessage: String?
    var loadMoreError: String?
    var removingID: RecommendationPreference.ID?
}

struct RecommendationPreferencesPageKey: Hashable, Sendable {
    let username: String
    let offset: Int
    let count: Int
}

enum RecommendationPreferencesCaches {
    static let pages = EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>(
        timeToLive: 10 * 60,
        maximumEntryCount: 10
    )
}

@MainActor
@Observable
final class RecommendationPreferencesModel {
    static let maximumPageCount = 10
    static let maximumVisibleCount = 200

    let account: Account
    private let provider: any DoNotRecommendProviding
    private let cache: EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>
    private let changes: RecommendationPreferenceChanges
    private let pageSize: Int
    private let afterConditionalCacheSave: (@Sendable () async -> Void)?
    private let changeSourceID = UUID()
    private var generation = UUID()
    private var loadedPageCount = 0

    private(set) var state = RecommendationPreferencesState()
    var notice: DoNotRecommendNotice?

    init(
        account: Account,
        provider: (any DoNotRecommendProviding)? = nil,
        cache: EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage> = RecommendationPreferencesCaches.pages,
        pageSize: Int = 25,
        changes: RecommendationPreferenceChanges = .shared,
        afterConditionalCacheSave: (@Sendable () async -> Void)? = nil
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzDoNotRecommendProvider(token: account.token)
        self.cache = cache
        self.changes = changes
        self.pageSize = min(max(pageSize, 1), 25)
        self.afterConditionalCacheSave = afterConditionalCacheSave
    }

    func load() async {
        guard state.phase == .idle, state.removingID == nil else { return }
        state.phase = .loading
        await fetch(offset: 0, force: false, appending: false)
    }

    func refresh() async {
        guard state.phase != .loading,
              state.phase != .refreshing,
              !state.isLoadingMore,
              state.removingID == nil
        else { return }
        generation = UUID()
        loadedPageCount = 0
        state.phase = state.items.isEmpty ? .loading : .refreshing
        state.refreshMessage = nil
        state.loadMoreError = nil
        await fetch(offset: 0, force: true, appending: false)
    }

    func loadMore() async {
        guard state.phase == .ready,
              state.hasMore,
              !state.isLoadingMore,
              state.removingID == nil,
              loadedPageCount < Self.maximumPageCount,
              state.items.count < Self.maximumVisibleCount
        else { return }
        state.isLoadingMore = true
        state.loadMoreError = nil
        await fetch(offset: state.nextOffset, force: false, appending: true)
    }

    func cancel() {
        generation = UUID()
        state.isLoadingMore = false
        if state.phase == .loading || state.phase == .refreshing {
            state.phase = state.items.isEmpty ? .idle : .ready
        }
    }

    func remove(_ item: RecommendationPreference) async -> Bool {
        guard account.isAuthenticated, state.removingID == nil else { return false }

        // A list read that began before this mutation must not restore or
        // re-cache the item after ListenBrainz removes it.
        generation = UUID()
        state.isLoadingMore = false
        if state.phase == .refreshing { state.phase = .ready }
        state.refreshMessage = nil
        state.loadMoreError = nil
        state.removingID = item.id
        notice = nil
        defer { state.removingID = nil }

        // Clear and notify before dispatch because a cancelled or failed
        // response cannot prove whether the server applied the mutation.
        // A second notification after confirmed success protects another
        // list that explicitly refreshed while this mutation was in flight.
        await cache.removeAll()
        changes.recordChange(for: account.username, sourceID: changeSourceID)
        do {
            try await provider.remove(entity: item.entity, entityMBID: item.entityMBID)
            await cache.removeAll()
            changes.recordChange(for: account.username, sourceID: changeSourceID)
            state.items.removeAll { $0.id == item.id }
            state.totalCount = max(0, state.totalCount - 1)
            state.nextOffset = max(0, state.nextOffset - 1)
            state.hasMore = state.nextOffset < state.totalCount
                && loadedPageCount < Self.maximumPageCount
                && state.items.count < Self.maximumVisibleCount
            notice = .init(
                kind: .confirmation,
                message: String(localized: "The saved choice was removed from ListenBrainz.")
            )
            return true
        } catch is CancellationError {
            return false
        } catch {
            notice = .init(kind: .error, message: Self.mutationErrorMessage(error))
            return false
        }
    }

    func dismissNotice() { notice = nil }

    func observeExternalChange(_ event: RecommendationPreferenceChanges.Event) {
        guard event.sourceID != changeSourceID, state.phase != .idle else { return }
        generation = UUID()
        state.isLoadingMore = false
        state.loadMoreError = nil
        state.phase = .ready
        state.refreshMessage = String(localized: "A preference update may have changed this list. Refresh to check.")
    }

    private func fetch(offset: Int, force: Bool, appending: Bool) async {
        let key = RecommendationPreferencesPageKey(username: account.username, offset: offset, count: pageSize)
        var cacheRevision = await cache.currentRevision()
        var hadStale = !state.items.isEmpty
        if !force, let cached = await cache.value(for: key) {
            do {
                try apply(cached.value, expectedOffset: offset, appending: appending)
                if cached.isFresh {
                    state.phase = .ready
                    state.isLoadingMore = false
                    return
                }
                if !appending { state.phase = .refreshing }
                hadStale = !state.items.isEmpty
            } catch {
                await cache.removeValue(for: key)
                cacheRevision = await cache.currentRevision()
            }
        }

        let requestGeneration = UUID()
        generation = requestGeneration
        do {
            let page = try await provider.entries(username: account.username, offset: offset, count: pageSize)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            _ = try validatedNextOffset(page, expectedOffset: offset)
            guard let writeReceipt = await cache.save(
                page,
                for: key,
                ifUnchangedSince: cacheRevision
            ) else {
                settleInvalidatedRead(hadStale: hadStale)
                return
            }
            if let afterConditionalCacheSave { await afterConditionalCacheSave() }
            guard generation == requestGeneration else {
                await cache.removeValue(for: key, ifWrittenWith: writeReceipt)
                return
            }
            if Task.isCancelled {
                await cache.removeValue(for: key, ifWrittenWith: writeReceipt)
                throw CancellationError()
            }
            try apply(page, expectedOffset: offset, appending: appending)
            state.phase = .ready
            state.isLoadingMore = false
            state.refreshMessage = nil
            state.loadMoreError = nil
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            state.isLoadingMore = false
            state.phase = state.items.isEmpty ? .idle : .ready
        } catch {
            guard generation == requestGeneration else { return }
            state.isLoadingMore = false
            if appending {
                state.loadMoreError = Self.readErrorMessage(error)
                state.phase = .ready
            } else if hadStale {
                state.refreshMessage = String(localized: "Couldn’t refresh. Showing saved preferences.")
                state.phase = .ready
            } else {
                state.phase = .failed(Self.readErrorMessage(error))
            }
        }
    }

    private func apply(
        _ page: RecommendationPreferencePage,
        expectedOffset: Int,
        appending: Bool
    ) throws {
        let nextOffset = try validatedNextOffset(page, expectedOffset: expectedOffset)
        let combined = appending ? state.items + page.items : page.items
        state.items = Array(Self.deduplicated(combined).prefix(Self.maximumVisibleCount))
        loadedPageCount = appending ? min(loadedPageCount + 1, Self.maximumPageCount) : 1
        state.nextOffset = nextOffset
        state.totalCount = max(page.totalCount, nextOffset)
        state.hasMore = page.serverCount > 0
            && nextOffset < state.totalCount
            && loadedPageCount < Self.maximumPageCount
            && state.items.count < Self.maximumVisibleCount
        if !state.hasMore { state.loadMoreError = nil }
    }

    private func validatedNextOffset(
        _ page: RecommendationPreferencePage,
        expectedOffset: Int
    ) throws -> Int {
        let expectedUsername = account.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        let returnedUsername = page.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        let (nextOffset, overflowed) = page.offset.addingReportingOverflow(page.serverCount)
        guard !expectedUsername.isEmpty,
              returnedUsername == expectedUsername,
              page.offset == expectedOffset,
              page.offset >= 0,
              page.serverCount >= 0,
              page.serverCount <= pageSize,
              page.items.count == page.serverCount,
              page.totalCount >= 0,
              !overflowed,
              page.totalCount >= nextOffset
        else { throw DoNotRecommendProviderError.invalidReadResponse }
        return nextOffset
    }

    private func settleInvalidatedRead(hadStale: Bool) {
        state.isLoadingMore = false
        if hadStale {
            state.phase = .ready
            state.refreshMessage = String(localized: "Preferences changed. Refresh to see the latest list.")
        } else {
            state.phase = .failed(String(localized: "Preferences changed while loading. Try again."))
        }
    }

    private static func readErrorMessage(_ error: Error) -> String {
        if let error = error as? DoNotRecommendProviderError { return error.localizedDescription }
        if let error = error as? ProviderError { return error.localizedDescription }
        return DoNotRecommendProviderError.readUnavailable.localizedDescription
    }

    private static func mutationErrorMessage(_ error: Error) -> String {
        if let error = error as? DoNotRecommendProviderError { return error.localizedDescription }
        if let error = error as? ProviderError { return error.localizedDescription }
        return DoNotRecommendProviderError.mutationUnavailable.localizedDescription
    }

    private static func deduplicated(_ items: [RecommendationPreference]) -> [RecommendationPreference] {
        var seen = Set<RecommendationPreference.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
