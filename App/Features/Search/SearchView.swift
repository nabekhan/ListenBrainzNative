import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SearchModel
    @State private var path: [SearchResult] = []
    @State private var didOpenDebugResult = false
    @Bindable var listeningModel: ListeningModel

    init(account: Account, listeningModel: ListeningModel) {
        var initialQuery = ""
        var initialScope: SearchScope = .artists
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-brainz-search-scope"),
           arguments.indices.contains(flag + 1),
           let scope = SearchScope(rawValue: arguments[flag + 1]) {
            initialScope = scope
        }
        if let flag = arguments.firstIndex(of: "-brainz-search-query"),
           arguments.indices.contains(flag + 1) {
            initialQuery = arguments[flag + 1]
        }
        #endif
        let model = SearchModel(
            account: account,
            initialQuery: initialQuery,
            initialScope: initialScope
        )
        _model = State(initialValue: model)
        _listeningModel = Bindable(wrappedValue: listeningModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search your music world",
                        systemImage: "magnifyingglass",
                        description: Text("Find ListenBrainz users and playlists, or explore MusicBrainz artists, albums, and tracks.")
                    )
                } else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).count < model.scope.minimumQueryLength {
                    ContentUnavailableView(
                        "Keep typing",
                        systemImage: "text.magnifyingglass",
                        description: Text("Playlist search needs at least three characters.")
                    )
                } else {
                    results
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: Binding(get: { model.query }, set: { model.update(query: $0) }),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Artists, tracks, people, playlists"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Search category", selection: Binding(get: { model.scope }, set: { model.update(scope: $0) })) {
                        ForEach(SearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Search category")
                }
            }
            .navigationDestination(for: SearchResult.self) { result in
                destination(for: result)
            }
            .mediaDestinations(model: listeningModel)
            .task { model.startInitialSearchIfNeeded() }
            .onChange(of: model.state) { _, state in
                #if DEBUG
                guard state == .loaded,
                      !didOpenDebugResult,
                      ProcessInfo.processInfo.arguments.contains("-brainz-open-user-detail"),
                      let result = model.results.first(where: {
                          if case .user = $0 { return true }
                          return false
                      })
                else { return }
                didOpenDebugResult = true
                path.append(result)
                #endif
            }
            .onDisappear { model.cancel() }
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .waiting, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(model.state == .waiting ? "Waiting to search…" : "Searching…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded where model.results.isEmpty:
            ContentUnavailableView(
                "No results",
                systemImage: "music.note.list",
                description: Text("Try another name or category.")
            )
        case let .failed(message):
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.retry() } }
            }
        case .loaded:
            List(model.results) { result in
                NavigationLink(value: result) {
                    SearchResultRow(result: result)
                }
            }
            .listStyle(.plain)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func destination(for result: SearchResult) -> some View {
        switch result {
        case let .artist(artist):
            ArtistDetailView(artist: artist, model: listeningModel)
        case let .recording(recording):
            RecordingDetailView(recording: recording, model: listeningModel)
        case let .releaseGroup(group):
            SearchReleaseGroupDetailView(group: group)
        case let .user(user):
            UserDetailView(user: user, viewer: listeningModel.account)
        case let .playlist(playlist):
            SearchPlaylistDetailView(playlist: playlist)
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch result {
        case .user: "person.crop.circle"
        case .artist: "music.mic"
        case .releaseGroup: "square.stack"
        case .recording: "music.note"
        case .playlist: "music.note.list"
        }
    }
}

private struct SearchReleaseGroupDetailView: View {
    let group: SearchReleaseGroup

    var body: some View {
        SearchCompactDetail(title: group.title, subtitle: group.artistName, systemImage: "square.stack") {
            if let date = group.firstReleaseDate { detail("First released", date) }
            if let type = group.primaryType { detail("Type", type) }
            Link(destination: group.musicBrainzURL) {
                Label("Open release group in MusicBrainz", systemImage: "arrow.up.right.square")
            }
        }
    }
}

private struct SearchPlaylistDetailView: View {
    let playlist: SearchPlaylist

    var body: some View {
        SearchCompactDetail(title: playlist.title, subtitle: "By \(playlist.creator)", systemImage: "music.note.list") {
            if let annotation = playlist.annotation, !annotation.isEmpty { detail("About", annotation) }
            detail("Visibility", playlist.isPublic ? "Public" : "Private")
            if let lastModifiedAt = playlist.lastModifiedAt {
                detail("Updated", lastModifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let url = playlist.listenBrainzURL {
                Link(destination: url) {
                    Label("Open playlist in ListenBrainz", systemImage: "arrow.up.right.square")
                }
            }
        }
    }
}

private struct SearchCompactDetail<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 54))
                        .foregroundStyle(AppTheme.accent)
                    Text(title).font(.title.bold()).multilineTextAlignment(.center)
                    Text(subtitle).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            }
            .padding(20)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.body)
    }
}
