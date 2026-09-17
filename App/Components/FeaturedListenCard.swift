import SwiftUI

struct FeaturedListenCard: View {
    let listen: Listen
    let label: String
    let systemImage: String

    var body: some View {
        NavigationLink(value: listen.recording) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(
                    url: listen.recording.artworkURL,
                    title: listen.recording.title,
                    cornerRadius: 24,
                    showsPlaceholderSymbol: false
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(1.45, contentMode: .fill)
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.78)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .clipShape(.rect(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Label(label.uppercased(), systemImage: systemImage)
                        .font(.caption2.bold())
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(listen.recording.title)
                        .font(.title.bold())
                        .lineLimit(2)
                    Text(listen.recording.artistName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(listen.recording.title) by \(listen.recording.artistName)")
    }
}
