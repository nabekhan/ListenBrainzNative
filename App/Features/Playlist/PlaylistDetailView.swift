import SwiftUI

struct PlaylistDetailView: View {
    let playlist: SearchPlaylist
    let viewer: Account
    @State private var model: PlaylistDetailModel

    init(playlist: SearchPlaylist, viewer: Account) {
        self.playlist = playlist
        self.viewer = viewer
        _model = State(initialValue: PlaylistDetailModel(seed: playlist, token: viewer.token))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                hero
                loadNotice
                if let detail = model.detail {
                    about(detail)
                    playlistFacts(detail)
                    tracks(detail)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
        }
        .refreshable { await model.refresh() }
        .background {
            AppTheme.artworkGradient(seed: displayTitle)
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
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = model.detail?.listenBrainzURL ?? playlist.listenBrainzURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open playlist in ListenBrainz")
                }
            }
        }
        .task { await model.load() }
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
