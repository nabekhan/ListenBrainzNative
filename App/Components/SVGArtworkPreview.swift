import CoreTransferable
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import UIKit
@preconcurrency import WebKit

enum SVGArtworkRenderingPolicy {
    static let contentRuleList = #"""
    [
      {
        "trigger": {"url-filter": "^https?://.*"},
        "action": {"type": "block"}
      },
      {
        "trigger": {"url-filter": "^https://archive\\.org(?::443)?/download/mbid-[0-9a-fA-F-]+/mbid-[0-9a-fA-F-]+-[0-9]+_thumb250\\.jpg$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://archive\\.org(?::443)?/download/mbid-[0-9a-fA-F-]+/mbid-[0-9a-fA-F-]+-[0-9]+_thumb500\\.jpg$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://dn[0-9]+\\.ca\\.archive\\.org(?::443)?/0/items/mbid-[0-9a-fA-F-]+/mbid-[0-9a-fA-F-]+-[0-9]+_thumb250\\.jpg$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://dn[0-9]+\\.ca\\.archive\\.org(?::443)?/0/items/mbid-[0-9a-fA-F-]+/mbid-[0-9a-fA-F-]+-[0-9]+_thumb500\\.jpg$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://fonts\\.googleapis\\.com(?::443)?/css2\\?family=Inter:wght@300;900$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://fonts\\.googleapis\\.com(?::443)?/css2\\?family=Inter:wght@300;500;900$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://fonts\\.googleapis\\.com(?::443)?/css2\\?family=Anonymous%20Pro:wght@400;700$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://fonts\\.gstatic\\.com(?::443)?/s/inter/[A-Za-z0-9._/~%+-]+\\.woff2$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://fonts\\.gstatic\\.com(?::443)?/s/anonymouspro/[A-Za-z0-9._/~%+-]+\\.woff2$"},
        "action": {"type": "ignore-previous-rules"}
      },
      {
        "trigger": {"url-filter": "^https://listenbrainz\\.org(?::443)?/static/img/cover-art-placeholder-grid\\.png$"},
        "action": {"type": "ignore-previous-rules"}
      }
    ]
    """#

    private static let allowedFontQueries = Set([
        "family=Inter:wght@300;900",
        "family=Inter:wght@300;500;900",
        "family=Anonymous Pro:wght@400;700",
    ])

    static func permitsExternalResource(_ url: URL) -> Bool {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "https",
        let host = components.host?.lowercased(),
        components.user == nil,
        components.password == nil,
        components.fragment == nil,
        components.port == nil || components.port == 443
        else {
            return false
        }

        let path = components.percentEncodedPath
        switch host {
        case "archive.org":
            guard components.percentEncodedQuery == nil else { return false }
            return permitsArchivePath(
                path,
                leadingComponents: ["download"]
            )
        case let value where isArchiveCDNHost(value):
            guard components.percentEncodedQuery == nil else { return false }
            return permitsArchivePath(
                path,
                leadingComponents: ["0", "items"]
            )
        case "fonts.googleapis.com":
            guard path == "/css2",
                  let query = components.percentEncodedQuery?.removingPercentEncoding
            else {
                return false
            }
            return allowedFontQueries.contains(query)
        case "fonts.gstatic.com":
            guard components.percentEncodedQuery == nil else { return false }
            return path.range(
                of: #"^/s/(inter|anonymouspro)/[A-Za-z0-9._/~+-]+\.woff2$"#,
                options: .regularExpression
            ) != nil
        case "listenbrainz.org":
            return components.percentEncodedQuery == nil
                && path == "/static/img/cover-art-placeholder-grid.png"
        default:
            return false
        }
    }

    static func permitsExternalResources(in svg: String) -> Bool {
        guard let data = svg.data(using: .utf8) else { return false }
        let collector = SVGExternalResourceCollector()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        guard parser.parse(), !collector.foundInvalidReference else {
            return false
        }
        return collector.urls.allSatisfy(permitsExternalResource)
    }

    private static func permitsArchivePath(
        _ path: String,
        leadingComponents: [String]
    ) -> Bool {
        guard !path.contains("%") else { return false }
        let components = path.split(separator: "/").map(String.init)
        guard components.count == leadingComponents.count + 2,
              Array(components.prefix(leadingComponents.count)) == leadingComponents
        else {
            return false
        }

        let directory = components[leadingComponents.count].lowercased()
        let fileName = components[leadingComponents.count + 1].lowercased()
        guard directory.hasPrefix("mbid-"),
              let mbid = UUID(uuidString: String(directory.dropFirst(5))),
              directory == "mbid-\(mbid.uuidString.lowercased())"
        else {
            return false
        }

        let prefix = "\(directory)-"
        guard fileName.hasPrefix(prefix) else { return false }
        let remainder = fileName.dropFirst(prefix.count)

        let suffix: Substring
        if remainder.hasSuffix("_thumb250.jpg") {
            suffix = remainder.dropLast("_thumb250.jpg".count)
        } else if remainder.hasSuffix("_thumb500.jpg") {
            suffix = remainder.dropLast("_thumb500.jpg".count)
        } else {
            return false
        }
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    private static func isArchiveCDNHost(_ host: String) -> Bool {
        let suffix = ".ca.archive.org"
        guard host.hasPrefix("dn"), host.hasSuffix(suffix) else { return false }
        let start = host.index(host.startIndex, offsetBy: 2)
        let end = host.index(host.endIndex, offsetBy: -suffix.count)
        let identifier = host[start ..< end]
        return !identifier.isEmpty && identifier.allSatisfy(\.isNumber)
    }
}

typealias YearInMusicArtworkRenderingPolicy = SVGArtworkRenderingPolicy

private final class SVGExternalResourceCollector: NSObject, XMLParserDelegate {
    private static let resourceElements = Set(["image", "link", "script", "use"])
    private static let cssURLExpression = try! NSRegularExpression(
        pattern: #"url\(\s*['\"]?([^'\")\s]+)"#,
        options: .caseInsensitive
    )

    private var styleDepth = 0
    private var styleText = ""

    private(set) var urls: [URL] = []
    private(set) var foundInvalidReference = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.lowercased()
        if element == "style" {
            styleDepth += 1
        }

        if let inlineStyle = attributeDict.first(where: {
            $0.key.lowercased() == "style"
        })?.value {
            collectCSSReferences(from: inlineStyle)
        }

        guard Self.resourceElements.contains(element) else { return }
        for (name, value) in attributeDict {
            let attribute = name.lowercased()
            if attribute == "src" || attribute.hasSuffix("href") {
                collectResourceReference(value)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if styleDepth > 0 {
            styleText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "style" else { return }
        styleDepth = max(styleDepth - 1, 0)
        if styleDepth == 0 {
            collectCSSReferences(from: styleText)
            styleText = ""
        }
    }

    private func collectCSSReferences(from value: String) {
        let range = NSRange(value.startIndex..., in: value)
        for match in Self.cssURLExpression.matches(in: value, range: range) {
            guard let matchRange = Range(match.range(at: 1), in: value) else {
                continue
            }
            collectResourceReference(String(value[matchRange]))
        }
    }

    private func collectResourceReference(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.lowercased().hasPrefix("data:")
        else {
            return
        }

        let baseURL = URL(string: "https://api.listenbrainz.org/")!
        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            foundInvalidReference = true
            return
        }
        urls.append(url)
    }
}

enum SVGArtworkSnapshotPhase {
    case preparing
    case ready(UIImage)
    case failed(String)
}

struct SVGArtworkPreview: UIViewRepresentable {
    let svg: String
    let reloadID: Int
    let accessibilityLabel: String
    let onSnapshot: @MainActor (SVGArtworkSnapshotPhase) -> Void

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
        webView.accessibilityElementsHidden = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSnapshot = onSnapshot
        guard context.coordinator.loadedSVG != svg
                || context.coordinator.loadedReloadID != reloadID
        else {
            return
        }

        let generation = context.coordinator.prepareToLoad(
            svg,
            reloadID: reloadID
        )
        guard SVGArtworkRenderingPolicy.permitsExternalResources(in: svg),
              let data = svg.data(using: .utf8)
        else {
            onSnapshot(.failed(String(localized: "This artwork includes a resource Brainz can’t load safely.")))
            return
        }

        let encodedSVG = data.base64EncodedString()
        let escapedLabel = accessibilityLabel.htmlEscaped
        let document = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <meta name="referrer" content="no-referrer">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; object-src data:; img-src data: https://archive.org https://*.ca.archive.org https://listenbrainz.org; font-src data: https://fonts.gstatic.com; style-src 'unsafe-inline' https://fonts.googleapis.com; form-action 'none'; base-uri 'none'; connect-src 'none'; script-src 'none'">
            <style>
              html, body, object { width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden; }
              body { background: transparent; }
              object { display: block; border: 0; }
            </style>
          </head>
          <body>
            <object type="image/svg+xml" data="data:image/svg+xml;base64,\(encodedSVG)" aria-label="\(escapedLabel)"></object>
          </body>
        </html>
        """
        context.coordinator.load(
            document: document,
            in: webView,
            generation: generation
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidate()
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private static let logger = Logger(
            subsystem: "dev.nabekhan.listenbrainznative",
            category: "SVGArtworkPreview"
        )
        private static let ruleListIdentifier = "Brainz-SVGArtworkResources-v2"

        var onSnapshot: @MainActor (SVGArtworkSnapshotPhase) -> Void
        private(set) var loadedSVG: String?
        private(set) var loadedReloadID: Int?
        private var generation = 0
        private var snapshotGeneration: Int?

        init(
            onSnapshot: @escaping @MainActor (SVGArtworkSnapshotPhase) -> Void
        ) {
            self.onSnapshot = onSnapshot
        }

        func prepareToLoad(_ svg: String, reloadID: Int) -> Int {
            loadedSVG = svg
            loadedReloadID = reloadID
            generation += 1
            snapshotGeneration = nil
            onSnapshot(.preparing)
            return generation
        }

        func load(
            document: String,
            in webView: WKWebView,
            generation requestedGeneration: Int
        ) {
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    let rules = try await Self.compileContentRules()
                    guard generation == requestedGeneration else { return }
                    webView.configuration.userContentController
                        .removeAllContentRuleLists()
                    webView.configuration.userContentController.add(rules)
                    webView.loadHTMLString(
                        document,
                        baseURL: URL(string: "https://api.listenbrainz.org/")
                    )
                } catch {
                    guard generation == requestedGeneration else { return }
                    Self.logger.error(
                        "Artwork resource policy failed: \(error.localizedDescription, privacy: .public)"
                    )
                    onSnapshot(.failed(String(localized: "Brainz couldn’t prepare the secure artwork preview.")))
                }
            }
        }

        func invalidate() {
            generation += 1
            snapshotGeneration = nil
        }

        private static func compileContentRules() async throws -> WKContentRuleList {
            try await withCheckedThrowingContinuation { continuation in
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: ruleListIdentifier,
                    encodedContentRuleList: SVGArtworkRenderingPolicy.contentRuleList
                ) { rules, error in
                    if let rules {
                        continuation.resume(returning: rules)
                    } else {
                        continuation.resume(
                            throwing: error ?? CocoaError(.coderInvalidValue)
                        )
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
                .cancel
            default:
                .allow
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            captureWhenReady(webView, generation: generation)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            reportNavigationFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            reportNavigationFailure(error)
        }

        private func reportNavigationFailure(_ error: any Error) {
            Self.logger.error(
                "Artwork navigation failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        private func captureWhenReady(
            _ webView: WKWebView,
            generation requestedGeneration: Int
        ) {
            guard snapshotGeneration != requestedGeneration else { return }
            snapshotGeneration = requestedGeneration

            Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .milliseconds(750))
                guard let self,
                      let webView,
                      generation == requestedGeneration
                else {
                    return
                }

                for _ in 0 ..< 30 where webView.isLoading {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard generation == requestedGeneration else { return }
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard generation == requestedGeneration else { return }

                let configuration = WKSnapshotConfiguration()
                configuration.snapshotWidth = 924
                webView.takeSnapshot(with: configuration) { [weak self] image, error in
                    guard let self, generation == requestedGeneration else {
                        return
                    }
                    if let image {
                        onSnapshot(.ready(image))
                    } else {
                        if let error {
                            Self.logger.error(
                                "Artwork snapshot failed: \(error.localizedDescription, privacy: .public)"
                            )
                        }
                        onSnapshot(.failed(String(localized: "Brainz couldn’t prepare a high-resolution copy.")))
                    }
                }
            }
        }
    }
}

struct SVGPNGShareItem: Transferable, Sendable {
    let data: Data
    let fileName: String

    init(data: Data, fileName: String) {
        self.data = data
        self.fileName = Self.safePNGFileName(fileName)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "Brainz-Shared-Artwork", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appending(path: item.fileName)
            try item.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    private static func safePNGFileName(_ value: String) -> String {
        let stem = value
            .deletingPathExtension
            .unicodeScalars
            .map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "-"
                    || scalar == "_"
                    ? Character(String(scalar))
                    : "-"
            }
        let normalized = String(stem)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return "\(normalized.isEmpty ? "ListenBrainz-artwork" : normalized).png"
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }

    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
