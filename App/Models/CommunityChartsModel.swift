import Foundation
import Observation

struct CommunityChartPageCacheKey: Hashable, Sendable {
    let query: CommunityChartQuery
    let offset: Int
    let limit: Int
}

enum CommunityChartCaches {
    static let pages = EntityDetailCache<CommunityChartPageCacheKey, CommunityChartPage>(
        timeToLive: 10 * 60,
        maximumEntryCount: 180
    )
}

@MainActor
@Observable
final class CommunityChartsModel {
    private(set) var kind: CommunityChartKind
    private(set) var period: ListeningActivityPeriod
    private(set) var items: [CommunityChartItem] = []
    private(set) var state: CommunityChartLoadState = .idle
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var loadMoreError: String?
    private(set) var refreshError: String?
    private(set) var totalResultCount: Int?
    private(set) var lastUpdated: Date?
    private(set) var hasReachedVisibleLimit = false

    private let provider: any CommunityChartsProviding
    private let pageSize: Int
    private let visibleLimit: Int
    private let cache: EntityDetailCache<CommunityChartPageCacheKey, CommunityChartPage>
    private var nextOffset: Int?
    private var initialTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var requestID = UUID()

    init(
        provider: (any CommunityChartsProviding)? = nil,
        cache: EntityDetailCache<CommunityChartPageCacheKey, CommunityChartPage>? = nil,
        pageSize: Int = ListenBrainzCommunityChartsProvider.maximumPageSize,
        visibleLimit: Int = 200,
        initialKind: CommunityChartKind = .artists,
        initialPeriod: ListeningActivityPeriod = .thisWeek
    ) {
        self.provider = provider ?? ListenBrainzCommunityChartsProvider()
        self.cache = cache ?? (provider == nil ? CommunityChartCaches.pages : EntityDetailCache())
        self.pageSize = min(max(pageSize, 1), ListenBrainzCommunityChartsProvider.maximumPageSize)
        self.visibleLimit = max(1, visibleLimit)
        kind = initialKind
        period = initialPeriod
    }

    var query: CommunityChartQuery {
        CommunityChartQuery(kind: kind, period: period)
    }

    var canLoadMore: Bool {
        state == .loaded
            && nextOffset != nil
            && !isLoadingMore
            && !isRefreshing
            && items.count < visibleLimit
    }

    var visibleResultLimit: Int { visibleLimit }

    func select(kind newKind: CommunityChartKind) {
        guard kind != newKind else { return }
        kind = newKind
        resetForSelection()
    }

    func select(period newPeriod: ListeningActivityPeriod) {
        guard period != newPeriod else { return }
        period = newPeriod
        resetForSelection()
    }

