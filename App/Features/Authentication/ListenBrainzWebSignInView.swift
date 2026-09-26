import SwiftUI
@preconcurrency import WebKit

/// The official pages own credential collection. This view only moves an
/// already-authenticated browser session to Settings and reads its readonly
/// ListenBrainz token there for validation by `SessionModel`.
struct ListenBrainzWebSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SessionModel
    @State private var visibleHost = "listenbrainz.org"
    @State private var phase: ListenBrainzWebSignInPhase = .credentials
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .accessibilityHidden(true)
                        Text("Official site: \(visibleHost)")
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("official-sign-in-host")
                    }
                    .font(.subheadline.weight(.semibold))
                    Text("Enter your password only on the official page. Brainz never sees or saves it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.thinMaterial)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                ZStack {
                    ListenBrainzWebSignInBrowser(
                        phase: $phase,
                        visibleHost: $visibleHost,
                        errorMessage: $errorMessage,
                        onToken: { token in
                            let attempt = session.beginSignInAttempt()
                            Task { @MainActor in
                                await session.signIn(token: token, attempt: attempt)
                                if case .active = session.state {
                                    dismiss()
                                } else if errorMessage == nil {
                                    errorMessage = session.errorMessage ?? String(
                                        localized: "We couldn’t verify this sign-in. Try again or use your token instead."
                                    )
                                }
                            }
                        },
                        onCancelled: {
                            session.cancelPendingSignIn()
                        }
                    )

                    if phase != .credentials, errorMessage == nil {
                        ProgressView("Finishing sign-in…")
                            .padding(20)
                            .background(.regularMaterial, in: .rect(cornerRadius: 16, style: .continuous))
                            .accessibilityElement(children: .combine)
                    }

                    if let errorMessage {
                        ContentUnavailableView {
                            Label("Sign-in unavailable", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try again") {
                                phase = .credentials
                                self.errorMessage = nil
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Use a token instead") { dismiss() }
                                .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(.background)
                    }
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onDisappear {
                session.cancelPendingSignIn()
            }
            .privacySensitive()
        }
    }
}

enum ListenBrainzWebSignInPhase: Equatable {
    case credentials
    case extracting
    case completed
}

enum ListenBrainzWebSignInPolicy {
    enum Browser: Sendable {
        case credentials
        case extraction
    }

    static let startURL = URL(
        string: "https://listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F"
    )!
    static let settingsURL = URL(string: "https://listenbrainz.org/settings/")!
    private static let authorizeClientID = "5i5ZSOSjNGDCVt3yOovLkDb2"
    private static let authorizeRedirectURI = "https://listenbrainz.org/login/musicbrainz/post/"
    private static let authorizeScopes: Set<String> = ["email", "musicbrainz:rating", "musicbrainz:tag", "profile"]

    struct Authorization: Equatable, Sendable {
        let state: String
    }

    enum CredentialRoute: Equatable, Sendable {
        case initial
        case authorize(Authorization)
        case login(Authorization)
        case callback(code: String, authorization: Authorization)
        case completion
    }

    static func credentialRoute(
        for url: URL,
        method: String,
        matching expectedAuthorization: Authorization?
    ) -> CredentialRoute? {
        guard let components = secureComponents(url), let host = components.host?.lowercased() else {
            return nil
        }
        let requestMethod = method.uppercased()
        if host == "listenbrainz.org",
           components.percentEncodedPath == "/login/musicbrainz/",
           requestMethod == "GET",
           hasExactSettingsNext(components) {
            return .initial
        }
        if host == "metabrainz.org",
           components.percentEncodedPath == "/oauth2/authorize",
           (requestMethod == "GET" || (requestMethod == "POST" && expectedAuthorization != nil)),
           let authorization = authorization(from: components) {
            guard expectedAuthorization == nil || expectedAuthorization == authorization else { return nil }
            return .authorize(authorization)
        }
        if host == "metabrainz.org", components.percentEncodedPath == "/login", requestMethod == "GET" || requestMethod == "POST", let activeAuthorization = expectedAuthorization, loginNext(in: components, matches: activeAuthorization) {
            return .login(activeAuthorization)
        }
        if host == "listenbrainz.org", components.percentEncodedPath == "/login/musicbrainz/post/", requestMethod == "GET", let activeAuthorization = expectedAuthorization, let code = callbackCode(in: components, matching: activeAuthorization) {
            return .callback(code: code, authorization: activeAuthorization)
        }
        if host == "listenbrainz.org",
           components.percentEncodedPath == "/settings/",
           requestMethod == "GET",
           expectedAuthorization != nil,
           hasNoQuery(components) {
            return .completion
        }
        return nil
    }

