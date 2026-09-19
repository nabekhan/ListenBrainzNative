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
