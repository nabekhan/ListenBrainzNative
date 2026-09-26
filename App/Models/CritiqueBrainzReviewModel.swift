import Foundation
import Observation

@MainActor
@Observable
final class CritiqueBrainzReviewModel {
    let entity: CritiqueBrainzEntity
    private let provider: any CritiqueBrainzReviewsProviding
    private let cache: EntityDetailCache<CritiqueBrainzReviewCacheKey, CritiqueBrainzReviewSummary>
    private var requestID: UUID?
    private var didLoad = false

    private(set) var phase: CritiqueBrainzReviewPhase = .idle
    private(set) var refreshMessage: String?

    init(entity: CritiqueBrainzEntity, provider: some CritiqueBrainzReviewsProviding, cache: EntityDetailCache<CritiqueBrainzReviewCacheKey, CritiqueBrainzReviewSummary> = CritiqueBrainzReviewCaches.values) {
        self.entity = entity
        self.provider = provider
        self.cache = cache
    }

    func load() async { guard !didLoad else { return }; didLoad = true; await fetch(retrying: false) }
    func retry() async { didLoad = true; await fetch(retrying: true) }

    private func fetch(retrying: Bool) async {
        let key = CritiqueBrainzReviewCacheKey(entity: entity)
        var hasStale = false
        if let cached = await cache.value(for: key) {
            phase = cached.value.hasVisibleContent ? .loaded(cached.value) : .unavailable
            hasStale = cached.value.hasVisibleContent
            if cached.isFresh, !retrying { return }
        }
        if !hasStale { phase = .loading }
        refreshMessage = nil
        let id = UUID(); requestID = id
        do {
            guard let value = try await provider.reviews(for: entity) else {
                guard requestID == id else { return }
                let unavailable = CritiqueBrainzReviewSummary(
                    entity: entity,
                    reviews: [],
                    averageRating: nil
                )
                phase = .unavailable
                await cache.save(unavailable, for: key)
                return
            }
            try Task.checkCancellation(); guard requestID == id else { return }
            phase = value.hasVisibleContent ? .loaded(value) : .unavailable
            await cache.save(value, for: key)
        } catch is CancellationError {
            guard requestID == id else { return }
            didLoad = false
            if !hasStale { phase = .idle }
        } catch {
            guard requestID == id else { return }
            if hasStale { refreshMessage = error.localizedDescription } else { phase = .failed(error.localizedDescription) }
        }
    }
}

@MainActor
@Observable
final class CritiqueBrainzReviewReaderModel {
    static let readerPageSize = 20
    static let maximumAdditionalPages = 10
    static let maximumVisibleReviews = 200

    private let provider: any CritiqueBrainzReviewsProviding
    private var requestID: UUID?
    private var successfulAdditionalPages = 0

    private(set) var summary: CritiqueBrainzReviewSummary
    private(set) var isLoadingMore = false
    private(set) var loadMoreMessage: String?
    private(set) var hasReachedEnd = false

    init(summary: CritiqueBrainzReviewSummary, provider: any CritiqueBrainzReviewsProviding) {
        self.summary = summary
        self.provider = provider
        hasReachedEnd = summary.pagination?.nextOffset == nil
    }

    var canLoadMore: Bool {
        !isLoadingMore
            && loadMoreMessage == nil
            && !hasReachedEnd
            && successfulAdditionalPages < Self.maximumAdditionalPages
            && summary.reviews.count < Self.maximumVisibleReviews
    }

    var canRetryLoadMore: Bool { loadMoreMessage != nil && !isLoadingMore && !hasReachedEnd }

    func loadMore() async {
        guard canLoadMore || canRetryLoadMore,
              let offset = summary.pagination?.nextOffset,
              successfulAdditionalPages < Self.maximumAdditionalPages,
              summary.reviews.count < Self.maximumVisibleReviews
        else { return }

        isLoadingMore = true
        loadMoreMessage = nil
        let id = UUID()
        requestID = id
        do {
            guard let page = try await provider.reviewPage(
                for: summary.entity,
                offset: offset,
                limit: Self.readerPageSize
            ) else {
                guard requestID == id else { return }
                hasReachedEnd = true
                isLoadingMore = false
                return
            }
            try Task.checkCancellation()
            guard requestID == id else { return }

            // The live decoder already enforces this contract. Keep the
            // reader defensive for injected providers as well: a malformed or
            // non-advancing page must never create a request loop.
            guard page.pagination.offset == offset,
                  page.pagination.rawRowCount > 0,
                  page.pagination.nextOffset.map({ $0 > offset }) ?? true
            else {
                hasReachedEnd = true
                isLoadingMore = false
                return
            }

            var seenIDs = Set(summary.reviews.map(\.id))
            let additions = page.summary.reviews.filter { seenIDs.insert($0.id).inserted }
            guard !additions.isEmpty else {
                hasReachedEnd = true
                isLoadingMore = false
                return
            }

            let remaining = Self.maximumVisibleReviews - summary.reviews.count
            guard remaining > 0 else {
                hasReachedEnd = true
                isLoadingMore = false
                return
            }
            let merged = summary.reviews + additions.prefix(remaining)
            successfulAdditionalPages += 1
            summary = CritiqueBrainzReviewSummary(
                entity: summary.entity,
                reviews: merged,
                averageRating: summary.averageRating,
                ratingCount: summary.ratingCount,
                pagination: page.pagination
            )
            hasReachedEnd = page.pagination.nextOffset == nil
                || successfulAdditionalPages >= Self.maximumAdditionalPages
                || merged.count >= Self.maximumVisibleReviews
            isLoadingMore = false
        } catch is CancellationError {
            guard requestID == id else { return }
            isLoadingMore = false
        } catch {
            guard requestID == id else { return }
            isLoadingMore = false
            loadMoreMessage = error.localizedDescription
        }
    }

    func cancel() {
        requestID = nil
        isLoadingMore = false
    }
}
