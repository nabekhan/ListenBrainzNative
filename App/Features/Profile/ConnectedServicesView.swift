import SwiftUI

struct ConnectedServicesView: View {
    @State private var model: ConnectedServicesModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        account: Account,
        provider: (any ConnectedServicesProviding)? = nil,
        cache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices> = ConnectedServicesCaches.values
    ) {
        _model = State(initialValue: ConnectedServicesModel(
            account: account,
            provider: provider,
            cache: cache
        ))
    }

    init(
        account: Account,
        scope: RequestGate.ReadScope = .isolated(),
        provider: some ConnectedServicesProviding,
        cache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices> = ConnectedServicesCaches.values
    ) {
        _model = State(initialValue: ConnectedServicesModel(
            account: account,
            scope: scope,
            provider: provider,
            cache: cache
        ))
    }

    var body: some View {
        Group {
            if model.account.isAuthenticated {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hero
                        content
                        manageLink
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .refreshable { await model.refresh() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await model.refresh() }
                        }
                        .disabled(model.phase == .loading)
                    }
                }
                .task { await model.load() }
                .onDisappear { model.cancel() }
            } else {
                ContentUnavailableView(
                    "Connected services are private",
                    systemImage: "lock.fill",
                    description: Text("Sign in to view the services linked to your ListenBrainz account.")
                )
            }
        }
        .navigationTitle("Connected services")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "link")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(AppTheme.artworkGradient(seed: "connected-services"), in: .rect(cornerRadius: 17, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Your music services")
                    .font(.headline)
                Text("Services linked to this ListenBrainz account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("Loading connected services…")
                .frame(maxWidth: .infinity, minHeight: 220)
        case let .failed(message):
            ContentUnavailableView {
                Label("Connected services couldn’t load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.refresh() } }
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        case let .loaded(services):
            if services.services.isEmpty {
                ContentUnavailableView(
                    "No connected services",
                    systemImage: "link.badge.plus",
                    description: Text("Link a music service on ListenBrainz to see it here.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let refreshMessage = model.refreshMessage {
                        warning(refreshMessage)
                    }
                    Text("Linked services")
                        .font(.headline)
                    ForEach(services.services) { service in
                        serviceRow(service)
                    }
                }
            }
        }
    }

    private func serviceRow(_ service: ConnectedService) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        serviceIcon(service)
                        Text(service.label ?? "Other service")
                            .font(.body.weight(.semibold))
                    }
                    serviceStatus(service)
                }
            } else {
                HStack(spacing: 13) {
                    serviceIcon(service)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.label ?? "Other service")
                            .font(.body.weight(.semibold))
                        serviceStatus(service)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func serviceIcon(_ service: ConnectedService) -> some View {
        Image(systemName: service.label == nil ? "link" : "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(service.label == nil ? .secondary : AppTheme.secondary)
            .accessibilityHidden(true)
    }

    private func serviceStatus(_ service: ConnectedService) -> some View {
        Text(service.label == nil ? service.identifier : String(localized: "Connected to ListenBrainz"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private func warning(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var manageLink: some View {
        Link(destination: URL(string: "https://listenbrainz.org/settings/music-services/details/")!) {
            Label("Manage services on ListenBrainz", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .accessibilityHint("Opens ListenBrainz in your browser")
    }
}
