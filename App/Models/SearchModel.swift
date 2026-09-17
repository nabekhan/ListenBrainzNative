import Foundation
import Observation

@MainActor
@Observable
final class SearchModel {
    var query = ""
    var scope: SearchScope = .artists
    private(set) var results: [SearchResult] = []
    private(set) var state: SearchLoadState = .idle
    private let provider: any SearchProviding
    private let debounceDuration: Duration
    private var cache: [CacheKey: [SearchResult]] = [:]
    private var scheduledSearch: Task<Void, Never>?
    private var requestID = UUID()

    init(
        account: Account,
        provider: (any SearchProviding)? = nil,
        debounceDuration: Duration = .milliseconds(500),
        initialQuery: String = "",
        initialScope: SearchScope = .artists
    ) {
        self.provider = provider ?? SearchProvider(token: account.token)
        self.debounceDuration = debounceDuration
        self.query = initialQuery
        self.scope = initialScope
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
        scheduledSearch?.cancel()
        requestID = UUID()
        let request = makeRequest()
        guard !request.query.isEmpty else {
            results = []
            state = .idle
            return
        }
        guard request.query.count >= request.key.scope.minimumQueryLength else {
            results = []
            state = .idle
            return
        }
        if let cached = cache[request.key] {
            results = cached
            state = .loaded
            return
        }
        state = .waiting
        let id = requestID
        scheduledSearch = Task { [weak self] in
            guard let self else { return }
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
        scheduledSearch?.cancel()
        scheduledSearch = nil
        requestID = UUID()
        if state == .waiting || state == .loading {
            state = .idle
        }
    }

    func searchImmediatelyForTesting() async {
        scheduledSearch?.cancel()
        requestID = UUID()
        let request = makeRequest()
        guard !request.query.isEmpty,
              request.query.count >= request.key.scope.minimumQueryLength
        else {
            results = []
            state = .idle
            return
        }
        await search(request: request, requestID: requestID)
    }

    func retry() async {
        scheduledSearch?.cancel()
        requestID = UUID()
        let request = makeRequest()
        guard !request.query.isEmpty,
              request.query.count >= request.key.scope.minimumQueryLength
        else { return }
        await search(request: request, requestID: requestID)
    }

    private func search(request: SearchRequest, requestID: UUID) async {
        guard self.requestID == requestID else { return }
        if let cached = cache[request.key] {
            results = cached
            state = .loaded
            return
        }
        state = .loading
        do {
            let value = try await provider.search(query: request.query, scope: request.key.scope)
            guard self.requestID == requestID else { return }
            cache[request.key] = value
            results = value
            state = .loaded
        } catch {
            guard self.requestID == requestID else { return }
            state = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
    }

    private func makeRequest() -> SearchRequest {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchRequest(
            key: .init(scope: scope, normalizedQuery: trimmedQuery.lowercased()),
            query: trimmedQuery
        )
    }

    private struct SearchRequest: Sendable {
        let key: CacheKey
        let query: String
    }

    private struct CacheKey: Hashable, Sendable {
        let scope: SearchScope
        let normalizedQuery: String
    }
}