    static func permits(_ url: URL, in browser: Browser) -> Bool {
        switch browser {
        case .credentials:
            return credentialRoute(for: url, method: "GET", matching: nil) != nil
        case .extraction:
            guard let components = secureComponents(url) else { return false }
            return components.host?.lowercased() == "listenbrainz.org"
                && components.percentEncodedPath == "/settings/"
                && hasNoQuery(components)
        }
    }

    static func canonicalToken(from rawToken: String) -> String? {
        guard rawToken == rawToken.trimmingCharacters(in: .whitespacesAndNewlines),
              let uuid = UUID(uuidString: rawToken),
              uuid.uuidString.lowercased() == rawToken
        else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }

    private static func secureComponents(_ url: URL) -> URLComponents? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              host == "listenbrainz.org" || host == "metabrainz.org"
        else { return nil }
        return components
    }

    private static func hasNoQuery(_ components: URLComponents) -> Bool {
        components.percentEncodedQuery == nil
    }

    private static func hasExactSettingsNext(_ components: URLComponents) -> Bool {
        guard let values = uniqueQueryValues(in: components) else { return false }
        return Set(values.keys) == ["next"] && values["next"] == "/settings/"
    }

    private static func authorization(from components: URLComponents) -> Authorization? {
        guard let values = uniqueQueryValues(in: components),
              Set(values.keys) == ["access_type", "client_id", "redirect_uri", "response_type", "scope", "state"],
              values["access_type"] == "offline",
              values["client_id"] == authorizeClientID,
              values["redirect_uri"] == authorizeRedirectURI,
              values["response_type"] == "code",
              let scope = values["scope"],
              Set(scope.split(whereSeparator: { $0 == " " || $0 == "+" }).map(String.init)) == authorizeScopes,
              scope.split(whereSeparator: { $0 == " " || $0 == "+" }).count == authorizeScopes.count,
              let state = values["state"], isOpaqueValue(state)
        else { return nil }
        return Authorization(state: state)
    }

    private static func loginNext(in components: URLComponents, matches expectedAuthorization: Authorization) -> Bool {
        guard let values = uniqueQueryValues(in: components),
              Set(values.keys) == ["next"],
              let next = values["next"],
              next.hasPrefix("/oauth2/authorize?"),
              let nested = URLComponents(string: "https://metabrainz.org" + next),
              let nestedURL = nested.url,
              let securedNested = secureComponents(nestedURL),
              securedNested.host?.lowercased() == "metabrainz.org",
              securedNested.percentEncodedPath == "/oauth2/authorize",
              authorization(from: securedNested) == expectedAuthorization
        else { return false }
        return true
    }

    private static func callbackCode(in components: URLComponents, matching authorization: Authorization) -> String? {
        guard let values = uniqueQueryValues(in: components),
              Set(values.keys) == ["code", "state"],
              values["state"] == authorization.state,
              let code = values["code"], isOpaqueValue(code)
        else { return nil }
        return code
    }

    private static func uniqueQueryValues(in components: URLComponents) -> [String: String]? {
        guard let items = components.queryItems, !items.isEmpty else { return nil }
        var values: [String: String] = [:]
        for item in items {
            guard let value = item.value, !item.name.isEmpty, values[item.name] == nil else { return nil }
            values[item.name] = value
        }
        return values
    }

    private static func isOpaqueValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7E }
    }
}

private struct ListenBrainzWebSignInBrowser: UIViewRepresentable {
    @Binding var phase: ListenBrainzWebSignInPhase
    @Binding var visibleHost: String
    @Binding var errorMessage: String?
    let onToken: @MainActor (String) -> Void
    let onCancelled: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            phase: $phase,
            visibleHost: $visibleHost,
            errorMessage: $errorMessage,
            onToken: onToken,
            onCancelled: onCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.makeContainer()
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.update(
            phase: phase,
            errorMessage: errorMessage,
            onToken: onToken,
            onCancelled: onCancelled
        )
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var phase: Binding<ListenBrainzWebSignInPhase>
        private var visibleHost: Binding<String>
        private var errorMessage: Binding<String?>
        private var onToken: @MainActor (String) -> Void
        private var onCancelled: @MainActor () -> Void
        private var generation = 0
        private var renderedPhase: ListenBrainzWebSignInPhase = .credentials
        private var credentialFlow: CredentialFlow = .initial
        private var hasRequestedExtraction = false
        private var hasDeliveredToken = false
        private let dataStore = WKWebsiteDataStore.nonPersistent()
        private var credentialWebView: WKWebView?
        private var extractionWebView: WKWebView?

