import Foundation
import Observation

enum GeneratedArtworkPhase: Equatable {
    case idle
    case loading
    case ready(GeneratedArtworkDocument)
    case unavailable
    case failed(String)
}

@MainActor
@Observable
final class GeneratedArtworkModel {
    let request: GeneratedArtworkRequest

    private let provider: any GeneratedArtworkProviding
    private var activeTask: Task<GeneratedArtworkDocument?, any Error>?
    private var requestID: UUID?

    private(set) var phase: GeneratedArtworkPhase = .idle

    init(
        request: GeneratedArtworkRequest,
        provider: any GeneratedArtworkProviding
    ) {
        self.request = request
        self.provider = provider
    }

    func generate() async {
        guard phase == .idle else { return }
        await fetch()
    }

    func retry() async {
        guard phase != .loading else { return }
        await fetch()
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        requestID = nil
        if phase == .loading {
            phase = .idle
        }
    }

    private func fetch() async {
        let id = UUID()
        requestID = id
        phase = .loading

        let task = Task {
            try await provider.artwork(for: request)
        }
        activeTask = task

        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard requestID == id else { return }

            activeTask = nil
            requestID = nil
            phase = value.map(GeneratedArtworkPhase.ready) ?? .unavailable
        } catch is CancellationError {
            guard requestID == id else { return }
            activeTask = nil
            requestID = nil
            phase = .idle
        } catch {
            guard requestID == id else { return }
            activeTask = nil
            requestID = nil
            phase = .failed(error.localizedDescription)
        }
    }
}
