import SwiftUI

struct ListenRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let listen: Listen
    var showsDate = false

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            ArtworkView(url: listen.recording.artworkURL, title: listen.recording.title, cornerRadius: 8)
                .frame(width: 54, height: 54)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    metadata
                    timestampLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                metadata
                Spacer(minLength: 8)
                timestampLabel
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(listen.recording.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            if let release = listen.recording.releaseTitle, !release.isEmpty {
                Text(release)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
    }

    private var timestampLabel: some View {
        Text(timestamp)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var timestamp: String {
        if listen.isPlayingNow { return String(localized: "Now") }
        return showsDate
            ? listen.listenedAt.formatted(date: .abbreviated, time: .shortened)
            : listen.listenedAt.formatted(date: .omitted, time: .shortened)
    }
}
