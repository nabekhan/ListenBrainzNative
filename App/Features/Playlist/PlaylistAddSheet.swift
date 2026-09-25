// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// The destination-sheet and duplicate-decision interaction is adapted from
// Minidisc's AddToPlaylistSheet, AddToPlaylistViewModel, and
// PlaylistAppendIntent at commit 2072435702909a8ac313d7871ed7cf114a8e1012.

import Observation
import SwiftUI

@MainActor
@Observable
final class PlaylistAddSheetModel {
    let account: Account
    let recordingMBID: UUID
    let playlists: ProfilePlaylistsModel
    private let detailProvider: any PlaylistDetailProviding
    private let appendProvider: any PlaylistAppendProviding
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>

    private(set) var activePlaylistMBID: UUID?
    private(set) var message: String?
    private(set) var didBecomeIndeterminate = false
    private(set) var didComplete = false
    var pendingDuplicate: SearchPlaylist?

    init(
        account: Account,
        recordingMBID: UUID,
        playlists: ProfilePlaylistsModel? = nil,
        detailProvider: (any PlaylistDetailProviding)? = nil,
        appendProvider: (any PlaylistAppendProviding)? = nil,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists
    ) {
        self.account = account
        self.recordingMBID = recordingMBID
        self.playlists = playlists ?? ProfilePlaylistsModel(account: account)
        self.detailProvider = detailProvider ?? ListenBrainzMediaDetailProvider(token: account.token)
        self.appendProvider = appendProvider ?? ListenBrainzPlaylistAppendProvider(token: account.token)
        self.detailCache = detailCache
    }

    func load() async {
        async let owned: Void = playlists.load(category: .owned)
        async let collaborating: Void = playlists.load(category: .collaborating)
        _ = await (owned, collaborating)
    }

    func refresh() async {
        async let owned: Void = playlists.refresh(category: .owned)
        async let collaborating: Void = playlists.refresh(category: .collaborating)
        _ = await (owned, collaborating)
    }

    func dismissMessage() { message = nil }

    var isSubmitting: Bool { activePlaylistMBID != nil }

    static func canPresent(account: Account, recordingMBID: UUID?) -> Bool {
        account.isAuthenticated && recordingMBID != nil
    }

    func isWorking(on destination: SearchPlaylist) -> Bool {
        destination.playlistMBID == activePlaylistMBID
    }

    func select(_ destination: SearchPlaylist) async {
        guard activePlaylistMBID == nil, !didBecomeIndeterminate, !didComplete,
              let playlistMBID = destination.playlistMBID else { return }
        activePlaylistMBID = playlistMBID
        message = nil
        defer { activePlaylistMBID = nil }
        do {
            let detail = try await detailProvider.playlist(mbid: playlistMBID)
            try Task.checkCancellation()
            // ListenBrainz has no conditional append or playlist version. This
            // catches existing duplicates but cannot close an external
            // collaborator race between this read and the later POST.
            let baseline = occurrenceCount(in: detail)
            if baseline > 0 {
                pendingDuplicate = destination
            } else {
                await append(to: playlistMBID, baseline: baseline)
            }
        } catch is CancellationError {
            // Dismissing the sheet while the read-only preflight is pending is
            // an ordinary cancellation and does not need user-facing noise.
        } catch {
            await discardAccessSensitiveStateIfNeeded(error)
            message = error.localizedDescription
        }
    }

    func appendAnotherCopy() async {
        guard let destination = pendingDuplicate,
              let playlistMBID = destination.playlistMBID,
              activePlaylistMBID == nil,
              !didBecomeIndeterminate,
              !didComplete
        else { return }
        pendingDuplicate = nil
        activePlaylistMBID = playlistMBID
        message = nil
        defer { activePlaylistMBID = nil }
        do {
            // The confirmation can stay open indefinitely. Revalidate the
            // occurrence baseline immediately before POST so a collaborator's
            // intervening addition is not mistaken for ours during recovery.
            let detail = try await detailProvider.playlist(mbid: playlistMBID)
            try Task.checkCancellation()
            await append(to: playlistMBID, baseline: occurrenceCount(in: detail))
        } catch is CancellationError {
            return
        } catch {
            await discardAccessSensitiveStateIfNeeded(error)
            message = error.localizedDescription
        }
    }

