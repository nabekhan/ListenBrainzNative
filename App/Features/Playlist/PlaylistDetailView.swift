import SwiftUI

struct PlaylistDetailView: View {
    let playlist: SearchPlaylist
    let viewer: Account
    private let mutationProvider: any PlaylistMutationProviding
    private let mutationJournal: PlaylistMutationJournal
    private let automaticallyPresentsEditor: Bool
    private let automaticallyPresentsCopyConfirmation: Bool
    @State private var model: PlaylistDetailModel
    @State private var copyModel: PlaylistCopyModel
    @State private var showsEditor = false
    @State private var showsCopyConfirmation = false
    @State private var copyDestination: SearchPlaylist?
    @State private var didAutomaticallyPresentEditor = false
    @State private var didAutomaticallyPresentCopyConfirmation = false
    @State private var isPreparingEditor = false
    @State private var isPreparingCopy = false

    init(
        playlist: SearchPlaylist,
        viewer: Account,
        provider: (any PlaylistDetailProviding)? = nil,
        mutationProvider: (any PlaylistMutationProviding)? = nil,
        copyProvider: (any PlaylistCopyProviding)? = nil,
        copyProfileProvider: (any ProfilePlaylistsProviding)? = nil,
        cache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        mutationJournal: PlaylistMutationJournal = .shared,
        copyReconciliationJournal: PlaylistCopyReconciliationJournal = .shared,
        automaticallyPresentsEditor: Bool = false,
        automaticallyPresentsCopyConfirmation: Bool = false
    ) {
        self.playlist = playlist
        self.viewer = viewer
        self.mutationProvider = mutationProvider
            ?? ListenBrainzPlaylistMutationProvider(token: viewer.token)
        self.mutationJournal = mutationJournal
        self.automaticallyPresentsEditor = automaticallyPresentsEditor
        self.automaticallyPresentsCopyConfirmation = automaticallyPresentsCopyConfirmation
        let resolvedDetailProvider = provider
            ?? ListenBrainzMediaDetailProvider(token: viewer.token)
        _model = State(initialValue: PlaylistDetailModel(
            seed: playlist,
            account: viewer,
            provider: resolvedDetailProvider,
            cache: cache
        ))
        _copyModel = State(initialValue: PlaylistCopyModel(
            account: viewer,
            sourceMBID: playlist.playlistMBID,
            provider: copyProvider,
            detailProvider: resolvedDetailProvider,
            profileProvider: copyProfileProvider,
            reconciliationJournal: copyReconciliationJournal
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if model.accessWasLost {
                    accessLostContent
                } else {
                    hero
                    loadNotice
                    if copyModel.requiresReconciliation {
                        copyReconciliationNotice
                    }
                    if let detail = model.detail {
                        about(detail)
                        playlistFacts(detail)
                        tracks(detail)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
        }
        .refreshable { await model.refresh() }
        .background {
            AppTheme.artworkGradient(seed: model.accessWasLost ? "Playlist" : displayTitle)
                .opacity(0.1)
                .ignoresSafeArea()
                .mask(
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        .navigationTitle(model.accessWasLost ? "Playlist Unavailable" : displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canEdit {
                    Button {
                        Task { await presentEditor() }
                    } label: {
                        if isPreparingEditor {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Refreshing playlist before editing")
                        } else {
                            Text("Edit")
                        }
                    }
                    .disabled(isPreparingEditor)
                }
                if copyModel.isCopying || isPreparingCopy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(
                            copyModel.isCopying
                                ? "Duplicating playlist"
                                : "Refreshing playlist before duplication"
                        )
                }
                if canCopy || actionURL != nil {
                    Menu {
                        if canCopy {
                            Button {
                                Task { await presentCopyConfirmation() }
                            } label: {
                                Label("Duplicate Playlist", systemImage: "square.on.square")
                            }
                            .disabled(
                                copyModel.isCopying
                                    || isPreparingCopy
                                    || copyModel.requiresReconciliation
                            )
                        }
                        if let url = actionURL {
                            Link(destination: url) {
                                Label("Open in ListenBrainz", systemImage: "arrow.up.right.square")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Playlist actions")
                }
            }
        }
        .sheet(isPresented: $showsEditor) {
            if let detail = model.detail {
                PlaylistMetadataEditorSheet(
                    account: viewer,
                    detail: detail,
                    editPreflight: { try await model.revalidateForEditing() },
                    provider: mutationProvider,
                    onIndeterminateResult: {
                        Task { await model.refresh() }
                    }
                ) { mutation in
                    guard case let .edited(draft) = mutation else { return }
                    mutationJournal.recordConfirmedEdit(
                        mbid: detail.mbid,
                        ownerUsername: viewer.username,
                        draft: draft
                    )
                    Task { await model.reconcileAfterConfirmedEdit(draft) }
                }
            }
        }
        .alert(
            "Duplicate Playlist?",
            isPresented: $showsCopyConfirmation
        ) {
            Button("Duplicate Playlist") {
                Task { await duplicatePlaylist() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(copyConfirmationMessage)
        }
        .alert(item: copyNoticeBinding) { notice in
            switch notice {
            case let .confirmed(copiedPlaylist):
                let visibility = copiedPlaylist.isPublic ? "public" : "private"
                return Alert(
                    title: Text("Playlist Duplicated"),
                    message: Text(
                        "“\(copiedPlaylist.title)” was created as a \(visibility) playlist and is now in Owned Playlists."
                    ),
                    primaryButton: .default(Text("Open Copy")) {
                        copyModel.acknowledgeConfirmedCopy()
                        copyDestination = copiedPlaylist
                    },
                    secondaryButton: .cancel(Text("Done")) {
                        copyModel.acknowledgeConfirmedCopy()
                    }
                )
            case let .failed(_, message):
                return Alert(
                    title: Text("Couldn’t Duplicate Playlist"),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) { copyModel.dismissNotice() }
                )
            case let .verificationNeeded(_, _, message):
                return Alert(
                    title: Text("Copy Needs Verification"),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) { copyModel.dismissNotice() }
                )
            }
        }
        .navigationDestination(item: $copyDestination) { copiedPlaylist in
            PlaylistDetailView(playlist: copiedPlaylist, viewer: viewer)
        }
        .task {
            await model.load()
            if automaticallyPresentsEditor, canEdit, !didAutomaticallyPresentEditor {
                didAutomaticallyPresentEditor = true
                await presentEditor()
            }
            if automaticallyPresentsCopyConfirmation,
               canCopy,
               !didAutomaticallyPresentCopyConfirmation {
                didAutomaticallyPresentCopyConfirmation = true
                await presentCopyConfirmation()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            PlaylistArtworkMosaic(
                tracks: model.detail?.tracks ?? [],
                title: displayTitle
            )
            .frame(maxWidth: 360)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
            .padding(.top, 12)

            VStack(spacing: 7) {
                Text(displayTitle)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                NavigationLink {
                    UserDetailView(
                        user: SearchUser(username: displayCreator),
                        viewer: viewer
                    )
                } label: {
                    Text("By \(displayCreator)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .multilineTextAlignment(.center)
                }

                if let detail = model.detail {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) { metrics(detail) }
                        VStack(alignment: .leading, spacing: 9) { metrics(detail) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        playlist.isPublic ? "Public playlist" : "Private playlist",
                        systemImage: playlist.isPublic ? "globe" : "lock.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var loadNotice: some View {
        switch model.phase {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading playlist tracks…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        case .refreshing:
            Label("Refreshing playlist…", systemImage: "arrow.clockwise")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case let .failed(message):
            retryNotice(message: message)
        case .ready:
            if let message = model.refreshMessage {
                retryNotice(message: message)
            }
        case .unavailable:
            EmptyView()
        }
    }

    @ViewBuilder
    private func metrics(_ detail: PlaylistDetail) -> some View {
        Label(
            "\(detail.tracks.count.formatted()) \(detail.tracks.count == 1 ? "track" : "tracks")",
            systemImage: "music.note.list"
        )
        .fixedSize(horizontal: true, vertical: false)
        if let duration = durationDescription(detail.totalDurationMilliseconds) {
            Label(duration, systemImage: "clock")
                .fixedSize(horizontal: true, vertical: false)
        }
        Label(
            detail.isPublic ? "Public" : "Private",
            systemImage: detail.isPublic ? "globe" : "lock.fill"
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func about(_ detail: PlaylistDetail) -> some View {
        if let annotation = detail.annotation {
            detailSection("About") {
                Text(annotation)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func playlistFacts(_ detail: PlaylistDetail) -> some View {
        detailSection("Playlist details") {
            VStack(alignment: .leading, spacing: 12) {
                if let created = detail.createdAt {
                    fact("Created", created.formatted(date: .abbreviated, time: .omitted))
                }
                if let updated = detail.lastModifiedAt {
                    fact("Updated", updated.formatted(date: .abbreviated, time: .shortened))
                }
                if let createdFor = detail.createdFor {
                    fact("Created for", createdFor)
                }
                if !detail.collaborators.isEmpty {
                    fact("Collaborators", detail.collaborators.joined(separator: ", "))
                }
            }
        }
    }

    private func tracks(_ detail: PlaylistDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Tracks",
                subtitle: detail.tracks.isEmpty
                    ? "This playlist is empty"
                    : "\(detail.tracks.count.formatted()) in playlist order"
            )

            if detail.tracks.isEmpty {
                ContentUnavailableView(
                    "No tracks yet",
                    systemImage: "music.note.list",
                    description: Text("Tracks added on ListenBrainz will appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(detail.tracks) { track in
                        if track.recording.identity.mbid != nil {
                            NavigationLink(value: track.recording) {
                                PlaylistTrackRow(track: track)
                            }
                            .buttonStyle(.plain)
                        } else {
                            PlaylistTrackRow(track: track)
                        }
                        if track.id != detail.tracks.last?.id {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var displayTitle: String {
        model.detail?.title ?? playlist.title
    }

    private var displayCreator: String {
        model.detail?.creator ?? playlist.creator
    }

    private var canEdit: Bool {
        guard viewer.isAuthenticated, let creator = model.detail?.creator else { return false }
        return creator.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(viewer.username.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private var canCopy: Bool {
        !model.accessWasLost && PlaylistCopyModel.canCopy(account: viewer, detail: model.detail)
    }

    private var actionURL: URL? {
        guard !model.accessWasLost else { return nil }
        return model.detail?.listenBrainzURL ?? playlist.listenBrainzURL
    }

    private var copyConfirmationMessage: String {
        "Copies current tracks, details, and privacy. You own it; no collaborators."
    }

    private var copyNoticeBinding: Binding<PlaylistCopyNotice?> {
        Binding(
            get: { copyModel.notice },
            set: { if $0 == nil { copyModel.dismissNotice() } }
        )
    }

    private var copyReconciliationNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Copy status needs review", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.headline)
            Text(copyReconciliationMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await reconcileCopy() }
            } label: {
                if copyModel.isReconciling {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking ListenBrainz…")
                    }
                } else {
                    Text("Check Again")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(copyModel.isReconciling)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var accessLostContent: some View {
        ContentUnavailableView {
            Label("Playlist Unavailable", systemImage: "lock.slash")
        } description: {
            Text("This playlist was removed or is no longer available to your account.")
        } actions: {
            Button("Try Again") { Task { await model.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func duplicatePlaylist() async {
        guard let detail = model.detail, canCopy else { return }
        await copyModel.copy(detail)
        await reconcileCopyOutcome()
    }

    private func reconcileCopy() async {
        await copyModel.reconcileAfterOwnedPlaylistsRefresh()
        await reconcileCopyOutcome()
    }

    private func reconcileCopyOutcome() async {
        if case let .confirmed(copiedPlaylist) = copyModel.notice {
            mutationJournal.recordConfirmedCopy(
                copiedPlaylist,
                ownerUsername: viewer.username
            )
        }
        guard let reason = copyModel.sourceAccessLossReason,
              let message = copyModel.sourceAccessMessage,
              let sourceMBID = playlist.playlistMBID
        else { return }
        await mutationJournal.recordAccessLoss(
            sourceMBID: sourceMBID,
            viewerUsername: viewer.username,
            reason: reason,
            message: message
        )
        await model.discardAfterAccessLoss(message: message)
    }

    private func presentCopyConfirmation() async {
        guard canCopy,
              !isPreparingCopy,
              !copyModel.isCopying,
              !copyModel.requiresReconciliation
        else { return }
        isPreparingCopy = true
        defer { isPreparingCopy = false }
        do {
            _ = try await model.revalidateForEditing()
            try Task.checkCancellation()
            showsCopyConfirmation = true
        } catch is CancellationError {
            return
        } catch {
            guard let reason = PlaylistAccessFailurePolicy.reason(for: error),
                  let sourceMBID = playlist.playlistMBID
            else { return }
            await mutationJournal.recordAccessLoss(
                sourceMBID: sourceMBID,
                viewerUsername: viewer.username,
                reason: reason,
                message: error.localizedDescription
            )
        }
    }

    private var copyReconciliationMessage: String {
        if copyModel.reconciliationRecord?.destinationMBID != nil {
            return "ListenBrainz created a copy, but its current details still need verification. Another copy is disabled until the returned playlist loads."
        }
        return "The copy response was lost. A fresh Owned Playlists check is required; another copy stays disabled unless a matching destination is verified."
    }

    private func presentEditor() async {
        guard canEdit, !isPreparingEditor else { return }
        isPreparingEditor = true
        defer { isPreparingEditor = false }
        do {
            _ = try await model.revalidateForEditing()
            try Task.checkCancellation()
            showsEditor = true
        } catch is CancellationError {
            return
        } catch {
            // The model already exposes the refresh failure beside the
            // playlist. Do not open an editor from unverified cached metadata.
            return
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func retryNotice(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Playlist unavailable", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try Again") { Task { await model.refresh() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func durationDescription(_ milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let totalMinutes = milliseconds / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }
}

#if DEBUG
struct PlaylistMutationVisualQAScreen: View {
    private let account = Account(username: "visual-listener", token: "visual-token")

    var body: some View {
        NavigationStack {
            PlaylistDetailView(
                playlist: Self.playlist,
                viewer: account,
                provider: VisualQAPlaylistDetailProvider(),
                mutationProvider: VisualQAPlaylistMutationProvider(),
                cache: EntityDetailCache(),
                automaticallyPresentsEditor: true
            )
        }
    }

    private static let playlistMBID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private static let playlist = SearchPlaylist(
        title: "Soft Focus — late-night favorites",
        creator: "visual-listener",
        annotation: "Dream pop, ambient edges, and songs that make the room feel quieter.",
        identifier: "https://listenbrainz.org/playlist/\(playlistMBID.uuidString)",
        isPublic: false,
        lastModifiedAt: Date(timeIntervalSince1970: 1_789_689_600),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationMilliseconds: 4_860_000,
        collaborators: ["cassetteclub", "softstatic"]
    )
}

struct PlaylistCopyVisualQAScreen: View {
    private let account = Account(username: "visual-listener", token: "visual-token")

    var body: some View {
        NavigationStack {
            PlaylistDetailView(
                playlist: Self.playlist,
                viewer: account,
                provider: VisualQACopyPlaylistDetailProvider(),
                copyProvider: VisualQAPlaylistCopyProvider(),
                cache: EntityDetailCache(),
                automaticallyPresentsCopyConfirmation: true
            )
        }
    }

    private static let playlistMBID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private static let playlist = SearchPlaylist(
        title: "Soft Focus — late-night favorites",
        creator: "cassetteclub",
        annotation: "Dream pop, ambient edges, and songs that make the room feel quieter.",
        identifier: "https://listenbrainz.org/playlist/\(playlistMBID.uuidString)",
        isPublic: true,
        lastModifiedAt: Date(timeIntervalSince1970: 1_789_689_600),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationMilliseconds: 4_860_000,
        collaborators: ["softstatic"]
    )
}

private struct VisualQAPlaylistDetailProvider: PlaylistDetailProviding {
    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        PlaylistDetail(
            mbid: mbid,
            title: "Soft Focus — late-night favorites",
            creator: "visual-listener",
            annotation: "Dream pop, ambient edges, and songs that make the room feel quieter.",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastModifiedAt: Date(timeIntervalSince1970: 1_789_689_600),
            isPublic: false,
            createdFor: nil,
            collaborators: ["cassetteclub", "softstatic"],
            copiedFrom: nil,
            tracks: []
        )
    }
}

private struct VisualQAPlaylistCopyProvider: PlaylistCopyProviding {
    func copy(mbid: UUID) async throws -> UUID {
        UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    }
}

private struct VisualQACopyPlaylistDetailProvider: PlaylistDetailProviding {
    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        PlaylistDetail(
            mbid: mbid,
            title: "Soft Focus — late-night favorites",
            creator: "cassetteclub",
            annotation: "Dream pop, ambient edges, and songs that make the room feel quieter.",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastModifiedAt: Date(timeIntervalSince1970: 1_789_689_600),
            isPublic: true,
            createdFor: nil,
            collaborators: ["softstatic"],
            copiedFrom: nil,
            tracks: []
        )
    }
}
#endif
