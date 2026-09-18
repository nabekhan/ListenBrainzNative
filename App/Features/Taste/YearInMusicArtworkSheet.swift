import CoreTransferable
import ListenBrainzKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import UIKit
@preconcurrency import WebKit

enum YearInMusicArtworkRenderingPolicy {
    static let contentRuleList = #"""
    [
      {"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"^https://archive\\.org/download/.*"},"action":{"type":"ignore-previous-rules"}},
      {"trigger":{"url-filter":"^https://fonts\\.googleapis\\.com/.*"},"action":{"type":"ignore-previous-rules"}},
      {"trigger":{"url-filter":"^https://fonts\\.gstatic\\.com/.*"},"action":{"type":"ignore-previous-rules"}}
    ]
    """#

    static func permitsExternalResource(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        switch url.host?.lowercased() {
        case "archive.org":
            return url.path.hasPrefix("/download/")
        case "fonts.googleapis.com", "fonts.gstatic.com":
            return true
        default:
            return false
        }
    }
}

private enum YearInMusicArtworkSnapshotPhase {
    case preparing
    case ready(UIImage)
    case failed(String)
}

struct YearInMusicArtworkSheet: View {
    let report: YearInMusicReport
    let reportURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: YearInMusicArtworkModel
    @State private var snapshotPhase: YearInMusicArtworkSnapshotPhase = .preparing
    @State private var snapshotReloadID = 0

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
                options: .init(username: username, year: report.year),
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
            .navigationTitle("Shareable Artwork")
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
        .onDisappear { model.cancel() }
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
                        Text("Creating your overview…")
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
            YearInMusicSVGPreview(svg: artwork.svg, reloadID: snapshotReloadID) { phase in
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
                        Text("Official ListenBrainz overview")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityElement(children: .combine)
                } else {
                    Label("Official ListenBrainz overview", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                }
                Text("Generated from your \(String(report.year)) listening report.")
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
                    item: YearInMusicPNGShareItem(data: pngData, year: report.year),
                    subject: Text("My \(String(report.year)) Year in Music"),
                    message: Text("My \(String(report.year)) listening story on ListenBrainz: \(reportURL.absoluteString)"),
                    preview: SharePreview(
                        "ListenBrainz Year in Music \(String(report.year))",
                        image: Image(uiImage: shareImage)
                    )
                ) {
                    Label("Share Artwork", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.accent)
                .accessibilityHint("Shares a PNG copy and the ListenBrainz report link")
            } else {
                snapshotFailure("The rendered artwork could not be encoded as a PNG.")
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
            Button("Prepare Again") {
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
                Text("ListenBrainz does not have enough data to create this overview.")
            } actions: {
                Button("Try Again") { Task { await model.retry() } }
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
                Button("Try Again") { Task { await model.retry() } }
            }
            .frame(minHeight: 340)

            Text("You can still share the report link from the Year in Music screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var artworkExplanation: some View {
        Text("ListenBrainz generates this artwork on demand. Once created, Brainz keeps it ready in memory for the rest of the day.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var artworkAccessibilityLabel: String {
        var parts = [
            "Official ListenBrainz Year in Music \(String(report.year)) overview",
            "\(report.totals.listenCount.formatted()) listens",
            "\(report.totals.artistCount.formatted()) artists",
        ]
        if let artist = report.topArtists.first?.name {
            parts.append("top artist \(artist)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct YearInMusicSVGPreview: UIViewRepresentable {
    let svg: String
    let reloadID: Int
    let onSnapshot: @MainActor (YearInMusicArtworkSnapshotPhase) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSnapshot: onSnapshot)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.allowsLinkPreview = false
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSnapshot = onSnapshot
        guard context.coordinator.loadedSVG != svg
                || context.coordinator.loadedReloadID != reloadID,
              let data = svg.data(using: .utf8)
        else { return }

        let generation = context.coordinator.prepareToLoad(svg, reloadID: reloadID)
        let encodedSVG = data.base64EncodedString()
        let document = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; object-src data:; img-src data: https:; font-src data: https:; style-src 'unsafe-inline' https:; form-action 'none'; base-uri 'none'">
            <style>
              html, body, object { width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden; }
              body { background: transparent; }
              object { display: block; border: 0; }
            </style>
          </head>
          <body>
            <object type="image/svg+xml" data="data:image/svg+xml;base64,\(encodedSVG)" aria-label="ListenBrainz Year in Music artwork"></object>
          </body>
        </html>
        """
        context.coordinator.load(
            document: document,
            in: webView,
            generation: generation
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private static let logger = Logger(subsystem: "dev.nabekhan.listenbrainznative", category: "YearInMusicArtwork")
        private static let ruleListIdentifier = "Brainz-YearInMusicArtworkResources-v1"

        var onSnapshot: @MainActor (YearInMusicArtworkSnapshotPhase) -> Void
        private(set) var loadedSVG: String?
        private(set) var loadedReloadID: Int?
        private var generation = 0

        init(onSnapshot: @escaping @MainActor (YearInMusicArtworkSnapshotPhase) -> Void) {
            self.onSnapshot = onSnapshot
        }

        func prepareToLoad(_ svg: String, reloadID: Int) -> Int {
            loadedSVG = svg
            loadedReloadID = reloadID
            generation += 1
            return generation
        }

        func load(document: String, in webView: WKWebView, generation requestedGeneration: Int) {
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    let rules = try await Self.compileContentRules()
                    guard generation == requestedGeneration else { return }
                    webView.configuration.userContentController.removeAllContentRuleLists()
                    webView.configuration.userContentController.add(rules)
                    webView.loadHTMLString(
                        document,
                        baseURL: URL(string: "https://api.listenbrainz.org/")
                    )
                    captureWhenReady(webView, generation: requestedGeneration)
                } catch {
                    guard generation == requestedGeneration else { return }
                    Self.logger.error("Year in Music resource policy failed: \(error.localizedDescription, privacy: .public)")
                    onSnapshot(.failed("Brainz couldn’t prepare the secure artwork renderer."))
                }
            }
        }

