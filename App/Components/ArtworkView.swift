import SwiftUI

struct ArtworkView: View {
    let url: URL?
    let title: String
    var cornerRadius: CGFloat = 12
    var showsPlaceholderSymbol = true

    var body: some View {
        AsyncImage(url: url, transaction: .init(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .empty:
                if url == nil {
                    placeholder
                } else {
                    placeholder.overlay { ProgressView().tint(.white.opacity(0.8)) }
                }
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(url == nil ? "No artwork for \(title)" : "Artwork for \(title)")
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
        Circle()
            .fill(AppTheme.artworkGradient(seed: artist.name))
            .overlay {
                Text(artist.name.prefix(1).uppercased())
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(
                artist.listenCount > 0
                    ? "\(artist.name), \(artist.listenCount.formatted()) listens"
                    : "\(artist.name), MusicBrainz artist"
            )
    }
}