        private enum CredentialFlow: Equatable {
            case initial
            case authorization(ListenBrainzWebSignInPolicy.Authorization)
            case login(ListenBrainzWebSignInPolicy.Authorization)
            case callback(ListenBrainzWebSignInPolicy.Authorization)
        }

        init(
            phase: Binding<ListenBrainzWebSignInPhase>,
            visibleHost: Binding<String>,
            errorMessage: Binding<String?>,
            onToken: @escaping @MainActor (String) -> Void,
            onCancelled: @escaping @MainActor () -> Void
        ) {
            self.phase = phase
            self.visibleHost = visibleHost
            self.errorMessage = errorMessage
            self.onToken = onToken
            self.onCancelled = onCancelled
        }

        func makeContainer() -> UIView {
            let container = UIView()
            container.backgroundColor = .systemBackground
            let credentials = makeCredentialWebView()
            let extraction = makeExtractionWebView()
            credentialWebView = credentials
            extractionWebView = extraction
            [credentials, extraction].forEach { webView in
                webView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(webView)
                NSLayoutConstraint.activate([
                    webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    webView.topAnchor.constraint(equalTo: container.topAnchor),
                    webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }
            extraction.isHidden = true
            credentials.load(URLRequest(url: ListenBrainzWebSignInPolicy.startURL))
            renderedPhase = .credentials
            return container
        }

        func update(
            phase: ListenBrainzWebSignInPhase,
            errorMessage: String?,
            onToken: @escaping @MainActor (String) -> Void,
            onCancelled: @escaping @MainActor () -> Void
        ) {
            self.onToken = onToken
            self.onCancelled = onCancelled
            defer { renderedPhase = phase }
            guard phase == .credentials, renderedPhase != .credentials else { return }
            resetForRetry()
        }

        func invalidate() {
            generation &+= 1
            credentialWebView?.stopLoading()
            extractionWebView?.stopLoading()
            credentialWebView?.navigationDelegate = nil
            extractionWebView?.navigationDelegate = nil
            credentialWebView?.uiDelegate = nil
            extractionWebView?.uiDelegate = nil
            credentialWebView = nil
            extractionWebView = nil
            clearEphemeralData()
            onCancelled()
        }

        private func makeCredentialWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = dataStore
            // The official OAuth pages may require their own JavaScript. Brainz
            // injects no user scripts and registers no script message handlers.
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.allowsLinkPreview = false
            return webView
        }

        private func makeExtractionWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = dataStore
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.isUserInteractionEnabled = false
            webView.allowsLinkPreview = false
            webView.accessibilityElementsHidden = true
            return webView
        }

        private func resetForRetry() {
            generation &+= 1
            hasRequestedExtraction = false
            hasDeliveredToken = false
            credentialFlow = .initial
            errorMessage.wrappedValue = nil
            visibleHost.wrappedValue = "listenbrainz.org"
            extractionWebView?.stopLoading()
            extractionWebView?.isHidden = true
            credentialWebView?.isHidden = false
            let retryGeneration = generation
            clearEphemeralData { [weak self] in
                guard let self, self.generation == retryGeneration else { return }
                self.credentialWebView?.load(URLRequest(url: ListenBrainzWebSignInPolicy.startURL))
            }
        }

        private func beginExtraction() {
            guard !hasRequestedExtraction else { return }
            hasRequestedExtraction = true
            phase.wrappedValue = .extracting
            visibleHost.wrappedValue = "listenbrainz.org"
            credentialWebView?.stopLoading()
            credentialWebView?.isHidden = true
            extractionWebView?.isHidden = true
            extractionWebView?.load(URLRequest(url: ListenBrainzWebSignInPolicy.settingsURL))
        }

        private func fail(_ message: String) {
            guard !hasDeliveredToken else { return }
            generation &+= 1
            credentialWebView?.stopLoading()
            extractionWebView?.stopLoading()
            clearEphemeralData()
            errorMessage.wrappedValue = message
        }

