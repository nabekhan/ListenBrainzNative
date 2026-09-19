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
                      let result = debugResultToOpen
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
            ReleaseGroupDetailView(group: group, viewer: listeningModel.account)
        case let .user(user):
            UserDetailView(user: user, viewer: listeningModel.account)
        case let .playlist(playlist):
            PlaylistDetailView(playlist: playlist, viewer: listeningModel.account)
        }
    }

    #if DEBUG
    private var debugResultToOpen: SearchResult? {
        let arguments = ProcessInfo.processInfo.arguments
        return model.results.first { result in
            switch result {
            case .user:
                arguments.contains("-brainz-open-user-detail")
            case .releaseGroup:
                arguments.contains("-brainz-open-release-detail")
            case .playlist:
                arguments.contains("-brainz-open-playlist-detail")
            default:
                false
            }
        }
    }
    #endif
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
