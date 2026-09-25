import ListenBrainzKit
import SwiftUI

struct YearInMusicArtworkSheet: View {
    let report: YearInMusicReport
    let reportURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: YearInMusicArtworkModel
    @State private var snapshotPhase: SVGArtworkSnapshotPhase = .preparing
    @State private var snapshotReloadID = 0
    @State private var retryTask: Task<Void, Never>?

    init(
        report: YearInMusicReport,
        username: String,
        reportURL: URL,
        provider: any YearInMusicArtworkProviding
    ) {
        self.report = report
        self.reportURL = reportURL
        _model = State(
            initialValue: YearInMusicArtworkModel(
                options: .init(
                    username: username,
                    year: report.year,
                    variant: report.year == 2022 ? .stats : .overview,
                    legacy: report.source == .archive
                ),
                provider: provider
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                phaseContent
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Shareable artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await model.generate() }
        .onDisappear {
            retryTask?.cancel()
            model.cancel()
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .idle, .loading:
            loadingContent
        case let .ready(artwork):
            readyContent(artwork)
        case .unavailable:
            unavailableContent
        case let .failed(message):
            failureContent(message)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.secondary.opacity(0.1))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Creating your artwork…")
                            .font(.headline)
                    }
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("ListenBrainz is generating Year in Music artwork")
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 300 : .infinity)

