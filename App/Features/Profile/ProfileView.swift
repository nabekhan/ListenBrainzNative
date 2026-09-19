import SwiftUI

struct ProfileView: View {
    @Bindable var model: ListeningModel
    @Bindable var session: SessionModel
    @Environment(PinsModel.self) private var pins
    @State private var playlistModel: ProfilePlaylistsModel
    @State private var selectedPlaylistCategory: ProfilePlaylistCategory
    private let connectedServicesProvider: (any ConnectedServicesProviding)?
    private let connectedServicesCache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices>

    init(
        model: ListeningModel,
        session: SessionModel,
        playlistProvider: (any ProfilePlaylistsProviding)? = nil,
        playlistCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages,
        connectedServicesProvider: (any ConnectedServicesProviding)? = nil,
        connectedServicesCache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices> = ConnectedServicesCaches.values,
        initialPlaylistCategory: ProfilePlaylistCategory = .owned
    ) {
        _model = Bindable(wrappedValue: model)
        _session = Bindable(wrappedValue: session)
        _playlistModel = State(initialValue: ProfilePlaylistsModel(
            account: model.account,
            provider: playlistProvider,
            cache: playlistCache
        ))
        _selectedPlaylistCategory = State(initialValue: initialPlaylistCategory)
        self.connectedServicesProvider = connectedServicesProvider
        self.connectedServicesCache = connectedServicesCache
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    profileHeader
                    CurrentPinSection(isOwner: model.account.isAuthenticated)
                    if !model.snapshot.topArtists.isEmpty { favoriteArtists }
                    if !model.snapshot.topReleases.isEmpty { favoriteReleases }
                    ProfilePlaylistSection(
                        model: playlistModel,
                        selection: $selectedPlaylistCategory,
                        viewer: model.account
                    )
                    accountSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .refreshable {
                await model.refresh()
                await pins.refresh()
                if playlistModel.state(for: selectedPlaylistCategory).phase != .idle {
                    await playlistModel.refresh(category: selectedPlaylistCategory)
                }
            }
            .task { await pins.load() }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .mediaDestinations(model: model)
            .alert(
                "Account",
                isPresented: Binding(
                    get: { session.errorMessage != nil },
                    set: { if !$0 { session.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "")
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(AppTheme.heroGradient)
                Text(model.account.username.prefix(1).uppercased())
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 132, height: 132)
            .shadow(color: AppTheme.accent.opacity(0.24), radius: 22, y: 10)

            VStack(spacing: 5) {
                Text(model.account.username)
                    .font(.largeTitle.bold())
                Label(
                    model.account.isAuthenticated ? "Connected to ListenBrainz" : "Public profile",
                    systemImage: model.account.isAuthenticated ? "checkmark.seal.fill" : "eye.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.account.isAuthenticated ? AppTheme.secondary : .secondary)
            }

            HStack(spacing: 0) {
                profileMetric(model.snapshot.listenCount?.formatted() ?? "—", label: "Listens")
                Divider().frame(height: 36)
                profileMetric(model.snapshot.topArtists.count.formatted(), label: "Top artists loaded")
                Divider().frame(height: 36)
                profileMetric(model.snapshot.topReleases.count.formatted(), label: "Albums loaded")
            }
            .padding(.vertical, 16)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func profileMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var favoriteArtists: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Defining artists", subtitle: "The artists at the center of this profile")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16)], spacing: 18) {
                ForEach(model.snapshot.topArtists.prefix(8)) { artist in
                    NavigationLink(value: artist) {
                        VStack(spacing: 8) {
                            ArtistArtworkView(artist: artist)
                                .aspectRatio(1, contentMode: .fit)
                            Text(artist.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var favoriteReleases: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Most played albums")
            ForEach(model.snapshot.topReleases.prefix(6)) { release in
                if let seed = release.releaseSeed {
                    NavigationLink(value: seed) {
                        releaseRow(release)
                    }
                    .buttonStyle(.plain)
                } else {
                    releaseRow(release)
                }
            }
        }
    }

    private func releaseRow(_ release: RankedRelease) -> some View {
        HStack(spacing: 13) {
            ArtworkView(url: release.artworkURL, title: release.name, cornerRadius: 9)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(release.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(release.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(release.listenCount.formatted())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Account")
            if model.account.isAuthenticated {
                NavigationLink {
                    ConnectedServicesView(
                        account: model.account,
                        provider: connectedServicesProvider,
                        cache: connectedServicesCache
                    )
                } label: {
                    Label("Connected services", systemImage: "link")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
                }
                .accessibilityHint("View services linked to this account")
            }
            Link(destination: Self.listenBrainzProfileURL(for: model.account.username)) {
                Label("Open profile on ListenBrainz", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
            }
            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Label(model.account.isAuthenticated ? "Disconnect account" : "Leave public profile", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private static func listenBrainzProfileURL(for username: String) -> URL {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: allowed) ?? username
        return URL(string: "https://listenbrainz.org/user/\(encodedUsername)/")!
    }
}
