import SwiftUI

struct PlaylistDetailView: View {
    let playlist: SearchPlaylist
    let viewer: Account
    private let mutationProvider: any PlaylistMutationProviding
    private let mutationJournal: PlaylistMutationJournal
    private let automaticallyPresentsEditor: Bool
    private let automaticallyPresentsCopyConfirmation: Bool
    private let automaticallyPresentsRemovalConfirmation: Bool
    @State private var model: PlaylistDetailModel
    @State private var copyModel: PlaylistCopyModel
    @State private var removalModel: PlaylistItemRemovalModel
    @State private var showsEditor = false
    @State private var showsCopyConfirmation = false
    @State private var copyDestination: SearchPlaylist?
    @State private var didAutomaticallyPresentEditor = false
    @State private var didAutomaticallyPresentCopyConfirmation = false
    @State private var didAutomaticallyPresentRemovalConfirmation = false
    @State private var isPreparingEditor = false
    @State private var isPreparingCopy = false
    @State private var trackPendingRemoval: PlaylistTrack?
    @State private var showsRemovalConfirmation = false
    @State private var showsSafetyResetConfirmation = false
    @State private var showsArtwork = false

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
        removalProvider: (any PlaylistItemRemovalProviding)? = nil,
        removalJournal: PlaylistItemRemovalJournal = .shared,
        automaticallyPresentsEditor: Bool = false,
        automaticallyPresentsCopyConfirmation: Bool = false,
        automaticallyPresentsRemovalConfirmation: Bool = false
    ) {
        self.playlist = playlist
        self.viewer = viewer
        self.mutationProvider = mutationProvider
            ?? ListenBrainzPlaylistMutationProvider(token: viewer.token)
        self.mutationJournal = mutationJournal
        self.automaticallyPresentsEditor = automaticallyPresentsEditor
        self.automaticallyPresentsCopyConfirmation = automaticallyPresentsCopyConfirmation
        self.automaticallyPresentsRemovalConfirmation = automaticallyPresentsRemovalConfirmation
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
        _removalModel = State(initialValue: PlaylistItemRemovalModel(
            account: viewer,
            detailProvider: resolvedDetailProvider,
            provider: removalProvider ?? ListenBrainzPlaylistItemRemovalProvider(token: viewer.token),
            journal: removalJournal,
            mutationJournal: mutationJournal
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
                    if let detail = model.detail, removalModel.requiresReview(playlistMBID: detail.mbid) {
                        removalReviewNotice(detail)
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
        .sheet(isPresented: $showsArtwork) {
            if let detail = model.detail,
               let request = playlistArtworkRequest(
                   mbid: detail.mbid,
                   trackCount: detail.tracks.count
               ) {
                GeneratedArtworkSheet(
                    presentation: .playlist(
                        title: detail.title,
                        mbid: detail.mbid,
                        sourceURL: detail.listenBrainzURL
                    ),
                    request: request,
                    provider: ListenBrainzGeneratedArtworkProvider(
                        token: viewer.token
                    )
                )
            }
        }
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
                if canCopy || canCreateArtwork || actionURL != nil {
                    Menu {
                        if canCreateArtwork {
                            Button {
                                showsArtwork = true
                            } label: {
                                Label("Create artwork", systemImage: "photo.badge.plus")
                            }
                        }
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
        .confirmationDialog(
            removalConfirmationTitle,
            isPresented: $showsRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Track", role: .destructive) { Task { await removeSelectedTrack() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(removalConfirmationMessage) }
        .alert(item: removalNoticeBinding) { notice in
            switch notice {
            case .stale:
                Alert(title: Text("Playlist Changed"), message: Text("The track order changed before anything was removed. Review the refreshed playlist and try again."), dismissButton: .default(Text("OK")))
            case let .confirmed(track, playlist):
                Alert(title: Text("Track Removed"), message: Text("“\(track)” was removed from “\(playlist)”."), dismissButton: .default(Text("OK")))
            case let .needsReview(message):
                Alert(title: Text("Removal Needs Review"), message: Text(message), dismissButton: .default(Text("OK")))
            case .refreshed:
                Alert(title: Text("Playlist Refreshed"), message: Text("Review the current track order before removing another track."), dismissButton: .default(Text("OK")))
            case let .accessLost(message):
                Alert(title: Text("Playlist Unavailable"), message: Text(message), dismissButton: .default(Text("OK")))
            case let .failed(message):
                Alert(title: Text("Couldn’t Remove Track"), message: Text(message), dismissButton: .default(Text("OK")))
            }
        }
        .confirmationDialog("Reset the Safety Record?", isPresented: $showsSafetyResetConfirmation, titleVisibility: .visible) {
            Button("Reset Record", role: .destructive) { if let detail = model.detail { _ = removalModel.resetSafetyRecord(playlistMBID: detail.mbid) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only reset it after reviewing the current track order. This affects this playlist and account only.") }
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
            if automaticallyPresentsRemovalConfirmation,
               canRemove,
               !didAutomaticallyPresentRemovalConfirmation,
               let firstTrack = model.detail?.tracks.first {
                didAutomaticallyPresentRemovalConfirmation = true
                trackPendingRemoval = firstTrack
                showsRemovalConfirmation = true
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
                            .contextMenu { removalAction(track, detail: detail) }
                        } else {
                            PlaylistTrackRow(track: track)
                                .contextMenu { removalAction(track, detail: detail) }
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

    private var canRemove: Bool {
        !model.accessWasLost && removalModel.canAttemptRemoval(from: model.detail)
    }

    @ViewBuilder private func removalAction(_ track: PlaylistTrack, detail: PlaylistDetail) -> some View {
        if canRemove {
            Button(role: .destructive) {
                trackPendingRemoval = track; showsRemovalConfirmation = true
            } label: { Label("Remove from Playlist", systemImage: "minus.circle") }
            .disabled(removalModel.isRemoving || removalModel.isReconciling || removalModel.requiresReview(playlistMBID: detail.mbid))
        }
    }

    private func removalReviewNotice(_ detail: PlaylistDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(removalModel.requiresRecovery(playlistMBID: detail.mbid) ? "Removal Paused" : "Removal Needs Review", systemImage: "exclamationmark.arrow.triangle.2.circlepath").font(.headline)
            Text(removalModel.requiresRecovery(playlistMBID: detail.mbid) ? "Brainz can’t read this playlist’s removal safety record. Refresh and review the playlist before resetting the record." : "A previous removal may have reached ListenBrainz. Refresh the playlist before removing another track.").font(.subheadline).foregroundStyle(.secondary)
            Button("Refresh and Review") { Task { if let canonical = await removalModel.refreshAfterReview(playlistMBID: detail.mbid) { await model.applyCanonicalDetail(canonical) } else { await discardRemovalAccessIfNeeded() } } }
                .buttonStyle(.bordered).controlSize(.small).disabled(removalModel.isReconciling)
            if removalModel.canResetSafetyRecord(playlistMBID: detail.mbid) { Button("Reset Safety Record", role: .destructive) { showsSafetyResetConfirmation = true }.buttonStyle(.bordered).controlSize(.small) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.orange.opacity(0.12), in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var removalConfirmationTitle: String { "Remove “\(trackPendingRemoval?.recording.title ?? "")”?" }
    private var removalConfirmationMessage: String { "This removes one track from “\(displayTitle)” for everyone who uses it." }
    private var removalNoticeBinding: Binding<PlaylistItemRemovalNotice?> { Binding(get: { removalModel.notice }, set: { if $0 == nil { removalModel.dismissNotice() } }) }
    private func removeSelectedTrack() async {
        guard let track = trackPendingRemoval, let detail = model.detail else { return }
        if let canonical = await removalModel.remove(track, from: detail) { await model.applyCanonicalDetail(canonical) }
        else { await discardRemovalAccessIfNeeded() }
        trackPendingRemoval = nil
    }

    private func discardRemovalAccessIfNeeded() async {
        guard case let .accessLost(message) = removalModel.notice else { return }
        await model.discardAfterAccessLoss(message: message)
    }

    private var actionURL: URL? {
        guard !model.accessWasLost else { return nil }
        return model.detail?.listenBrainzURL ?? playlist.listenBrainzURL
    }

    private var canCreateArtwork: Bool {
        viewer.isAuthenticated && model.detail?.tracks.isEmpty == false
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

struct PlaylistRemovalVisualQAScreen: View {
    private let account = Account(username: "visual-listener", token: "visual-token")
    private let showsReview: Bool
    @State private var journal: PlaylistItemRemovalJournal

    init(showsReview: Bool) {
        self.showsReview = showsReview
        let journal = PlaylistItemRemovalJournal()
        if showsReview {
            _ = journal.begin(
                username: "visual-listener",
                playlistMBID: Self.playlistMBID
            )
        }
        _journal = State(initialValue: journal)
    }

    var body: some View {
        NavigationStack {
            PlaylistDetailView(
                playlist: Self.playlist,
                viewer: account,
                provider: VisualQAPlaylistRemovalDetailProvider(),
                removalProvider: VisualQAPlaylistRemovalProvider(),
                removalJournal: journal,
                automaticallyPresentsRemovalConfirmation: !showsReview
            )
        }
    }

    private static let playlistMBID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private static let playlist = SearchPlaylist(
        title: "Soft Focus — late-night favorites",
        creator: "visual-listener",
        annotation: "Dream pop, ambient edges, and songs that make the room feel quieter.",
        identifier: "https://listenbrainz.org/playlist/\(playlistMBID.uuidString)",
        isPublic: false,
        lastModifiedAt: Date(timeIntervalSince1970: 1_789_689_600),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationMilliseconds: 694_000,
        collaborators: ["cassetteclub", "softstatic"]
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

private struct VisualQAPlaylistRemovalDetailProvider: PlaylistDetailProviding {
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
            tracks: [
                track(1, "Myth", "Beach House", "Bloom", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
                track(2, "Cherry-coloured Funk", "Cocteau Twins", "Heaven or Las Vegas", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
                track(3, "An Ending (Ascent)", "Brian Eno", "Apollo", "cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
            ]
        )
    }

    private func track(
        _ position: Int,
        _ title: String,
        _ artist: String,
        _ release: String,
        _ mbid: String
    ) -> PlaylistTrack {
        PlaylistTrack(
            position: position,
            recording: Recording(
                identity: .init(mbid: UUID(uuidString: mbid), msid: nil),
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: release,
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

private struct VisualQAPlaylistRemovalProvider: PlaylistItemRemovalProviding {
    func removeItem(at index: Int, from playlistMBID: UUID) async throws {}
}
#endif