    func loadSelectedIfNeeded() async {
        guard state == .idle else { return }
        let selectedQuery = query
        let id = requestID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFirstPage(query: selectedQuery, requestID: id, forceNetwork: false)
        }
        initialTask = task
        await task.value
        if requestID == id {
            initialTask = nil
        }
    }

    func retry() async {
        cancelTasks()
        requestID = UUID()
        let selectedQuery = query
        let id = requestID
        items = []
        resetPagination()
        refreshError = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFirstPage(query: selectedQuery, requestID: id, forceNetwork: true)
        }
        initialTask = task
        await task.value
        if requestID == id {
            initialTask = nil
        }
    }

    func refresh() async {
        guard state == .loaded, refreshTask == nil, !isLoadingMore else { return }
        isRefreshing = true
        refreshError = nil
        let selectedQuery = query
        let id = requestID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFirstPage(query: selectedQuery, requestID: id, forceNetwork: true)
        }
        refreshTask = task
        await task.value
        if requestID == id {
            refreshTask = nil
            isRefreshing = false
        }
    }

    func loadMore() async {
        guard canLoadMore, let offset = nextOffset else { return }
        let selectedQuery = query
        let id = requestID
        isLoadingMore = true
        loadMoreError = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadMore(query: selectedQuery, offset: offset, requestID: id)
        }
        loadMoreTask = task
        await task.value
        if requestID == id {
            loadMoreTask = nil
        }
    }

    func cancel() {
        cancelTasks()
        requestID = UUID()
        isLoadingMore = false
        isRefreshing = false
        if state == .loading {
            state = items.isEmpty ? .idle : .loaded
        }
    }

    private func performFirstPage(
        query: CommunityChartQuery,
        requestID: UUID,
        forceNetwork: Bool
    ) async {
        guard self.requestID == requestID, self.query == query else { return }
        let key = cacheKey(query: query, offset: 0)
        var showedCachedPage = false

        if !forceNetwork,
           let cached = await cache.value(for: key),
           self.requestID == requestID,
           self.query == query,
           !Task.isCancelled {
            applyFirstPage(cached.value)
            showedCachedPage = true
            if cached.isFresh { return }
        }

        if !showedCachedPage, items.isEmpty {
            state = .loading
        }
        do {
            let page = try await provider.page(
                query: query,
                offset: 0,
                limit: pageSize
            )
            try Task.checkCancellation()
            guard self.requestID == requestID, self.query == query else { return }
            guard page.offset == 0 else { throw CommunityChartsProviderError.invalidResponse }
            await cache.save(page, for: key)
            applyFirstPage(page)
        } catch {
            guard self.requestID == requestID, self.query == query, !Task.isCancelled else { return }
            if showedCachedPage || !items.isEmpty {
                state = .loaded
                refreshError = error.localizedDescription
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func performLoadMore(
        query: CommunityChartQuery,
        offset: Int,
        requestID: UUID
    ) async {
        defer {
            if self.requestID == requestID {
                isLoadingMore = false
            }
        }
        do {
            let page = try await page(query: query, offset: offset)
            try Task.checkCancellation()
            guard self.requestID == requestID, self.query == query else { return }
            guard page.offset == offset else { throw CommunityChartsProviderError.invalidResponse }
            append(page)
            loadMoreError = nil
        } catch {
            guard self.requestID == requestID, self.query == query, !Task.isCancelled else { return }
            loadMoreError = error.localizedDescription
        }
    }

    private func page(
        query: CommunityChartQuery,
        offset: Int
    ) async throws -> CommunityChartPage {
        let key = cacheKey(query: query, offset: offset)
        if let cached = await cache.value(for: key), cached.isFresh {
            return cached.value
        }
        let page = try await provider.page(
            query: query,
            offset: offset,
            limit: pageSize
        )
        try Task.checkCancellation()
        guard page.offset == offset else { throw CommunityChartsProviderError.invalidResponse }
        await cache.save(page, for: key)
        return page
    }

    private func applyFirstPage(_ page: CommunityChartPage) {
        let uniqueItems = unique(page.items)
        let hadTruncatedItems = uniqueItems.count > visibleLimit
        items = Array(uniqueItems.prefix(visibleLimit))
        totalResultCount = page.totalResultCount
        lastUpdated = page.lastUpdated
        refreshError = nil
        loadMoreError = nil
        updatePagination(from: page, hadTruncatedItems: hadTruncatedItems)
        state = .loaded
    }

    private func append(_ page: CommunityChartPage) {
        var seen = Set(items.map(\CommunityChartItem.id))
        let additions = page.items.filter { seen.insert($0.id).inserted }
        let remainingCapacity = max(visibleLimit - items.count, 0)
        let hadTruncatedItems = additions.count > remainingCapacity
        items.append(contentsOf: additions.prefix(remainingCapacity))
        totalResultCount = page.totalResultCount
        lastUpdated = page.lastUpdated ?? lastUpdated
        updatePagination(from: page, hadTruncatedItems: hadTruncatedItems)
    }

    private func updatePagination(
        from page: CommunityChartPage,
        hadTruncatedItems: Bool
    ) {
        if items.count >= visibleLimit {
            hasReachedVisibleLimit = page.nextOffset != nil || hadTruncatedItems
            nextOffset = nil
        } else {
            hasReachedVisibleLimit = false
            nextOffset = page.nextOffset
        }
    }

    private func unique(_ values: [CommunityChartItem]) -> [CommunityChartItem] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private func cacheKey(
        query: CommunityChartQuery,
        offset: Int
    ) -> CommunityChartPageCacheKey {
        .init(query: query, offset: offset, limit: pageSize)
    }

    private func resetForSelection() {
        cancelTasks()
        requestID = UUID()
        items = []
        state = .idle
        resetPagination()
        refreshError = nil
        lastUpdated = nil
        isRefreshing = false
    }

    private func resetPagination() {
        nextOffset = nil
        totalResultCount = nil
        isLoadingMore = false
        loadMoreError = nil
        hasReachedVisibleLimit = false
    }

    private func cancelTasks() {
        initialTask?.cancel()
        initialTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }
}
