import SwiftUI
import UIKit

struct GeneratedArtworkPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let accessibilityLabel: String
    let shareSubject: String
    let shareMessage: String
    let fileName: String

    static func statistics(
        username: String,
        period: ListeningActivityPeriod
    ) -> Self {
        let periodName = period.title
        let sourceURL = listenBrainzURL(path: "/user/\(username)/stats/")
        return Self(
            title: String(localized: "Stats artwork"),
            detail: String(localized: "Listening period: \(periodName)"),
            accessibilityLabel: String(localized: "ListenBrainz stats artwork. \(periodName)."),
            shareSubject: String(localized: "My ListenBrainz stats"),
            shareMessage: String(localized: "My ListenBrainz listening stats — \(periodName): \(sourceURL.absoluteString)"),
            fileName: "ListenBrainz-stats-\(period.artRange.rawValue).png"
        )
    }

    static func artist(name: String, mbid: UUID) -> Self {
        let sourceURL = listenBrainzURL(
            path: "/artist/\(mbid.uuidString.lowercased())"
        )
        return Self(
            title: String(localized: "Artist artwork"),
            detail: String(localized: "A cover grid for \(name)."),
            accessibilityLabel: String(localized: "ListenBrainz cover grid for \(name)"),
            shareSubject: String(localized: "\(name) on ListenBrainz"),
            shareMessage: String(localized: "A ListenBrainz cover grid for \(name): \(sourceURL.absoluteString)"),
            fileName: "ListenBrainz-artist-\(mbid.uuidString.lowercased()).png"
        )
    }

    static func playlist(
        title: String,
        mbid: UUID,
        sourceURL: URL
    ) -> Self {
        Self(
            title: String(localized: "Playlist artwork"),
            detail: String(localized: "Artwork for “\(title)”."),
            accessibilityLabel: String(localized: "ListenBrainz artwork for the playlist \(title)"),
            shareSubject: String(localized: "\(title) on ListenBrainz"),
            shareMessage: String(localized: "Artwork for “\(title)” on ListenBrainz: \(sourceURL.absoluteString)"),
            fileName: "ListenBrainz-playlist-\(mbid.uuidString.lowercased()).png"
        )
    }

    static func customAlbumCollage(
        username: String,
        albumCount: Int
    ) -> Self {
        let sourceURL = listenBrainzURL(path: "/user/\(username)/stats/")
        let detail = albumCount == 1
            ? String(localized: "One album you chose from your listening history.")
            : String(localized: "\(albumCount.formatted()) albums you chose from your listening history.")
        let accessibilityLabel = albumCount == 1
            ? String(localized: "ListenBrainz album collage with one cover")
            : String(localized: "ListenBrainz album collage with \(albumCount.formatted()) covers")
        return Self(
            title: String(localized: "Album collage"),
            detail: detail,
            accessibilityLabel: accessibilityLabel,
            shareSubject: String(localized: "My ListenBrainz album collage"),
            shareMessage: String(localized: "An album collage from my ListenBrainz history: \(sourceURL.absoluteString)"),
            fileName: "ListenBrainz-album-collage.png"
        )
    }

    private static func listenBrainzURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "listenbrainz.org"
        components.path = path
        return components.url!
    }
}

struct GeneratedArtworkSheet: View {
    let presentation: GeneratedArtworkPresentation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: GeneratedArtworkModel
    @State private var snapshotPhase: SVGArtworkSnapshotPhase = .preparing
    @State private var snapshotReloadID = 0
    @State private var retryTask: Task<Void, Never>?

    init(
        presentation: GeneratedArtworkPresentation,
        request: GeneratedArtworkRequest,
        provider: any GeneratedArtworkProviding
    ) {
        self.presentation = presentation
        _model = State(
            initialValue: GeneratedArtworkModel(
                request: request,
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
            .navigationTitle(presentation.title)
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
        case let .ready(document):
            readyContent(document)
        case .unavailable:
            unavailableContent
        case let .failed(message):
            failureContent(message)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.secondary.opacity(0.1))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Creating artwork…")
                            .font(.headline)
                        Text("ListenBrainz is building the image.")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("ListenBrainz is creating artwork")
                .frame(maxWidth: previewMaximumWidth)

            resourceDisclosure
        }
    }

