import SwiftUI

struct ListenRow: View {
    let listen: Listen
    var showsDate = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: listen.recording.artworkURL, title: listen.recording.title, cornerRadius: 8)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(listen.recording.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if listen.isPlayingNow {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative)
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityLabel("Playing now")
                    }
                }
                Text(listen.recording.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let release = listen.recording.releaseTitle, !release.isEmpty {
                    Text(release)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(timestamp)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var timestamp: String {
        if listen.isPlayingNow { return "Now" }
        return showsDate
            ? listen.listenedAt.formatted(date: .abbreviated, time: .shortened)
            : listen.listenedAt.formatted(date: .omitted, time: .shortened)
    }
}
