import SwiftUI
import NukeUI

struct ArtworkView: View {
    let url: URL?
    let title: String
    var cornerRadius: CGFloat = 12
    var showsPlaceholderSymbol = true

    var body: some View {
        let request = ArtworkPipeline.request(for: url)
        LazyImage(
            request: request,
            transaction: .init(animation: .easeInOut(duration: 0.2))
        ) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if state.error == nil {
                if request == nil {
                    placeholder
                } else {
                    placeholder.overlay { ProgressView().tint(.white.opacity(0.8)) }
                }
            } else {
                placeholder
            }
        }
        .pipeline(ArtworkPipeline.shared)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(
            request == nil
                ? String(localized: "No artwork for \(title)")
                : String(localized: "Artwork for \(title)")
        )
    }

    private var placeholder: some View {
        AppTheme.artworkGradient(seed: title)
            .overlay {
                if showsPlaceholderSymbol {
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .accessibilityHidden(true)
                }
            }
    }
}

struct ArtistArtworkView: View {
    let artist: RankedArtist

    var body: some View {
        let listens = String(localized: "\(artist.listenCount) listens")
        Circle()
            .fill(AppTheme.artworkGradient(seed: artist.name))
            .overlay {
                Text(artist.name.prefix(1).uppercased())
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(
                artist.listenCount > 0
                    ? String(localized: "\(artist.name), \(listens)")
                    : String(localized: "\(artist.name), MusicBrainz artist")
            )
    }
}
