import Foundation
import Observation

@MainActor
@Observable
final class TopListenersModel {
    let entity: TopListenersEntity

    private let scope: RequestGate.ReadScope
    private let provider: any TopListenersProviding
    private let cache: EntityDetailCache<TopListenersCacheKey, TopListeners>
    private var requestID: UUID?
    private var didLoad = false

    private(set) var phase: TopListenersPhase = .idle
    private(set) var refreshMessage: String?

    init(
        entity: TopListenersEntity,
        token: String,
        provider: (any TopListenersProviding)? = nil,
        cache: EntityDetailCache<TopListenersCacheKey, TopListeners> = TopListenersCaches.values
    ) {
        self.entity = entity
        scope = .authenticated(token: token)
        self.provider = provider ?? ListenBrainzTopListenersProvider(token: token)
        self.cache = cache
    }

    init(
        entity: TopListenersEntity,
        scope: RequestGate.ReadScope = .isolated(),
        provider: some TopListenersProviding,
        cache: EntityDetailCache<TopListenersCacheKey, TopListeners> = TopListenersCaches.values
    ) {
        self.entity = entity
        self.scope = scope
        self.provider = provider
        self.cache = cache
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        await fetch(retrying: false)
    }

    func retry() async {
        didLoad = true
        await fetch(retrying: true)
    }

    private func fetch(retrying: Bool) async {
        let key = TopListenersCacheKey(entity: entity, scope: scope)
        var hasStaleContent = false
        if let cached = await cache.value(for: key) {
            phase = cached.value.listeners.isEmpty ? .unavailable : .loaded(cached.value)
            hasStaleContent = !cached.value.listeners.isEmpty
            if cached.isFresh, !retrying { return }
        }
        if !hasStaleContent { phase = .loading }
        refreshMessage = nil

        let id = UUID()
        requestID = id
        do {
            let result = try await provider.topListeners(for: entity)
            try Task.checkCancellation()
            guard requestID == id else { return }
            guard let result else {
                let unavailable = TopListeners(entity: entity, listeners: [], totalListenCount: nil)
                phase = .unavailable
                await cache.save(unavailable, for: key)
                return
            }
            guard !result.listeners.isEmpty else {
                phase = .unavailable
                await cache.save(result, for: key)
                return
            }
            phase = .loaded(result)
            await cache.save(result, for: key)
        } catch is CancellationError {
            guard requestID == id else { return }
            if !hasStaleContent { phase = .idle }
        } catch {
            guard requestID == id else { return }
            if hasStaleContent, case .loaded = phase {
                refreshMessage = error.localizedDescription
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
