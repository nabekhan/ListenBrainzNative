import Foundation
import Observation
import ListenBrainzKit

enum YearInMusicArtworkPhase: Equatable {
    case idle
    case loading
    case ready(YearInMusicArtwork)
    case unavailable
    case failed(String)
}

/// An explicitly-triggered image generation model. It intentionally performs no
/// fetch during construction or view appearance.
@MainActor
@Observable
final class YearInMusicArtworkModel {
    let options: YearInMusicArtworkOptions

    private let provider: any YearInMusicArtworkProviding
    private var requestID: UUID?

    private(set) var phase: YearInMusicArtworkPhase = .idle

    init(options: YearInMusicArtworkOptions, provider: any YearInMusicArtworkProviding) {
        self.options = options
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
        requestID = nil
        if phase == .loading { phase = .idle }
    }

    private func fetch() async {
        let id = UUID()
        requestID = id
        phase = .loading
        do {
            let artwork = try await provider.artwork(for: options)
            try Task.checkCancellation()
            guard requestID == id else { return }
            phase = artwork.map(YearInMusicArtworkPhase.ready) ?? .unavailable
        } catch is CancellationError {
            guard requestID == id else { return }
            phase = .idle
        } catch {
            guard requestID == id else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
