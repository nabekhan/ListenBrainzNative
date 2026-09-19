import Foundation
import Observation

@MainActor
@Observable
final class SimilarArtistsModel {
    let artistMBID: UUID

    private let provider: any SimilarArtistsProviding
    private let cache: EntityDetailCache<SimilarArtistsCacheKey, SimilarArtists>
    private var requestID: UUID?
    private var didLoad = false

    private(set) var phase: SimilarArtistsPhase = .idle

    init(
        artistMBID: UUID,
        provider: any SimilarArtistsProviding,
        cache: EntityDetailCache<SimilarArtistsCacheKey, SimilarArtists> = SimilarArtistsCaches.values
    ) {
        self.artistMBID = artistMBID
        self.provider = provider
        self.cache = cache
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        await fetch()
    }

    private func fetch() async {
        let key = SimilarArtistsCacheKey(artistMBID: artistMBID)
        var hasStaleContent = false
        var staleContent: SimilarArtists?
        if let cached = await cache.value(for: key) {
            phase = cached.value.hasVisibleContent ? .loaded(cached.value) : .unavailable
            hasStaleContent = cached.value.hasVisibleContent
            if !cached.isFresh, hasStaleContent { staleContent = cached.value }
            if cached.isFresh { return }
        }
        if !hasStaleContent { phase = .loading }

        let id = UUID()
        requestID = id
        do {
            let value = try await provider.similarArtists(to: artistMBID)
            try Task.checkCancellation()
            guard requestID == id else { return }

            let cachedValue = value ?? SimilarArtists(sourceArtistMBID: artistMBID, artists: [])
            phase = cachedValue.hasVisibleContent ? .loaded(cachedValue) : .unavailable
            await cache.save(cachedValue, for: key)
        } catch is CancellationError {
            guard requestID == id else { return }
            didLoad = false
            if !hasStaleContent { phase = .idle }
        } catch {
            guard requestID == id else { return }
            if let staleContent {
                // Preserve the shelf and renew its short cooldown so each new
                // view does not retry the same failing refresh immediately.
                await cache.save(staleContent, for: key)
            } else if !hasStaleContent {
                phase = .failed(error.localizedDescription)
                // The shelf is optional. Briefly cache a failed load as empty
                // so repeated navigation during an outage or schema change
                // cannot amplify requests to the website route.
                await cache.save(
                    SimilarArtists(sourceArtistMBID: artistMBID, artists: []),
                    for: key
                )
            }
        }
    }
}
