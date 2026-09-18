import Foundation
import Observation

enum PopularitySummaryPhase: Equatable {
    case idle
    case loading
    case loaded(GlobalPopularity)
    case unavailable
    case failed(String)
}

@MainActor
@Observable
final class PopularitySummaryModel {
    let entity: PopularityEntity

    private let provider: any PopularityProviding
    private var didLoad = false
    private var requestID: UUID?

    private(set) var phase: PopularitySummaryPhase = .idle

    init(entity: PopularityEntity, provider: some PopularityProviding) {
        self.entity = entity
        self.provider = provider
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        await fetch()
    }

    func retry() async {
        didLoad = true
        await fetch()
    }

    private func fetch() async {
        let id = UUID()
        requestID = id
        phase = .loading

        do {
            let value = try await provider.popularity(for: entity)
            try Task.checkCancellation()
            guard requestID == id else { return }

            let normalized = GlobalPopularity(
                entity: value.entity,
                totalListenCount: value.totalListenCount.flatMap { $0 >= 0 ? $0 : nil },
                totalUserCount: value.totalUserCount.flatMap { $0 >= 0 ? $0 : nil }
            )
            phase = normalized.totalListenCount == nil && normalized.totalUserCount == nil
                ? .unavailable
                : .loaded(normalized)
        } catch is CancellationError {
            guard requestID == id else { return }
            didLoad = false
            phase = .idle
        } catch {
            guard requestID == id else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
