import SwiftUI

struct DiscoverView: View {
    @State private var model: FreshReleasesModel
    @State private var isSearchPresented = false
    @State private var isRecommendationsPresented = false
    @State private var isFeedPresented = false
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
                    recommendationsLink
                    radioLink
                    feedLink
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
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-recommendations") {
                    isRecommendationsPresented = true
                }
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-feed") {
                    isFeedPresented = true
                }
                #endif
            }
            .sheet(isPresented: $isSearchPresented) {
                SearchView(account: account, listeningModel: listeningModel)
            }
            .navigationDestination(isPresented: $isRecommendationsPresented) {
                RecommendationsView(account: account, listeningModel: listeningModel)
            }
            .navigationDestination(isPresented: $isFeedPresented) {
                FeedView(account: account, listeningModel: listeningModel)
            }
            .mediaDestinations(model: listeningModel)
        }
    }

    private var feedLink: some View {
        NavigationLink {
            FeedView(account: account, listeningModel: listeningModel)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.artworkGradient(seed: "listening-network"))
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Listening network")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(account.isAuthenticated
                        ? "Pins, recommendations, and recent plays from your music circle"
                        : "Connect your token to open your private ListenBrainz feed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: account.isAuthenticated ? "chevron.right" : "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(account.isAuthenticated
            ? "Open your ListenBrainz activity and recent network listens"
            : "Explains how to sign in for private feed access")
    }

    private var recommendationsLink: some View {
        NavigationLink {
            RecommendationsView(account: account, listeningModel: listeningModel)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.heroGradient)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Made for you")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Recommended tracks, Weekly Jams, and exploration playlists")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open ListenBrainz recommendations")
    }

    private var radioLink: some View {
        NavigationLink {
            RadioView(account: account, listeningModel: listeningModel)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.artworkGradient(seed: "lb-radio"))
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Tune LB Radio")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(account.isAuthenticated
                        ? "Generate a mix from your taste, recommendations, artists, or tags"
                        : "Connect your token to use ListenBrainz's playlist generator")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: account.isAuthenticated ? "chevron.right" : "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(account.isAuthenticated
            ? "Open the native ListenBrainz Radio playlist generator"
            : "Explains why ListenBrainz Radio requires sign-in")
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
                if let seed = ReleaseSeed(freshRelease: release) {
                    NavigationLink(value: seed) {
                        FreshReleaseCard(release: release)
                    }
                    .buttonStyle(.plain)
                } else if let groupMBID = release.releaseGroupMBID {
                    NavigationLink {
                        ReleaseGroupDetailView(
                            group: SearchReleaseGroup(
                                mbid: groupMBID,
                                title: release.title,
                                artistName: release.artistName,
                                primaryType: release.primaryType,
                                firstReleaseDate: release.releaseDate
                            ),
                            viewer: account,
                            discoveryContext: release.discoveryContext
                        )
                    } label: {
                        FreshReleaseCard(release: release)
                    }
                    .buttonStyle(.plain)
                } else {
                    FreshReleaseCard(release: release)
                }
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
