import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    static let storageKey = "app.appearance"

    case system
    case light
    case dark

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum SettingsLinks {
    static let listenBrainzSettings = URL(string: "https://listenbrainz.org/settings/")!
    static let privacyPolicy = URL(
        string: "https://github.com/nabekhan/ListenBrainzNative/blob/main/PRIVACY.md"
    )!
    static let metaBrainzPrivacyChoices = URL(string: "https://metabrainz.org/gdpr")!
    static let repository = URL(string: "https://github.com/nabekhan/ListenBrainzNative")!
    static let thirdPartyNotices = URL(
        string: "https://github.com/nabekhan/ListenBrainzNative/blob/main/THIRD_PARTY.md"
    )!
    static let issues = URL(string: "https://github.com/nabekhan/ListenBrainzNative/issues")!
    static let privateSecurityReport = URL(
        string: "https://github.com/nabekhan/ListenBrainzNative/security/advisories/new"
    )!

    static func listenBrainzProfile(username: String) -> URL {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "https://listenbrainz.org/user/\(encodedUsername)/")!
    }
}

enum SettingsAppVersion {
    static func current(bundle: Bundle = .main) -> String {
        display(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    static func display(version: String?, build: String?) -> String {
        let version = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = build?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)) where version != build:
            return "\(version) (\(build))"
        case let (.some(version), _):
            return version
        case let (_, .some(build)):
            return build
        default:
            return "—"
        }
    }
}

struct SettingsView: View {
    let account: Account
    @Bindable var session: SessionModel

    private let connectedServicesProvider: (any ConnectedServicesProviding)?
    private let connectedServicesCache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @State private var showsDisconnectConfirmation: Bool
    @State private var isDisconnecting = false

    init(
        account: Account,
        session: SessionModel,
        connectedServicesProvider: (any ConnectedServicesProviding)? = nil,
        connectedServicesCache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices> = ConnectedServicesCaches.values,
        initiallyShowsDisconnectConfirmation: Bool = false
    ) {
        self.account = account
        _session = Bindable(wrappedValue: session)
        self.connectedServicesProvider = connectedServicesProvider
        self.connectedServicesCache = connectedServicesCache
        _showsDisconnectConfirmation = State(initialValue: initiallyShowsDisconnectConfirmation)
    }