    private func readyContent(_ document: GeneratedArtworkDocument) -> some View {
        VStack(spacing: 20) {
            SVGArtworkPreview(
                svg: document.svg,
                reloadID: snapshotReloadID,
                accessibilityLabel: presentation.accessibilityLabel
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
            .accessibilityLabel(presentation.accessibilityLabel)
            .frame(maxWidth: previewMaximumWidth)

            Text(presentation.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            shareControls
            resourceDisclosure
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
        case let .ready(image):
            if let data = image.pngData() {
                ShareLink(
                    item: SVGPNGShareItem(
                        data: data,
                        fileName: presentation.fileName
                    ),
                    subject: Text(presentation.shareSubject),
                    message: Text(presentation.shareMessage),
                    preview: SharePreview(
                        presentation.shareSubject,
                        image: Image(uiImage: image)
                    )
                ) {
                    Label("Share artwork", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.accent)
                .accessibilityHint("Shares a PNG copy and its ListenBrainz link")
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
                Text("ListenBrainz doesn’t have enough artwork or listening data for this image yet.")
            }
            .frame(minHeight: 340)

            resourceDisclosure
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

            resourceDisclosure
        }
    }

    private var resourceDisclosure: some View {
        Text("ListenBrainz creates this artwork on demand. Cover images and fonts load from ListenBrainz, Internet Archive, and Google Fonts. Sharing is optional.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var previewMaximumWidth: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? 300 : nil
    }

    private func beginRetry() {
        retryTask?.cancel()
        retryTask = Task { await model.retry() }
    }
}

#if DEBUG
struct GenericArtVisualQAScreen: View {
    enum Fixture {
        case populated
        case unavailable
        case failure
    }

    let fixture: Fixture

    var body: some View {
        GeneratedArtworkSheet(
            presentation: .statistics(
                username: "visual-listener",
                period: .thisMonth
            ),
            request: .statistics(
                username: "visual-listener",
                range: .thisMonth
            ),
            provider: VisualQAGeneratedArtworkProvider(fixture: fixture)
        )
    }
}

struct CustomArtPreviewVisualQAScreen: View {
    var body: some View {
        GeneratedArtworkSheet(
            presentation: .customAlbumCollage(
                username: "visual-listener",
                albumCount: Self.releaseMBIDs.count
            ),
            request: .custom(
                releaseMBIDs: Self.releaseMBIDs,
                dimension: 3,
                layout: .one
            ),
            provider: VisualQAGeneratedArtworkProvider(fixture: .populated)
        )
    }

    private static let releaseMBIDs = (1 ... 6).map { number in
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                number
            )
        )!
    }
}

struct VisualQAGeneratedArtworkProvider: GeneratedArtworkProviding {
    let fixture: GenericArtVisualQAScreen.Fixture

    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> GeneratedArtworkDocument? {
        try await ContinuousClock().sleep(for: .milliseconds(180))
        switch fixture {
        case .populated:
            return GeneratedArtworkDocument(
                request: request,
                svg: Self.fixtureSVG
            )
        case .unavailable:
            return nil
        case .failure:
            throw GeneratedArtworkProviderError.creationFailed
        }
    }

    private static let fixtureSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="924" height="924" viewBox="0 0 924 924">
      <defs>
        <linearGradient id="a" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#ffb13b"/><stop offset="1" stop-color="#c83373"/></linearGradient>
        <linearGradient id="b" x1="1" y1="0" x2="0" y2="1"><stop stop-color="#37b6b3"/><stop offset="1" stop-color="#173d70"/></linearGradient>
        <linearGradient id="c" x1="0" y1="1" x2="1" y2="0"><stop stop-color="#8b62df"/><stop offset="1" stop-color="#e04d82"/></linearGradient>
      </defs>
      <rect width="924" height="924" fill="#100d19"/>
      <g>
        <rect x="0" y="0" width="308" height="308" fill="url(#a)"/><circle cx="154" cy="154" r="88" fill="#111" opacity=".42"/><circle cx="154" cy="154" r="15" fill="#fff" opacity=".75"/>
        <rect x="308" y="0" width="308" height="308" fill="url(#b)"/><path d="M330 232 L460 62 L594 232 Z" fill="#f8df82" opacity=".72"/>
        <rect x="616" y="0" width="308" height="308" fill="url(#c)"/><path d="M655 72 H885 V242 H655 Z" fill="none" stroke="#fff" stroke-width="18" opacity=".62"/>
        <rect x="0" y="308" width="308" height="308" fill="#e6634f"/><path d="M0 540 Q154 350 308 540 V616 H0 Z" fill="#6f244d"/>
        <rect x="308" y="308" width="308" height="308" fill="#efc648"/><g fill="#252035"><circle cx="462" cy="462" r="105"/><circle cx="462" cy="462" r="34" fill="#efc648"/></g>
        <rect x="616" y="308" width="308" height="308" fill="#377ac4"/><path d="M616 616 L770 334 L924 616 Z" fill="#7dd8c1" opacity=".8"/>
        <rect x="0" y="616" width="308" height="308" fill="#4a286e"/><circle cx="80" cy="720" r="95" fill="#e86f91"/><circle cx="254" cy="842" r="118" fill="#f0a446" opacity=".7"/>
        <rect x="308" y="616" width="308" height="308" fill="#182a46"/><path d="M338 876 C400 670 528 670 590 876" fill="none" stroke="#65c2dc" stroke-width="22"/>
        <rect x="616" y="616" width="308" height="308" fill="#c94269"/><g fill="#fff" opacity=".75"><rect x="680" y="678" width="180" height="18"/><rect x="680" y="722" width="136" height="18"/><rect x="680" y="766" width="164" height="18"/></g>
      </g>
      <rect x="0" y="760" width="924" height="164" fill="#08070d" opacity=".86"/>
      <g fill="#fff" font-family="-apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif">
        <text x="46" y="814" font-size="20" font-weight="700" letter-spacing="5" opacity=".72">LISTENBRAINZ</text>
        <text x="42" y="880" font-size="48" font-weight="760">YOUR MONTH IN MUSIC</text>
      </g>
    </svg>
    """
}
#endif
