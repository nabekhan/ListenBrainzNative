import Foundation
import Observation

@MainActor
@Observable
final class ArtistHighlightsModel {
    let artistMBID: UUID

    private let provider: any ArtistHighlightsProviding
    private var didLoad = false
    private var requestID: UUID?

    private(set) var selection: ArtistHighlightsSelection = .tracks
    private(set) var phase: ArtistHighlightsPhase = .idle

    init(artistMBID: UUID, provider: any ArtistHighlightsProviding) {
        self.artistMBID = artistMBID
        self.provider = provider
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        await fetch(forceRefresh: false)
    }

    func retry() async {
        didLoad = true
        await fetch(forceRefresh: true)
    }

    func select(_ selection: ArtistHighlightsSelection) {
        self.selection = selection
    }

    private func fetch(forceRefresh: Bool) async {
        let id = UUID()
        requestID = id
        phase = .loading

        do {
            guard let value = try await provider.highlights(
                for: artistMBID,
                forceRefresh: forceRefresh
            ) else {
                guard requestID == id else { return }
                phase = .unavailable
                return
            }
            try Task.checkCancellation()
            guard requestID == id else { return }

            if value.recordings.isEmpty, !value.releaseGroups.isEmpty {
                selection = .releases
            }
            phase = .loaded(value)
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