    var body: some View {
        Form {
            accountSection
            appearanceSection
            listenBrainzSection
            privacySection
            aboutSection
            sessionSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Disconnect from ListenBrainz?",
            isPresented: $showsDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect account", role: .destructive) {
                Task { await disconnect() }
            }
            Button("Keep connected", role: .cancel) {}
        } message: {
            Text("Brainz will remove the saved token and listening snapshot from this device. Small records that prevent repeated changes may remain. Your ListenBrainz account and listening data won’t be deleted.")
        }
        .alert(
            disconnectErrorTitle,
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )
        ) {
            Button("Try again") { Task { await disconnect() } }
            Button("Not now", role: .cancel) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var accountSection: some View {
        Section("Account") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Username")
                Text(verbatim: account.username)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityConnectionStatus
            } else {
                HStack(spacing: 12) {
                    Text("Status")
                    Spacer(minLength: 12)
                    connectionStatus
                }
            }
        }
    }

    @ViewBuilder private var connectionStatus: some View {
        if account.isAuthenticated {
            Label("Connected", systemImage: "checkmark.seal.fill")
                .foregroundStyle(AppTheme.secondary)
        } else {
            Label("Public profile", systemImage: "eye.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var accessibilityConnectionStatus: some View {
        if account.isAuthenticated {
            Label("Connected to ListenBrainz", systemImage: "checkmark.seal.fill")
                .foregroundStyle(AppTheme.secondary)
        } else {
            Label("Public profile", systemImage: "eye.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Use your device appearance or choose a theme for Brainz.")
        }
    }

    private var listenBrainzSection: some View {
        Section {
            if account.isAuthenticated {
                NavigationLink {
                    ConnectedServicesView(
                        account: account,
                        provider: connectedServicesProvider,
                        cache: connectedServicesCache
                    )
                } label: {
                    Label("Connected services", systemImage: "link")
                }
            }

            Link(destination: SettingsLinks.listenBrainzProfile(username: account.username)) {
                Label("Open profile on ListenBrainz", systemImage: "person.crop.circle")
            }

            if account.isAuthenticated {
                Link(destination: SettingsLinks.listenBrainzSettings) {
                    Label("Manage settings on ListenBrainz", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("ListenBrainz")
        } footer: {
            if account.isAuthenticated {
                Text("Manage your timezone, player, token, data export, and account deletion on ListenBrainz.")
            }
        }
    }

    private var privacySection: some View {
        Section {
            Link(destination: SettingsLinks.privacyPolicy) {
                Label("Read Brainz privacy policy", systemImage: "hand.raised")
            }
            Link(destination: SettingsLinks.metaBrainzPrivacyChoices) {
                Label("Review MetaBrainz privacy choices", systemImage: "person.badge.shield.checkmark")
            }
        } header: {
            Text("Privacy & data")
        } footer: {
            Text("Brainz connects directly to ListenBrainz and related metadata services. It has no ads or tracking software.")
        }
    }

    private var aboutSection: some View {
        Section("About Brainz") {
            LabeledContent("Version") {
                Text(verbatim: SettingsAppVersion.current())
                    .foregroundStyle(.secondary)
            }
            Link(destination: SettingsLinks.repository) {
                Label("View source code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: SettingsLinks.thirdPartyNotices) {
                Label("Read open-source notices", systemImage: "doc.text")
            }
            Link(destination: SettingsLinks.issues) {
                Label("Report a problem", systemImage: "exclamationmark.bubble")
            }
            Link(destination: SettingsLinks.privateSecurityReport) {
                Label("Report a security issue privately", systemImage: "lock.shield")
            }
        }
    }

    private var sessionSection: some View {
        Section {
            if isDisconnecting {
                HStack(spacing: 10) {
                    ProgressView()
                    if account.isAuthenticated {
                        Text("Disconnecting…")
                    } else {
                        Text("Leaving profile…")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if account.isAuthenticated {
                Button("Disconnect account", role: .destructive) {
                    showsDisconnectConfirmation = true
                }
            } else {
                Button("Leave public profile") {
                    Task { await disconnect() }
                }
            }
        } footer: {
            if account.isAuthenticated {
                Text("Disconnecting removes the saved token and listening snapshot. Small records that prevent repeated changes may remain. Your ListenBrainz account and listening data stay unchanged.")
            } else {
                Text("Leaving returns to sign-in. You can browse this public profile again at any time.")
            }
        }
    }

    private func disconnect() async {
        guard !isDisconnecting else { return }
        session.errorMessage = nil
        isDisconnecting = true
        await session.signOut()
        isDisconnecting = false
    }

    private var disconnectErrorTitle: String {
        if account.isAuthenticated {
            String(localized: "Couldn’t disconnect account")
        } else {
            String(localized: "Couldn’t leave public profile")
        }
    }
}

#if DEBUG
    struct SettingsVisualQAScreen: View {
        @State private var session = SessionModel(credentialStore: SettingsVisualCredentialStore())

        private let account: Account
        private let showsDisconnectConfirmation: Bool

        init(isPublic: Bool, showsDisconnectConfirmation: Bool) {
            account = Account(
                username: isPublic ? "public-music-explorer" : "visual-listener-with-a-long-name",
                token: isPublic ? "" : "visual-token"
            )
            self.showsDisconnectConfirmation = showsDisconnectConfirmation
        }

        var body: some View {
            NavigationStack {
                SettingsView(
                    account: account,
                    session: session,
                    connectedServicesProvider: SettingsVisualConnectedServicesProvider(),
                    connectedServicesCache: EntityDetailCache(),
                    initiallyShowsDisconnectConfirmation: showsDisconnectConfirmation
                )
            }
        }
    }

    private struct SettingsVisualCredentialStore: CredentialStoring {
        func load() async throws -> LoadedCredential? { nil }
        func save(_ credential: StoredCredential) throws {}
        func delete() async throws {}
    }

    private struct SettingsVisualConnectedServicesProvider: ConnectedServicesProviding {
        func connectedServices(username: String) async throws -> ConnectedServices {
            ConnectedServices(identifiers: ["spotify", "musicbrainz-prod"])
        }
    }
#endif
