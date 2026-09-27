import Foundation
import Observation

struct SearchPageCacheKey: Hashable, Sendable {
    let scope: SearchScope
    let normalizedQuery: String
    let offset: Int
    let limit: Int
}

enum SearchCaches {
    static let pages = EntityDetailCache<SearchPageCacheKey, SearchPage>(
        timeToLive: 5 * 60,
        maximumEntryCount: 160
    )
}

@MainActor
@Observable
final class SearchModel {
    var query = ""
    var scope: SearchScope = .artists
    private(set) var results: [SearchResult] = []
    private(set) var state: SearchLoadState = .idle
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?
    private(set) var totalResultCount: Int?

    private let provider: any SearchProviding
    private let debounceDuration: Duration
    private let pageSize: Int
    private let cache: EntityDetailCache<SearchPageCacheKey, SearchPage>
    private var nextOffset: Int?
    private var scheduledSearch: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var requestID = UUID()

    init(
        account: Account,
        provider: (any SearchProviding)? = nil,
        debounceDuration: Duration = .milliseconds(500),
        pageSize: Int = SearchProvider.maximumPageSize,
        cache: EntityDetailCache<SearchPageCacheKey, SearchPage>? = nil,
        initialQuery: String = "",
        initialScope: SearchScope = .artists
    ) {
        self.provider = provider ?? SearchProvider(token: account.token)
        self.debounceDuration = debounceDuration
        self.pageSize = min(max(pageSize, 1), SearchProvider.maximumPageSize)
        // Tests and visual fixtures receive an isolated bounded cache unless
        // they explicitly share one. Production search sheets reuse the
        // process-wide cache to avoid repeating identical public reads.
        self.cache = cache ?? (provider == nil ? SearchCaches.pages : EntityDetailCache())
        self.query = initialQuery
        self.scope = initialScope
    }

    var canLoadMore: Bool {
        state == .loaded && nextOffset != nil && !isLoadingMore
    }

    func update(query: String) {
        self.query = query
        scheduleSearch()
    }

    func update(scope: SearchScope) {
        self.scope = scope
        scheduleSearch()
    }

    func scheduleSearch() {
        cancelTasks()
        requestID = UUID()
        resetPagination()
        let request = makeRequest()
        guard request.isValid else {
            results = []
            state = .idle
            return
        }

        results = []
        state = .waiting
        let id = requestID
        scheduledSearch = Task { [weak self] in
            guard let self else { return }
            if await useFreshCachedFirstPage(request: request, requestID: id) {
                return
            }
            do { try await ContinuousClock().sleep(for: debounceDuration) }
            catch { return }
            await search(request: request, requestID: id)
        }
    }

    func startInitialSearchIfNeeded() {
        guard state == .idle,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        scheduleSearch()
    }

    func cancel() {
        cancelTasks()
        requestID = UUID()
        isLoadingMore = false
        if state == .waiting || state == .loading {
            state = .idle
        }
    }

    func searchImmediatelyForTesting() async {
        cancelTasks()
        requestID = UUID()
        resetPagination()
        let request = makeRequest()
        guard request.isValid else {
            results = []
            state = .idle
            return
        }
        results = []
        await search(request: request, requestID: requestID)
    }

    func retry() async {
        cancelTasks()
        requestID = UUID()
        resetPagination()
        let request = makeRequest()
        guard request.isValid else { return }
        results = []
        let id = requestID
        let task = Task { [weak self] in
            guard let self else { return }
            await search(request: request, requestID: id)
        }
        scheduledSearch = task
        await task.value
        if requestID == id {
            scheduledSearch = nil
        }
    }

    func loadMore() async {
        guard canLoadMore,
              let offset = nextOffset
        else { return }
        let request = makeRequest()
        guard request.isValid else { return }

        isLoadingMore = true
        loadMoreError = nil
        let id = requestID
        let task = Task { [weak self] in
            guard let self else { return }
            await performLoadMore(request: request, offset: offset, requestID: id)
        }
        loadMoreTask = task
        await task.value
        if requestID == id {
            loadMoreTask = nil
        }
    }

    private func search(request: SearchRequest, requestID: UUID) async {
        guard self.requestID == requestID else { return }
        state = .loading
        do {
            let page = try await page(for: request, offset: 0)
            try Task.checkCancellation()
            guard self.requestID == requestID else { return }
            applyFirstPage(page)
        } catch {
            guard self.requestID == requestID else { return }
            state = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
    }

    private func performLoadMore(
        request: SearchRequest,
        offset: Int,
        requestID: UUID
    ) async {
        defer {
            if self.requestID == requestID {
                isLoadingMore = false
            }
        }
        do {
            let page = try await page(for: request, offset: offset)
            try Task.checkCancellation()
            guard self.requestID == requestID else { return }
            guard page.offset == offset else { throw SearchProviderError.invalidResponse }
            appendUnique(page.results)
            totalResultCount = page.totalResultCount
            nextOffset = page.nextOffset
            loadMoreError = nil
        } catch {
            guard self.requestID == requestID, !Task.isCancelled else { return }
            loadMoreError = error.localizedDescription
        }
    }

    private func page(for request: SearchRequest, offset: Int) async throws -> SearchPage {
        let key = request.cacheKey(offset: offset, limit: pageSize)
        if let cached = await cache.value(for: key), cached.isFresh {
            return cached.value
        }
        let page = try await provider.searchPage(
            query: request.query,
            scope: request.scope,
            offset: offset,
            limit: pageSize
        )
        try Task.checkCancellation()
        guard page.offset == offset else { throw SearchProviderError.invalidResponse }
        await cache.save(page, for: key)
        return page
    }

    private func useFreshCachedFirstPage(
        request: SearchRequest,
        requestID: UUID
    ) async -> Bool {
        let key = request.cacheKey(offset: 0, limit: pageSize)
        guard let cached = await cache.value(for: key), cached.isFresh,
              self.requestID == requestID,
              !Task.isCancelled
        else { return false }
        applyFirstPage(cached.value)
        return true
    }

    private func applyFirstPage(_ page: SearchPage) {
        results = unique(page.results)
        totalResultCount = page.totalResultCount
        nextOffset = page.nextOffset
        loadMoreError = nil
        state = .loaded
    }

    private func appendUnique(_ additions: [SearchResult]) {
        var seen = Set(results.map(\.id))
        results.append(contentsOf: additions.filter { seen.insert($0.id).inserted })
    }

    private func unique(_ values: [SearchResult]) -> [SearchResult] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private func resetPagination() {
        nextOffset = nil
        totalResultCount = nil
        isLoadingMore = false
        loadMoreError = nil
    }

    private func cancelTasks() {
        scheduledSearch?.cancel()
        scheduledSearch = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
    }

    private func makeRequest() -> SearchRequest {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchRequest(
            scope: scope,
            normalizedQuery: trimmedQuery.lowercased(),
            query: trimmedQuery
        )
    }

    private struct SearchRequest: Sendable {
        let scope: SearchScope
        let normalizedQuery: String
        let query: String

        var isValid: Bool {
            !query.isEmpty && query.count >= scope.minimumQueryLength
        }

        func cacheKey(offset: Int, limit: Int) -> SearchPageCacheKey {
            .init(
                scope: scope,
                normalizedQuery: normalizedQuery,
                offset: offset,
                limit: limit
            )
        }
    }
}