    private func append(to playlistMBID: UUID, baseline: Int) async {
        do {
            try await appendProvider.append(recordingMBID: recordingMBID, to: playlistMBID)
            await reconcile(playlistMBID: playlistMBID, baseline: baseline, indeterminate: false)
        } catch is CancellationError {
            // Before RequestGate admits the mutation, cancellation proves no
            // transport began. Leave the sheet usable.
        } catch {
            if let error = error as? PlaylistMutationProviderError, error.isIndeterminate {
                await reconcile(playlistMBID: playlistMBID, baseline: baseline, indeterminate: true)
            } else {
                await discardAccessSensitiveStateIfNeeded(error)
                message = error.localizedDescription
            }
        }
    }

    private func reconcile(playlistMBID: UUID, baseline: Int, indeterminate: Bool) async {
        do {
            let detail = try await detailProvider.playlist(mbid: playlistMBID)
            if occurrenceCount(in: detail) > baseline {
                if indeterminate {
                    // An occurrence increase proves only that the recording is
                    // present. A collaborator may have added it while our POST
                    // response was lost, so never attribute ambiguous work to
                    // this client or enable a replay.
                    didBecomeIndeterminate = true
                    message = String(localized: "The recording is in the playlist now, but ListenBrainz did not confirm whether this add completed. Inspect the playlist before trying again.")
                } else {
                    didComplete = true
                    message = String(localized: "Added to \(detail.title).")
                }
            } else if indeterminate {
                didBecomeIndeterminate = true
                message = String(localized: "ListenBrainz did not confirm this add. Inspect the playlist before trying again.")
            } else {
                didBecomeIndeterminate = true
                message = String(localized: "ListenBrainz accepted the request but the playlist did not update yet. Inspect it before trying again.")
            }
        } catch {
            didBecomeIndeterminate = true
            await discardAccessSensitiveStateIfNeeded(error)
            message = PlaylistAccessFailurePolicy.requiresPurge(error)
                ? error.localizedDescription
                : String(localized: "Couldn’t verify this add. Inspect the playlist before trying again.")
        }
    }

    private func occurrenceCount(in detail: PlaylistDetail) -> Int {
        detail.tracks.reduce(into: 0) { count, track in
            if track.recording.identity.mbid == recordingMBID { count += 1 }
        }
    }

    private func discardAccessSensitiveStateIfNeeded(_ error: any Error) async {
        guard PlaylistAccessFailurePolicy.requiresPurge(error) else { return }
        pendingDuplicate = nil
        await detailCache.removeAll()
        await playlists.discardAccessSensitiveState(message: error.localizedDescription)
    }
}

