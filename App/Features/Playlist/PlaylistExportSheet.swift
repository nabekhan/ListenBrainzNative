import SwiftUI

struct PlaylistExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let detail: PlaylistDetail
    private let exportError: PlaylistExportError?
    @State private var connectedServices: ConnectedServicesModel
    @State private var serviceExport: PlaylistServiceExportModel
    @State private var exportedPlaylistIsPublic: Bool
    @State private var pendingService: PlaylistExternalService?
    @State private var servicePendingReset: PlaylistExternalService?

    init(
        detail: PlaylistDetail,
        account: Account,
        connectedServicesProvider: (any ConnectedServicesProviding)? = nil,
        connectedServicesCache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices> = ConnectedServicesCaches.values,
        serviceExportProvider: (any PlaylistServiceExportProviding)? = nil,
        serviceExportJournal: PlaylistServiceExportJournal = .shared
    ) {
        self.detail = detail
        _connectedServices = State(initialValue: ConnectedServicesModel(
            account: account,
            provider: connectedServicesProvider,
            cache: connectedServicesCache
        ))
        _serviceExport = State(initialValue: PlaylistServiceExportModel(
            account: account,
            playlistMBID: detail.mbid,
            provider: serviceExportProvider,
            journal: serviceExportJournal
        ))
        _exportedPlaylistIsPublic = State(initialValue: detail.isPublic)
        do {
            try PlaylistJSPFEncoder.validate(detail)
            exportError = nil
        } catch let error as PlaylistExportError {
            exportError = error
        } catch {
            exportError = .tooLarge
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 84, height: 84)
                        .background(AppTheme.accent.opacity(0.12), in: .circle)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Take this playlist with you")
                            .font(.title2.bold())
                        Text("Save a file or create a copy in a linked music service.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    fileSection
                    serviceSection
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Export playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(serviceExport.isExporting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(serviceExport.isExporting)
        .onDisappear { connectedServices.cancel() }
        .alert(
            exportConfirmationTitle,
            isPresented: Binding(
                get: { pendingService != nil },
                set: { if !$0 { pendingService = nil } }
            )
        ) {
            if let pendingService {
                Button(String(localized: "Export to \(pendingService.label)")) {
                    let destination = pendingService
                    self.pendingService = nil
                    Task {
                        await serviceExport.export(
                            to: destination,
                            isPublic: exportedPlaylistIsPublic
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingService = nil }
        } message: {
            Text(exportConfirmationMessage)
        }
        .alert(
            resetConfirmationTitle,
            isPresented: Binding(
                get: { servicePendingReset != nil },
                set: { if !$0 { servicePendingReset = nil } }
            )
        ) {
            if let servicePendingReset {
                Button("Allow another export", role: .destructive) {
                    serviceExport.clearAfterUserReview(servicePendingReset)
                    self.servicePendingReset = nil
                }
            }
            Button("Cancel", role: .cancel) { servicePendingReset = nil }
        } message: {
            Text(resetConfirmationMessage)
        }
        .alert(item: noticeBinding) { notice in
            switch notice {
            case let .confirmed(service, url):
                Alert(
                    title: Text("Playlist exported"),
                    message: Text(String(localized: "“\(detail.title)” was created in \(service.label).")),
                    primaryButton: .default(Text(String(localized: "Open \(service.label)"))) {
                        serviceExport.acknowledgeConfirmedExport()
                        openURL(url)
                    },
                    secondaryButton: .cancel(Text("Done")) {
                        serviceExport.acknowledgeConfirmedExport()
                    }
                )
            case let .failed(_, message):
                Alert(
                    title: Text("Couldn’t export playlist"),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) {
                        serviceExport.dismissNotice()
                    }
                )
            case let .verificationNeeded(_, service, message):
                Alert(
                    title: Text(String(localized: "Check \(service.label)")),
                    message: Text(message),
                    dismissButton: .default(Text("Got it")) {
                        serviceExport.acknowledgeVerificationNotice()
                    }
                )
            }
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Playlist file", systemImage: "doc")
                .font(.headline)
            Text("Includes playlist details, tracks, and contributor names.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !detail.isPublic {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Private playlist", systemImage: "lock.fill")
                        .font(.headline)
                    Text("Anyone you share the file with can read its contents.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.orange.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
            }

            if let exportError {
                Label(exportError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ShareLink(
                    item: PlaylistJSPFShareItem(detail: detail),
                    preview: SharePreview(
                        detail.title,
                        image: Image(systemName: "music.note.list")
                    )
                ) {
                    Label("Share playlist file", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("The file is created on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Music services", systemImage: "music.note.list")
                .font(.headline)
            Text("ListenBrainz creates a separate copy. Later changes won’t sync automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if serviceExport.account.isAuthenticated {
                Toggle("Make exported playlist public", isOn: $exportedPlaylistIsPublic)
                    .disabled(serviceExport.isExporting)
                connectedServiceContent
            } else {
                Label(
                    "Sign in to export through a linked music service.",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Link(
                "Manage linked services on ListenBrainz",
                destination: URL(string: "https://listenbrainz.org/settings/music-services/details/")!
            )
            .font(.subheadline.weight(.semibold))
            .accessibilityHint("Opens ListenBrainz in your browser")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var connectedServiceContent: some View {
        switch connectedServices.phase {
        case .idle:
            Button {
                Task { await connectedServices.load() }
            } label: {
                Label("Show linked services", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Checks your ListenBrainz account for supported music services")
            .accessibilityIdentifier("playlist-load-linked-services")
        case .loading:
            ProgressView("Loading linked services…")
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await connectedServices.refresh() }
                }
            }
        case let .loaded(services):
            let destinations = services.playlistExportDestinations
            if let refreshMessage = connectedServices.refreshMessage {
                Label(refreshMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if destinations.isEmpty {
                Label(
                    "Connect Spotify, Apple Music, or SoundCloud to export this playlist.",
                    systemImage: "link.badge.plus"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(destinations) { service in
                    if serviceExport.requiresReview(for: service) {
                        reviewCard(service)
                    } else {
                        serviceButton(service)
                    }
                }
            }
        }
    }

    private func serviceButton(_ service: PlaylistExternalService) -> some View {
        Button {
            pendingService = service
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Export to \(service.label)"))
                        .font(.body.weight(.semibold))
                    Text("Creates a new playlist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if serviceExport.isExporting, serviceExport.activeService == service {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(String(localized: "Exporting to \(service.label)"))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(serviceExport.isExporting)
        .padding(14)
        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 15, style: .continuous))
        .accessibilityHint("Creates a separate playlist through ListenBrainz")
        .accessibilityIdentifier("playlist-service-export-\(service.rawValue)")
    }

    private func reviewCard(_ service: PlaylistExternalService) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(localized: "Check \(service.label) before exporting again"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            Text(serviceExport.verificationMessage(for: service))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) { reviewActions(service) }
                } else {
                    HStack(spacing: 14) { reviewActions(service) }
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 15, style: .continuous))
    }

    @ViewBuilder private func reviewActions(_ service: PlaylistExternalService) -> some View {
        Link(destination: service.serviceHomeURL) {
            Label(String(localized: "Open \(service.label)"), systemImage: "arrow.up.right.square")
        }
        Button("Allow another export") {
            servicePendingReset = service
        }
        .disabled(serviceExport.isExporting)
    }

    private var exportConfirmationTitle: String {
        guard let pendingService else { return String(localized: "Export playlist?") }
        return String(localized: "Export to \(pendingService.label)?")
    }

    private var exportConfirmationMessage: String {
        guard let pendingService else { return "" }
        let visibility = exportedPlaylistIsPublic
            ? String(localized: "public")
            : String(localized: "private")
        return String(localized: "Creates a \(visibility) \(pendingService.label) copy. Changes won’t sync.")
    }

    private var resetConfirmationTitle: String {
        guard let servicePendingReset else { return String(localized: "Allow another export?") }
        return String(localized: "Allow another \(servicePendingReset.label) export?")
    }

    private var resetConfirmationMessage: String {
        guard let servicePendingReset else { return "" }
        return String(localized: "Only continue after checking \(servicePendingReset.label). Another export could create a duplicate playlist.")
    }

    private var noticeBinding: Binding<PlaylistServiceExportNotice?> {
        Binding(
            get: { serviceExport.notice },
            set: { _ in }
        )
    }
}

#if DEBUG
struct PlaylistExportVisualQAScreen: View {
    var body: some View {
        PlaylistExportSheet(
            detail: Self.detail,
            account: .init(username: "visual-listener", token: "visual-token"),
            connectedServicesProvider: VisualQAPlaylistExportConnectedServicesProvider(),
            connectedServicesCache: EntityDetailCache(),
            serviceExportProvider: PlaylistServiceExportPreviewProvider(),
            serviceExportJournal: PlaylistServiceExportJournal()
        )
    }

    private static let detail = PlaylistDetail(
        mbid: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        title: "Soft Focus — late-night favorites",
        creator: "visual-listener",
        annotation: "Dream pop, ambient edges, and songs that make the room feel quieter.",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastModifiedAt: Date(timeIntervalSince1970: 1_789_689_600),
        isPublic: false,
        createdFor: nil,
        collaborators: ["cassetteclub", "softstatic"],
        copiedFrom: nil,
        tracks: [
            track(1, "Myth", "Beach House", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
            track(2, "Cherry-coloured Funk", "Cocteau Twins", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
            track(3, "Myth", "Beach House", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
        ]
    )

    private static func track(
        _ position: Int,
        _ title: String,
        _ artist: String,
        _ mbid: String
    ) -> PlaylistTrack {
        PlaylistTrack(
            position: position,
            recording: Recording(
                identity: .init(mbid: UUID(uuidString: mbid), msid: nil),
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: nil,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            addedAt: nil,
            addedBy: "visual-listener"
        )
    }
}

private struct VisualQAPlaylistExportConnectedServicesProvider: ConnectedServicesProviding {
    func connectedServices(username: String) async throws -> ConnectedServices {
        ConnectedServices(identifiers: ["spotify", "apple", "soundcloud"])
    }
}
#endif