            artworkExplanation
        }
    }

    private func readyContent(_ artwork: YearInMusicArtwork) -> some View {
        VStack(spacing: 20) {
            SVGArtworkPreview(
                svg: artwork.svg,
                reloadID: snapshotReloadID,
                accessibilityLabel: artworkAccessibilityLabel
            ) { phase in
                snapshotPhase = phase
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(artworkAccessibilityLabel)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 300 : .infinity)

            VStack(spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                        Text("Official ListenBrainz artwork")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityElement(children: .combine)
                } else {
                    Label("Official ListenBrainz artwork", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                }
                Text(String(localized: "Generated from your \(report.year) listening report."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            shareControls

            artworkExplanation
        }
    }

    @ViewBuilder
    private var shareControls: some View {
        switch snapshotPhase {
        case .preparing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Preparing a high-resolution copy…")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        case let .ready(shareImage):
            if let pngData = shareImage.pngData() {
                ShareLink(
                    item: SVGPNGShareItem(
                        data: pngData,
                        fileName: "ListenBrainz-Year-in-Music-\(report.year).png"
                    ),
                    subject: Text(String(localized: "My \(report.year) Year in Music")),
                    message: Text(String(localized: "My \(report.year) listening story on ListenBrainz: \(reportURL.absoluteString)")),
                    preview: SharePreview(
                        String(localized: "ListenBrainz Year in Music \(report.year)"),
                        image: Image(uiImage: shareImage)
                    )
                ) {
                    Label("Share artwork", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.accent)
                .accessibilityHint("Shares a PNG copy and the ListenBrainz report link")
            } else {
                snapshotFailure(String(localized: "Brainz couldn’t encode the artwork as a PNG."))
            }
        case let .failed(message):
            snapshotFailure(message)
        }
    }

    private func snapshotFailure(_ message: String) -> some View {
        VStack(spacing: 10) {
            Label("Share copy unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Prepare again") {
                snapshotPhase = .preparing
                snapshotReloadID += 1
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var unavailableContent: some View {
        VStack(spacing: 22) {
            ContentUnavailableView {
                Label("Artwork unavailable", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("ListenBrainz doesn’t have enough data to create this artwork.")
            } actions: {
                Button("Try again") { beginRetry() }
            }
            .frame(minHeight: 340)

            artworkExplanation
        }
    }

    private func failureContent(_ message: String) -> some View {
        VStack(spacing: 22) {
            ContentUnavailableView {
                Label("Couldn’t create artwork", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { beginRetry() }
            }
            .frame(minHeight: 340)

            Text("You can still share the report link from the Year in Music screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var artworkExplanation: some View {
        Text("ListenBrainz creates this artwork on demand. Cover images and fonts load from ListenBrainz, Internet Archive, and Google Fonts. Brainz keeps the SVG in memory for the rest of the day.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var artworkAccessibilityLabel: String {
        var parts = [
            String(localized: "Official ListenBrainz Year in Music \(report.year) artwork"),
            listenCountLabel(report.totals.listenCount),
            artistCountLabel(report.totals.artistCount),
        ]
        if let artist = report.topArtists.first?.name {
            parts.append(String(localized: "top artist \(artist)"))
        }
        return parts.joined(separator: String(localized: ", "))
    }

    private func listenCountLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "\(count.formatted()) listen")
            : String(localized: "\(count.formatted()) listens")
    }

    private func artistCountLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "\(count.formatted()) artist")
            : String(localized: "\(count.formatted()) artists")
    }

    private func beginRetry() {
        retryTask?.cancel()
        retryTask = Task { await model.retry() }
    }
}

#if DEBUG
struct VisualQAYearInMusicArtworkProvider: YearInMusicArtworkProviding {
    func artwork(for options: YearInMusicArtworkOptions) async throws -> YearInMusicArtwork? {
        try await ContinuousClock().sleep(for: .milliseconds(180))
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="924" height="924" viewBox="0 0 924 924">
          <defs>
            <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#160d30"/>
              <stop offset="0.48" stop-color="#5f247a"/>
              <stop offset="1" stop-color="#eb406f"/>
            </linearGradient>
            <radialGradient id="glow" cx="0.82" cy="0.1" r="0.72">
              <stop offset="0" stop-color="#ffcf6d" stop-opacity="0.82"/>
              <stop offset="1" stop-color="#ffcf6d" stop-opacity="0"/>
            </radialGradient>
          </defs>
          <rect width="924" height="924" fill="url(#background)"/>
          <rect width="924" height="924" fill="url(#glow)"/>
          <circle cx="846" cy="82" r="216" fill="#ff7b80" opacity="0.2"/>
          <circle cx="86" cy="868" r="248" fill="#253592" opacity="0.5"/>
          <path d="M-40 658 C170 552 322 756 526 620 S807 514 984 574" fill="none" stroke="#fff" stroke-opacity="0.17" stroke-width="3"/>
          <path d="M-40 688 C170 582 322 786 526 650 S807 544 984 604" fill="none" stroke="#fff" stroke-opacity="0.1" stroke-width="3"/>
          <g fill="#fff" font-family="-apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif">
            <text x="64" y="78" font-size="22" font-weight="700" letter-spacing="5" opacity="0.72">LISTENBRAINZ</text>
            <text x="64" y="206" font-size="25" font-weight="700" letter-spacing="5" opacity="0.72">YOUR \(options.year)</text>
            <text x="58" y="305" font-size="88" font-weight="800" letter-spacing="-4">YEAR IN</text>
            <text x="58" y="392" font-size="88" font-weight="800" letter-spacing="-4">MUSIC</text>
            <text x="64" y="508" font-size="58" font-weight="750">18,742</text>
            <text x="64" y="542" font-size="20" font-weight="650" letter-spacing="4" opacity="0.7">LISTENS</text>
            <text x="374" y="508" font-size="58" font-weight="750">1,286</text>
            <text x="374" y="542" font-size="20" font-weight="650" letter-spacing="4" opacity="0.7">ARTISTS</text>
            <text x="651" y="508" font-size="58" font-weight="750">4,982</text>
            <text x="651" y="542" font-size="20" font-weight="650" letter-spacing="4" opacity="0.7">HOURS</text>
            <text x="64" y="768" font-size="20" font-weight="650" letter-spacing="3" opacity="0.66">TOP ARTIST</text>
            <text x="64" y="820" font-size="42" font-weight="750">Alvvays</text>
            <text x="64" y="866" font-size="21" font-weight="600" opacity="0.66">visual-taste · generated by ListenBrainz</text>
          </g>
        </svg>
        """
        return YearInMusicArtwork(options: options, source: LBYearInMusicArtwork(svg: svg))
    }
}
#endif
