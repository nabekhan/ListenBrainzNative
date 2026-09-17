import SwiftUI

struct DiscoverView: View {
    @State private var model: FreshReleasesModel
    @State private var isSearchPresented = false
    @Bindable var listeningModel: ListeningModel
    private let account: Account
    @AppStorage("discover.freshReleaseScope") private var scope: FreshReleaseScope = .forYou

    init(account: Account, listeningModel: ListeningModel) {
        self.account = account
        _model = State(initialValue: FreshReleasesModel(account: account))
        _listeningModel = Bindable(wrappedValue: listeningModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    scopePicker
                    content
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isSearchPresented = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search ListenBrainz and MusicBrainz")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.refresh(scope: scope) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh fresh releases")
                    .disabled(model.isLoading(scope: scope))
                }
            }
            .task(id: scope) { await model.load(scope: scope) }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-search") {
                    isSearchPresented = true
                }
                #endif
            }
            .sheet(isPresented: $isSearchPresented) {
                SearchView(account: account, listeningModel: listeningModel)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scope == .forYou ? "Fresh for you" : "New across ListenBrainz")
                .font(.title2.bold())
            Text(scope == .forYou
                ? "Recent releases selected from your listening world."
                : "A wider view of recent releases being explored by listeners.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopePicker: some View {
        Picker("Release source", selection: $scope) {
            ForEach(FreshReleaseScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("For You is personalized. All loads sitewide releases only when selected.")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state(for: scope) {
        case .idle, .loading:
            loading
        case let .loaded(releases):
            if releases.isEmpty {
                empty
            } else {
                releaseGrid(releases)
            }
        case let .failed(message):
            failure(message)
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding fresh releases…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        ContentUnavailableView(
            scope == .forYou ? "Nothing fresh for you yet" : "No fresh releases right now",
            systemImage: "sparkles",
            description: Text(scope == .forYou
                ? "No personalized releases today. Select All to explore the wider catalogue."
                : "Try refreshing in a little while.")
        )
        .frame(maxWidth: .infinity, minHeight: 290)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Fresh Releases unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await model.load(scope: scope, retrying: true) } }
        }
        .frame(maxWidth: .infinity, minHeight: 290)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func releaseGrid(_ releases: [FreshRelease]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148), spacing: 16)],
            spacing: 22
        ) {
            ForEach(releases) { release in
                NavigationLink {
                    FreshReleaseDetailView(release: release)
                } label: {
                    FreshReleaseCard(release: release)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FreshReleaseCard: View {
    let release: FreshRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ArtworkView(url: release.artworkURL, title: release.title, cornerRadius: 16, showsPlaceholderSymbol: false)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if release.isUpcoming {
                        Label("Upcoming", systemImage: "hourglass")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: .capsule)
                            .padding(8)
                    }
                }
            Text(release.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(release.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            metadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open release details")
    }

    @ViewBuilder private var metadata: some View {
        let values = [release.releaseDateDescription, release.typeDescription].compactMap { $0 }
        if !values.isEmpty {
            Text(values.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

private struct FreshReleaseDetailView: View {
    let release: FreshRelease

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ArtworkView(url: release.artworkURL, title: release.title, cornerRadius: 24, showsPlaceholderSymbol: false)
                    .frame(maxWidth: 430)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 7) {
                    Text(release.title)
                        .font(.title.bold())
                    Text(release.artistName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if let date = release.releaseDateDescription {
                        Label(date, systemImage: release.isUpcoming ? "hourglass" : "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let type = release.typeDescription {
                    detailSection("Release type") { Text(type) }
                }
                if let count = release.listenCount {
                    detailSection("ListenBrainz context") { Text("\(count.formatted()) listener \(count == 1 ? "listen" : "listens")") }
                }
                if !release.tags.isEmpty {
                    detailSection("Tags") {
                        FlowTags(tags: release.tags.prefix(8).map { $0 })
                    }
                }
                if release.releaseMusicBrainzURL != nil || release.releaseGroupMusicBrainzURL != nil {
                    detailSection("MusicBrainz identity") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let releaseURL = release.releaseMusicBrainzURL {
                                Link(destination: releaseURL) {
                                    Label("Open release", systemImage: "arrow.up.right.square")
                                }
                            }
                            if let releaseGroupURL = release.releaseGroupMusicBrainzURL {
                                Link(destination: releaseGroupURL) {
                                    Label("Open release group", systemImage: "square.stack.3d.up")
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        Text(tags.joined(separator: " · "))
            .foregroundStyle(.primary)
    }
}
