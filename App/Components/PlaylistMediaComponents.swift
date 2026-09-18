import SwiftUI

struct PlaylistArtworkMosaic: View {
    let tracks: [PlaylistTrack]
    let title: String

    var body: some View {
        Group {
            if tracks.count < 2 {
                ArtworkView(
                    url: tracks.first?.recording.artworkURL,
                    title: tracks.first?.recording.title ?? title,
                    cornerRadius: 24,
                    showsPlaceholderSymbol: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let side = max((proxy.size.width - 2) / 2, 0)
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            cell(at: 0).frame(width: side, height: side)
                            cell(at: 1).frame(width: side, height: side)
                        }
                        HStack(spacing: 2) {
                            cell(at: 2).frame(width: side, height: side)
                            cell(at: 3).frame(width: side, height: side)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Artwork mosaic for \(title)")
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        if tracks.indices.contains(index) {
            let recording = tracks[index].recording
            ArtworkView(
                url: recording.artworkURL,
                title: recording.title,
                cornerRadius: 0,
                showsPlaceholderSymbol: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            AppTheme.artworkGradient(seed: "\(title):\(index)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PlaylistTrackRow: View {
    let track: PlaylistTrack

    var body: some View {
        HStack(spacing: 12) {
            Text(track.position.formatted())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            ArtworkView(
                url: track.recording.artworkURL,
                title: track.recording.title,
                cornerRadius: 8
            )
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.recording.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(track.recording.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if track.recording.releaseTitle != nil || durationDescription != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) { secondaryMetadata(showsSeparator: true) }
                        VStack(alignment: .leading, spacing: 2) {
                            secondaryMetadata(showsSeparator: false)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 6)
            if track.recording.identity.mbid != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            track.recording.identity.mbid == nil
                ? "This playlist item is not mapped to MusicBrainz"
                : "Open recording details"
        )
    }

    private var durationDescription: String? {
        guard let milliseconds = track.recording.durationMilliseconds,
              milliseconds > 0
        else { return nil }
        let seconds = milliseconds / 1_000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    @ViewBuilder
    private func secondaryMetadata(showsSeparator: Bool) -> some View {
        if let release = track.recording.releaseTitle {
            Text(release).lineLimit(1)
        }
        if showsSeparator,
           track.recording.releaseTitle != nil,
           durationDescription != nil {
            Text("·").accessibilityHidden(true)
        }
        if let duration = durationDescription {
            Text(duration).monospacedDigit()
        }
    }
}