        private static func compileContentRules() async throws -> WKContentRuleList {
            try await withCheckedThrowingContinuation { continuation in
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: ruleListIdentifier,
                    encodedContentRuleList: YearInMusicArtworkRenderingPolicy.contentRuleList
                ) { rules, error in
                    if let rules {
                        continuation.resume(returning: rules)
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.coderInvalidValue))
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            switch navigationAction.navigationType {
            case .linkActivated, .formSubmitted, .formResubmitted:
                return .cancel
            default:
                return .allow
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Self.logger.debug("Year in Music SVG document finished loading")
        }

        func captureWhenReady(_ webView: WKWebView, generation requestedGeneration: Int) {
            Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .milliseconds(750))
                guard let self,
                      let webView,
                      generation == requestedGeneration
                else { return }

                for _ in 0 ..< 30 where webView.isLoading {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard generation == requestedGeneration else { return }
                }
                try? await Task.sleep(for: .milliseconds(350))

                let configuration = WKSnapshotConfiguration()
                configuration.snapshotWidth = 924
                webView.takeSnapshot(with: configuration) { [weak self] image, error in
                    guard let self, generation == requestedGeneration else { return }
                    if let error {
                        Self.logger.error("Year in Music snapshot failed: \(error.localizedDescription, privacy: .public)")
                        onSnapshot(.failed("The high-resolution copy could not be rendered."))
                    } else if let image {
                        Self.logger.debug("Year in Music PNG snapshot is ready")
                        onSnapshot(.ready(image))
                    } else {
                        Self.logger.error("Year in Music snapshot returned no image")
                        onSnapshot(.failed("The high-resolution copy could not be rendered."))
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            Self.logger.error("Year in Music SVG navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            Self.logger.error("Year in Music SVG provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct YearInMusicPNGShareItem: Transferable, Sendable {
    let data: Data
    let year: Int

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "Brainz-Shared-Artwork", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "ListenBrainz-Year-in-Music-\(item.year).png")
            try item.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
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
