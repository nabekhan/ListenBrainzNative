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
        let provider: (any SearchProviding)? = if arguments.contains("-brainz-search-pagination-demo")
            || arguments.contains("-brainz-search-pagination-failure-demo")
        {
            VisualQASearchProvider(
                failsOnce: arguments.contains("-brainz-search-pagination-failure-demo")
            )
        } else {
            nil
        }
        #else
        let provider: (any SearchProviding)? = nil
        #endif
        let model = SearchModel(
            account: account,
            provider: provider,
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
            List {
                ForEach(model.results) { result in
                    NavigationLink(value: result) {
                        SearchResultRow(result: result)
                    }
                }
                paginationFooter
            }
            .listStyle(.plain)
            .accessibilityIdentifier("search-results-list")
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if model.isLoadingMore {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading more results…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        } else if let message = model.loadMoreError {
            VStack(spacing: 9) {
                Label("More results couldn’t load", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await model.loadMore() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityIdentifier("search-load-more-error")
        } else if model.canLoadMore {
            Button {
                Task { await model.loadMore() }
            } label: {
                Label("Load more results", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 8)
            .accessibilityIdentifier("search-load-more")
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

#if DEBUG
private actor VisualQASearchProvider: SearchProviding {
    enum FixtureError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            String(localized: "More results are temporarily unavailable.")
        }
    }

    private let failsOnce: Bool
    private var didFail = false

    init(failsOnce: Bool) {
        self.failsOnce = failsOnce
    }

    func search(query: String, scope: SearchScope) async throws -> [SearchResult] {
        try await searchPage(
            query: query,
            scope: scope,
            offset: 0,
            limit: SearchProvider.maximumPageSize
        ).results
    }

    func searchPage(
        query _: String,
        scope _: SearchScope,
        offset: Int,
        limit _: Int
    ) async throws -> SearchPage {
        if offset > 0, failsOnce, !didFail {
            didFail = true
            throw FixtureError.unavailable
        }

        if offset == 0 {
            return SearchPage(
                results: [
                    .playlist(.init(
                        title: "Night Walks",
                        creator: "sound-explorer",
                        annotation: "Quiet discoveries for an evening outside.",
                        identifier: "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                        isPublic: true,
                        lastModifiedAt: nil
                    )),
                    .playlist(.init(
                        title: "Deep Focus",
                        creator: "headphones-on",
                        annotation: "Instrumental music for unbroken concentration.",
                        identifier: "https://listenbrainz.org/playlist/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                        isPublic: true,
                        lastModifiedAt: nil
                    )),
                ],
                offset: 0,
                rawResultCount: 2,
                totalResultCount: 4,
                allowsPagination: true
            )
        }

        return SearchPage(
            results: [
                .playlist(.init(
                    title: "Deep Focus",
                    creator: "headphones-on",
                    annotation: "Instrumental music for unbroken concentration.",
                    identifier: "https://listenbrainz.org/playlist/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                    isPublic: true,
                    lastModifiedAt: nil
                )),
                .playlist(.init(
                    title: "Late Night Coding",
                    creator: "syntax-and-sound",
                    annotation: "A patient pulse for one more thoughtful commit.",
                    identifier: "https://listenbrainz.org/playlist/cccccccc-cccc-cccc-cccc-cccccccccccc",
                    isPublic: true,
                    lastModifiedAt: nil
                )),
            ],
            offset: offset,
            rawResultCount: 2,
            totalResultCount: 4,
            allowsPagination: true
        )
    }
}
#endif

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