struct PlaylistAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaylistAddSheetModel
    @State private var searchText = ""

    init(
        account: Account,
        recordingMBID: UUID,
        playlists: ProfilePlaylistsModel? = nil,
        detailProvider: (any PlaylistDetailProviding)? = nil,
        appendProvider: (any PlaylistAppendProviding)? = nil
    ) {
        _model = State(initialValue: PlaylistAddSheetModel(
            account: account,
            recordingMBID: recordingMBID,
            playlists: playlists,
            detailProvider: detailProvider,
            appendProvider: appendProvider
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                category(.owned, title: "Your Playlists")
                category(.collaborating, title: "Collaborating")
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Find a playlist")
            .refreshable { await model.refresh() }
            .overlay(alignment: .center) {
                if isCompletelyLoading { ProgressView("Loading playlists…") }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(model.isSubmitting)
                }
            }
            .alert(model.didComplete ? "Added to Playlist" : "Playlist Update", isPresented: Binding(
                get: { model.message != nil }, set: { if !$0 { model.dismissMessage() } }
            )) {
                Button(model.didComplete ? "Done" : "OK") {
                    model.dismissMessage()
                    if model.didComplete { dismiss() }
                }
            } message: { Text(model.message ?? "") }
        }
        .interactiveDismissDisabled(model.isSubmitting)
        .task { await model.load() }
        .confirmationDialog("Already in Playlist", isPresented: Binding(
            get: { model.pendingDuplicate != nil }, set: { if !$0 { model.pendingDuplicate = nil } }
        ), titleVisibility: .visible) {
            Button("Add Another Copy") { Task { await model.appendAnotherCopy() } }
            Button("Cancel", role: .cancel) { model.pendingDuplicate = nil }
        } message: {
            Text("This recording is already in this playlist. ListenBrainz allows copies, but this adds another occurrence.")
        }
    }

    @ViewBuilder
    private func category(_ category: ProfilePlaylistCategory, title: LocalizedStringResource) -> some View {
        let state = model.playlists.state(for: category)
        let filtered = state.playlists.filter(matchesSearch)
        Section(title) {
            if case let .failed(message) = state.phase, state.playlists.isEmpty {
                ContentUnavailableView("Couldn’t load playlists", systemImage: "exclamationmark.triangle", description: Text(message))
                Button("Try Again") { Task { await model.playlists.refresh(category: category) } }
            } else if !filtered.isEmpty {
                ForEach(filtered) { playlist in
                    Button { Task { await model.select(playlist) } } label: {
                        HStack(spacing: 12) {
                            ArtworkView(url: nil, title: playlist.title, cornerRadius: 10)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.title).font(.body.weight(.semibold)).lineLimit(2)
                                Text(playlist.annotation ?? playlist.creator)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if model.isWorking(on: playlist) { ProgressView() }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting || model.didBecomeIndeterminate || playlist.playlistMBID == nil)
                }
            } else if state.phase == .ready {
                Text(searchText.isEmpty ? "No playlists here yet." : "No matching playlists.")
                    .foregroundStyle(.secondary)
            }
            if state.hasMore || state.loadMoreError != nil {
                Button(state.isLoadingMore ? "Loading…" : state.loadMoreError == nil ? "Load More" : "Try Again") {
                    Task { await model.playlists.loadMore(category: category) }
                }
                .disabled(state.isLoadingMore || model.isSubmitting)
            }
            if let refreshMessage = state.refreshMessage {
                Text(refreshMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func matchesSearch(_ playlist: SearchPlaylist) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return playlist.title.localizedCaseInsensitiveContains(query)
            || playlist.creator.localizedCaseInsensitiveContains(query)
            || (playlist.annotation?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private var isCompletelyLoading: Bool {
        ProfilePlaylistCategory.allCases.allSatisfy {
            let phase = model.playlists.state(for: $0).phase
            return phase == .idle || phase == .loading
        }
    }
}

#if DEBUG
struct PlaylistAddVisualQAScreen: View {
    private let account = Account(username: "visual-listener", token: "visual-token")
    private let recordingMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    var body: some View {
        PlaylistAddSheet(
            account: account,
            recordingMBID: recordingMBID,
            playlists: ProfilePlaylistsModel(
                account: account,
                provider: PlaylistAddVisualProvider(),
                cache: EntityDetailCache()
            ),
            detailProvider: PlaylistAddVisualDetailProvider(recordingMBID: recordingMBID),
            appendProvider: PlaylistAddVisualAppendProvider()
        )
    }
}

private struct PlaylistAddVisualProvider: ProfilePlaylistsProviding {
    func page(username: String, category: ProfilePlaylistCategory, offset: Int, count: Int) async throws -> ProfilePlaylistPage {
        let rows = category == .owned ? [row("After Hours", "11111111-1111-4111-8111-111111111111"), row("Sunday Records", "22222222-2222-4222-8222-222222222222")] : [row("Road Trip", "33333333-3333-4333-8333-333333333333", creator: "mira")]
        return .init(username: username, category: category, playlists: rows, requestedCount: count, offset: offset, totalCount: rows.count)
    }

    private func row(_ title: String, _ id: String, creator: String = "visual-listener") -> SearchPlaylist {
        .init(title: title, creator: creator, annotation: "A carefully kept mix", identifier: "https://listenbrainz.org/playlist/\(id)", isPublic: true, lastModifiedAt: nil, createdAt: nil, durationMilliseconds: nil, collaborators: creator == "visual-listener" ? [] : ["visual-listener"])
    }
}

private struct PlaylistAddVisualDetailProvider: PlaylistDetailProviding {
    let recordingMBID: UUID
    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        .init(mbid: mbid, title: "After Hours", creator: "visual-listener", annotation: "A carefully kept mix", createdAt: nil, lastModifiedAt: nil, isPublic: true, createdFor: nil, collaborators: [], copiedFrom: nil, tracks: [])
    }
}

private struct PlaylistAddVisualAppendProvider: PlaylistAppendProviding {
    func append(recordingMBID: UUID, to playlistMBID: UUID) async throws {}
}
#endif