        private func clearEphemeralData(completion: @escaping @MainActor () -> Void = {}) {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
                Task { @MainActor in completion() }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.targetFrame != nil,
                  let url = navigationAction.request.url
            else { return .cancel }
            if webView === credentialWebView {
                switch advanceCredentialFlow(
                    url: url,
                    method: navigationAction.request.httpMethod ?? "GET"
                ) {
                case .allow:
                    break
                case .beginExtraction:
                    beginExtraction()
                    return .cancel
                case .reject:
                    fail(String(localized: "This page isn’t part of the secure sign-in flow. Try again or use your token instead."))
                    return .cancel
                }
            } else if !ListenBrainzWebSignInPolicy.permits(url, in: .extraction) {
                fail(String(localized: "We couldn’t open ListenBrainz settings safely. Try again or use your token instead."))
                return .cancel
            }
            visibleHost.wrappedValue = url.host?.lowercased() ?? "listenbrainz.org"
            return .allow
        }

        private enum CredentialAdvance {
            case allow
            case beginExtraction
            case reject
        }

        private func advanceCredentialFlow(url: URL, method: String) -> CredentialAdvance {
            let currentAuthorization: ListenBrainzWebSignInPolicy.Authorization?
            switch credentialFlow {
            case .initial:
                currentAuthorization = nil
            case .authorization(let authorization), .login(let authorization), .callback(let authorization):
                currentAuthorization = authorization
            }
            guard let route = ListenBrainzWebSignInPolicy.credentialRoute(
                for: url,
                method: method,
                matching: currentAuthorization
            ) else { return .reject }

            switch (credentialFlow, route) {
            case (.initial, .initial):
                return .allow
            case (.initial, .authorize(let authorization)),
                 (.login(_), .authorize(let authorization)),
                 (.authorization(_), .authorize(let authorization)):
                credentialFlow = .authorization(authorization)
                return .allow
            case (.authorization(let expected), .login(let authorization)) where expected == authorization,
                 (.login(let expected), .login(let authorization)) where expected == authorization:
                credentialFlow = .login(authorization)
                return .allow
            case (.authorization(let expected), .callback(_, let authorization)) where expected == authorization,
                 (.login(let expected), .callback(_, let authorization)) where expected == authorization:
                credentialFlow = .callback(authorization)
                return .allow
            case (.callback, .completion):
                return .beginExtraction
            default:
                return .reject
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse
        ) async -> WKNavigationResponsePolicy {
            guard navigationResponse.canShowMIMEType,
                  let response = navigationResponse.response as? HTTPURLResponse,
                  response.value(forHTTPHeaderField: "Content-Disposition") == nil
            else {
                fail(String(localized: "This sign-in page tried to download a file. Try again or use your token instead."))
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            if webView === extractionWebView,
                      ListenBrainzWebSignInPolicy.permits(url, in: .extraction) {
                extractToken(from: webView, generation: generation)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            reportFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            reportFailure(error)
        }

        private func reportFailure(_ error: any Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            fail(String(localized: "We couldn’t load the secure sign-in page. Check your connection and try again."))
        }

        private func extractToken(
            from webView: WKWebView,
            generation expectedGeneration: Int,
            remainingAttempts: Int = 5
        ) {
            // This is the only script the flow evaluates. It reads one readonly
            // Settings input after strict URL validation and sends nothing back.
            let script = """
            (() => {
              const input = document.getElementById('auth-token');
              if (location.origin !== 'https://listenbrainz.org' || location.pathname !== '/settings/' || !(input instanceof HTMLInputElement) || !input.readOnly) return '';
              return input.value;
            })()
            """
            webView.evaluateJavaScript(script) { [weak self] value, _ in
                Task { @MainActor in
                    guard let self,
                          self.generation == expectedGeneration,
                          !self.hasDeliveredToken else { return }
                    guard let value = value as? String,
                          let token = ListenBrainzWebSignInPolicy.canonicalToken(from: value) else {
                        guard remainingAttempts > 1 else {
                            self.fail(String(localized: "We couldn’t finish sign-in. Try again or use your token instead."))
                            return
                        }
                        try? await Task.sleep(for: .seconds(1))
                        guard self.generation == expectedGeneration else { return }
                        self.extractToken(
                            from: webView,
                            generation: expectedGeneration,
                            remainingAttempts: remainingAttempts - 1
                        )
                        return
                    }
                    self.hasDeliveredToken = true
                    self.phase.wrappedValue = .completed
                    self.clearEphemeralData { [weak self] in
                        guard let self,
                              self.generation == expectedGeneration,
                              self.hasDeliveredToken else { return }
                        self.onToken(token)
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? { nil }

        @available(iOS 18.4, *)
        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor ([URL]?) -> Void
        ) {
            completionHandler(nil)
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.deny)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor () -> Void
        ) {
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor (Bool) -> Void
        ) {
            completionHandler(false)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor (String?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
