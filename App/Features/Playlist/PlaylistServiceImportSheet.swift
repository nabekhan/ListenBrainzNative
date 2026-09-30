import ListenBrainzKit
import SwiftUI

struct PlaylistServiceImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: PlaylistServiceImportModel
    @State private var pendingPlaylist: PlaylistServiceImportItem?
    @State private var playlistPendingReset: PlaylistServiceImportItem?
    @State private var listingTask: Task<Void, Never>?
    @State private var importTask: Task<Void, Never>?

    private let onImportConfirmed: (UUID) -> Void
    private let onReviewOwnedPlaylists: () -> Void

    init(
        account: Account,
        provider: (any PlaylistServiceImportProviding)? = nil,
        cache: EntityDetailCache<PlaylistServiceImportCacheKey, PlaylistServiceImportList> = PlaylistServiceImportCaches.values,
        journal: PlaylistServiceImportJournal = .shared,
        onImportConfirmed: @escaping (UUID) -> Void = { _ in },
        onReviewOwnedPlaylists: @escaping () -> Void = {}
    ) {
        if let provider {
            _model = State(initialValue: PlaylistServiceImportModel(
                account: account,
                provider: provider,
                cache: cache,
                journal: journal
            ))
        } else {
            _model = State(initialValue: PlaylistServiceImportModel(
                account: account,
                cache: cache,
                journal: journal
            ))
        }
        self.onImportConfirmed = onImportConfirmed
        self.onReviewOwnedPlaylists = onReviewOwnedPlaylists
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    stateContent
                    serviceManagementLink
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Import from Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isImporting)
        .onDisappear {
            listingTask?.cancel()
            importTask?.cancel()
            model.cancelListing()
        }
        .alert(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingPlaylist != nil },
                set: { if !$0 { pendingPlaylist = nil } }
            )
        ) {
            if let pendingPlaylist {
                Button("Import playlist") {
                    let playlist = pendingPlaylist
                    self.pendingPlaylist = nil
                    startImport(playlist)
                }
            }
            Button("Cancel", role: .cancel) { pendingPlaylist = nil }
        } message: {
            Text("ListenBrainz creates a separate copy. Future Spotify changes won’t sync.")
        }
        .alert(
            "Import again?",
            isPresented: Binding(
                get: { playlistPendingReset != nil },
                set: { if !$0 { playlistPendingReset = nil } }
            )
        ) {
            if let playlistPendingReset {
                Button("Allow import", role: .destructive) {
                    model.clearAfterUserReview(playlistPendingReset)
                    self.playlistPendingReset = nil
                }
            }
            Button("Cancel", role: .cancel) { playlistPendingReset = nil }
        } message: {
            Text("Check Owned Playlists first to avoid duplicates.")
        }
        .alert(item: noticeBinding) { notice in
            switch notice {
            case let .confirmed(_, playlist, playlistMBID):
                Alert(
                    title: Text("Playlist imported"),
                    message: Text(String(localized: "“\(playlist.title)” was added to Owned Playlists.")),
                    primaryButton: .default(Text("View owned playlists")) {
                        finishConfirmedImport(playlist, playlistMBID: playlistMBID, dismissSheet: true)
                    },
                    secondaryButton: .cancel(Text("Keep browsing")) {
                        finishConfirmedImport(playlist, playlistMBID: playlistMBID, dismissSheet: false)
                    }
                )
            case let .confirmedRecoveryNeeded(_, _, message):
                Alert(
                    title: Text("Playlist imported"),
                    message: Text(message),
                    primaryButton: .default(Text("View owned playlists")) {
                        model.acknowledgeConfirmedRecoveryNotice()
                        onReviewOwnedPlaylists()
                        dismiss()
                    },
                    secondaryButton: .cancel(Text("Not now")) {
                        model.acknowledgeConfirmedRecoveryNotice()
                    }
                )
            case let .failed(_, message):
                Alert(
                    title: Text("Couldn’t import playlist"),
                    message: Text(message),
                    dismissButton: .default(Text("Dismiss")) {
                        model.dismissFailureNotice()
                    }
                )
            case let .verificationNeeded(_, _, message):
                Alert(
                    title: Text("Check Owned Playlists"),
                    message: Text(message),
                    primaryButton: .default(Text("View owned playlists")) {
                        model.acknowledgeVerificationNotice()
                        onReviewOwnedPlaylists()
                        dismiss()
                    },
                    secondaryButton: .cancel(Text("Not now")) {
                        model.acknowledgeVerificationNotice()
                    }
                )
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 82, height: 82)
                .background(AppTheme.accent.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text("Bring a Spotify playlist to ListenBrainz")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Choose a linked playlist and create a separate ListenBrainz copy.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.phase {
        case .idle:
            idleCard
        case .loading:
            loadingCard
        case let .failed(message):
            failureCard(message)
        case let .loaded(list):
            if list.playlists.isEmpty {
                loadedContent(list)
            } else {
                loadedContent(list)
                    .searchable(
                        text: $model.searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search Spotify playlists"
                    )
            }
        }
    }

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Load playlists when you’re ready", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("Brainz asks ListenBrainz for your Spotify playlists only after you tap Load.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                startListing(refreshing: false)
            } label: {
                Label("Load Spotify playlists", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isListing || model.isRefreshCoolingDown)
            .accessibilityHint("Loads playlists from your linked Spotify account")
            .accessibilityIdentifier("playlist-import-load")
        }
        .cardStyle()
    }

    private var loadingCard: some View {
        HStack(spacing: 13) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text("Loading Spotify playlists…")
                    .font(.headline)
                Text("ListenBrainz is checking your linked account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("playlist-import-loading")
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn’t load Spotify playlists", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .accessibilityIdentifier("playlist-import-failed")
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { startListing(refreshing: true) }
                .buttonStyle(.borderedProminent)
                .disabled(model.isListing || model.isRefreshCoolingDown)
                .accessibilityIdentifier("playlist-import-retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private func loadedContent(_ list: PlaylistServiceImportList) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.isListing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Refreshing Spotify playlists…")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("playlist-import-refreshing")
            }

            if list.isTruncated {
                Label(
                    "Showing the first 100 playlists. Search applies to this list only.",
                    systemImage: "info.circle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.accent.opacity(0.10), in: .rect(cornerRadius: 15, style: .continuous))
            }

            if let refreshMessage = model.refreshMessage {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Showing saved playlists", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Text(refreshMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Refresh") { startListing(refreshing: true) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isListing || model.isRefreshCoolingDown)
                }
                .cardStyle()
            }

            if list.playlists.isEmpty {
                ContentUnavailableView(
                    "No Spotify playlists found",
                    systemImage: "music.note.list",
                    description: Text("Create a Spotify playlist or reconnect Spotify on ListenBrainz, then refresh.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .cardStyle()
                .accessibilityIdentifier("playlist-import-empty")
            } else if model.filteredPlaylists.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .cardStyle()
                    .accessibilityIdentifier("playlist-import-no-results")
            } else {
                LazyVStack(spacing: 11) {
                    ForEach(model.filteredPlaylists) { playlist in
                        if model.requiresReview(for: playlist) {
                            reviewCard(playlist)
                        } else {
                            playlistButton(playlist)
                        }
                    }
                }
            }
        }
    }

    private func playlistButton(_ playlist: PlaylistServiceImportItem) -> some View {
        Button {
            pendingPlaylist = playlist
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 11) {
                        rowArtwork(playlist)
                        rowText(playlist)
                        rowProgressOrDisclosure(playlist)
                    }
                } else {
                    HStack(spacing: 13) {
                        rowArtwork(playlist)
                        rowText(playlist)
                        Spacer(minLength: 4)
                        rowProgressOrDisclosure(playlist)
                    }
                }
            }
            .padding(13)
            .contentShape(.rect)
        }
        .accessibilityLabel(rowAccessibilityLabel(playlist))
        .accessibilityHint("Opens import confirmation")
        .accessibilityIdentifier("playlist-import-row-\(playlist.externalID)")
        .buttonStyle(.plain)
        .disabled(model.isImporting)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func rowArtwork(_ playlist: PlaylistServiceImportItem) -> some View {
        ArtworkView(
            url: playlist.artworkURL,
            title: playlist.title,
            cornerRadius: 11,
            requestPolicy: .spotifyImport
        )
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 76 : 64, height: dynamicTypeSize.isAccessibilitySize ? 76 : 64)
        .accessibilityHidden(true)
    }

    private func rowText(_ playlist: PlaylistServiceImportItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(playlist.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let ownerName = playlist.ownerName {
                Text("By \(ownerName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { rowMetadata(playlist) }
                VStack(alignment: .leading, spacing: 4) { rowMetadata(playlist) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowMetadata(_ playlist: PlaylistServiceImportItem) -> some View {
        if let trackCount = playlist.trackCount {
            Label("\(trackCount) tracks", systemImage: "music.note")
        }
        if playlist.isCollaborative {
            Label("Collaborative", systemImage: "person.2.fill")
        } else if let isPublic = playlist.isPublic {
            Label(isPublic ? "Public" : "Private", systemImage: isPublic ? "globe" : "lock.fill")
        }
    }

    @ViewBuilder
    private func rowProgressOrDisclosure(_ playlist: PlaylistServiceImportItem) -> some View {
        if model.isImporting, model.activePlaylistID == playlist.id {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Importing playlist")
        } else {
            Image(systemName: "chevron.forward")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private func reviewCard(_ playlist: PlaylistServiceImportItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Check Owned Playlists before importing again", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("playlist-import-recovery-\(playlist.externalID)")
            Text(model.verificationMessage(for: playlist))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) { reviewActions(playlist) }
                } else {
                    HStack(spacing: 14) { reviewActions(playlist) }
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func reviewActions(_ playlist: PlaylistServiceImportItem) -> some View {
        Button("Check Owned Playlists") {
            onReviewOwnedPlaylists()
            dismiss()
        }
        .accessibilityIdentifier("playlist-import-review-owned-\(playlist.externalID)")
        Button("Import again") {
            playlistPendingReset = playlist
        }
        .disabled(model.isImporting)
        .accessibilityIdentifier("playlist-import-allow-again-\(playlist.externalID)")
    }

    private var serviceManagementLink: some View {
        VStack(spacing: 7) {
            Link(
                "Manage Spotify connection on ListenBrainz",
                destination: URL(string: "https://listenbrainz.org/settings/music-services/details/")!
            )
            .font(.subheadline.weight(.semibold))
            .accessibilityHint("Opens ListenBrainz in your browser")
            Text("Spotify must be linked with playlist permissions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model.loadedList != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    startListing(refreshing: true)
                }
                .disabled(model.isImporting || model.isListing || model.isRefreshCoolingDown)
                .accessibilityHint("Reloads playlists from Spotify")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .disabled(model.isImporting)
        }
    }

    private var confirmationTitle: String {
        guard let pendingPlaylist else { return String(localized: "Import playlist?") }
        return String(localized: "Import “\(pendingPlaylist.title)”?" )
    }

    private var noticeBinding: Binding<PlaylistServiceImportNotice?> {
        Binding(get: { model.notice }, set: { _ in })
    }

    private func startListing(refreshing: Bool) {
        listingTask?.cancel()
        listingTask = Task {
            if refreshing {
                await model.refresh()
            } else {
                await model.load()
            }
        }
    }

    private func startImport(_ playlist: PlaylistServiceImportItem) {
        importTask?.cancel()
        importTask = Task { await model.importPlaylist(playlist) }
    }

    private func finishConfirmedImport(
        _ playlist: PlaylistServiceImportItem,
        playlistMBID: UUID,
        dismissSheet: Bool
    ) {
        guard model.acknowledgeConfirmedImport(playlist) else { return }
        onImportConfirmed(playlistMBID)
        if dismissSheet { dismiss() }
    }

    private func rowAccessibilityLabel(_ playlist: PlaylistServiceImportItem) -> String {
        var parts = [playlist.title]
        if let ownerName = playlist.ownerName {
            parts.append(String(localized: "by \(ownerName)"))
        }
        if let trackCount = playlist.trackCount {
            parts.append(String(localized: "\(trackCount) tracks"))
        }
        if playlist.isCollaborative {
            parts.append(String(localized: "Collaborative"))
        } else if let isPublic = playlist.isPublic {
            parts.append(isPublic ? String(localized: "Public") : String(localized: "Private"))
        }
        return parts.joined(separator: ", ")
    }
}

private extension View {
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(.thinMaterial, in: .rect(cornerRadius: 19, style: .continuous))
    }
}

#if DEBUG
enum PlaylistServiceImportVisualMode {
    case populated
    case empty
    case failure
    case recovery
    case indeterminate
}

struct PlaylistServiceImportVisualQAScreen: View {
    private let mode: PlaylistServiceImportVisualMode
    private let account = Account(username: "visual-listener", token: "visual-token")
    private let journal: PlaylistServiceImportJournal

    init(mode: PlaylistServiceImportVisualMode) {
        self.mode = mode
        let journal = PlaylistServiceImportJournal()
        if mode == .recovery {
            _ = journal.beginAttempt(
                username: "visual-listener",
                service: .spotify,
                externalPlaylistID: VisualQAPlaylistServiceImportProvider.primary.externalID,
                at: Date(timeIntervalSince1970: 1_789_689_600)
            )
            journal.releaseClaim(
                username: "visual-listener",
                service: .spotify,
                externalPlaylistID: VisualQAPlaylistServiceImportProvider.primary.externalID
            )
        }
        self.journal = journal
    }

    var body: some View {
        PlaylistServiceImportSheet(
            account: account,
            provider: VisualQAPlaylistServiceImportProvider(mode: mode),
            cache: EntityDetailCache(),
            journal: journal
        )
    }
}

private struct VisualQAPlaylistServiceImportProvider: PlaylistServiceImportProviding {
    let mode: PlaylistServiceImportVisualMode

    func playlists(from service: PlaylistExternalService) async throws -> PlaylistServiceImportList {
        try await Task.sleep(for: .milliseconds(120))
        if mode == .failure { throw LBError.badRequest }
        return PlaylistServiceImportList(
            service: .spotify,
            playlists: mode == .empty ? [] : Self.playlists,
            isTruncated: mode == .populated
        )
    }

    func importPlaylist(_ playlist: PlaylistServiceImportItem) async throws -> UUID {
        try await Task.sleep(for: .milliseconds(180))
        if mode == .indeterminate {
            throw PlaylistServiceImportProviderError.indeterminateImport
        }
        return UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    }

    static let primary = PlaylistServiceImportItem(
        service: .spotify,
        externalID: "4NHQUGzhtTLFvgF5SZesLK",
        title: "Soft focus — late-night favorites",
        summary: "Dream pop, ambient edges, and songs for quieter rooms.",
        artworkURL: nil,
        ownerName: "visual-listener",
        trackCount: 42,
        isPublic: false,
        isCollaborative: false
    )

    private static let playlists = [
        primary,
        PlaylistServiceImportItem(
            service: .spotify,
            externalID: "37i9dQZF1DX4WYpdgoIcn6",
            title: "Prairie drives and very long summer evenings",
            summary: nil,
            artworkURL: nil,
            ownerName: "cassetteclub",
            trackCount: 86,
            isPublic: true,
            isCollaborative: true
        ),
        PlaylistServiceImportItem(
            service: .spotify,
            externalID: "37i9dQZF1DWZd79rJ6a7lp",
            title: "Songs I keep coming back to",
            summary: nil,
            artworkURL: nil,
            ownerName: nil,
            trackCount: 18,
            isPublic: nil,
            isCollaborative: false
        ),
    ]
}
#endif
