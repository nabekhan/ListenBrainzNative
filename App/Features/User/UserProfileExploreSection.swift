import SwiftUI

struct UserProfileExploreSection: View {
    let user: SearchUser
    let viewer: Account
    let listeningModel: ListeningModel

    private let playlistProvider: (any ProfilePlaylistsProviding)?
    private let playlistCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>
    private let yearInMusicProvider: (any YearInMusicProviding)?
    private let yearInMusicCache: EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        user: SearchUser,
        viewer: Account,
        listeningModel: ListeningModel,
        playlistProvider: (any ProfilePlaylistsProviding)? = nil,
        playlistCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages,
        yearInMusicProvider: (any YearInMusicProviding)? = nil,
        yearInMusicCache: EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>? = nil
    ) {
        self.user = user
        self.viewer = viewer
        self.listeningModel = listeningModel
        self.playlistProvider = playlistProvider
        self.playlistCache = playlistCache
        self.yearInMusicProvider = yearInMusicProvider
        self.yearInMusicCache = yearInMusicCache
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "More to explore",
                subtitle: "Go deeper into \(user.username)’s music life"
            )

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { destinations }
            } else {
                HStack(alignment: .top, spacing: 12) { destinations }
            }
        }
    }

    @ViewBuilder
    private var destinations: some View {
        NavigationLink {
            UserProfilePlaylistsView(
                user: user,
                viewer: viewer,
                provider: playlistProvider,
                cache: playlistCache
            )
        } label: {
            destinationCard(
                title: "Playlists",
                subtitle: "Public collections and collaborations",
                systemImage: "music.note.list",
                gradient: [AppTheme.accent, AppTheme.secondary]
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Opens \(user.username)’s playlists"))

        NavigationLink {
            YearInMusicView(
                account: viewer,
                subjectUsername: user.username,
                listeningModel: listeningModel,
                provider: yearInMusicProvider,
                cache: yearInMusicCache
            )
        } label: {
            destinationCard(
                title: "Year in Music",
                subtitle: "Annual listening stories",
                systemImage: "sparkles.rectangle.stack.fill",
                gradient: [AppTheme.secondary, AppTheme.accent.opacity(0.72)]
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Opens \(user.username)’s Year in Music"))
    }

    private func destinationCard(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        systemImage: String,
        gradient: [Color]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 0 : 174, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .contentShape(.rect)
    }
}

struct UserProfilePlaylistsView: View {
    let user: SearchUser
    let viewer: Account

    @State private var model: ProfilePlaylistsModel
    @State private var selection: ProfilePlaylistCategory = .owned

    init(
        user: SearchUser,
        viewer: Account,
        provider: (any ProfilePlaylistsProviding)? = nil,
        cache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        self.user = user
        self.viewer = viewer
        _model = State(
            initialValue: ProfilePlaylistsModel(
                account: Account(username: user.username, token: viewer.token),
                provider: provider,
                cache: cache
            )
        )
    }

    var body: some View {
        ScrollView {
            ProfilePlaylistSection(
                model: model,
                selection: $selection,
                viewer: viewer
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background {
            AppTheme.artworkGradient(seed: user.username)
                .opacity(0.1)
                .ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
        }
        .navigationTitle(String(localized: "\(user.username)’s playlists"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            guard model.state(for: selection).phase != .idle else { return }
            await model.refresh(category: selection)
        }
    }
}

#if DEBUG
struct UserProfileExploreVisualQAScreen: View {
    @Bindable var listeningModel: ListeningModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let user = SearchUser(username: "music-friend-with-a-long-name")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle().fill(AppTheme.heroGradient)
                                Text(user.username.prefix(1).uppercased())
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 104, height: 104)

                            Text(user.username)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    UserProfileExploreSection(
                        user: user,
                        viewer: listeningModel.account,
                        listeningModel: listeningModel
                    )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background {
                AppTheme.artworkGradient(seed: user.username)
                    .opacity(0.12)
                    .ignoresSafeArea()
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
            }
            .navigationTitle("Listener")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
