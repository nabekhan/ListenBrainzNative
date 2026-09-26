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
                    if !model.snapshot.topRecordings.isEmpty { favoriteRecordings }
                    ProfilePlaylistSection(
                        model: playlistModel,
                        selection: $selectedPlaylistCategory,
                        viewer: model.account
                    )
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(
                            account: model.account,
                            session: session,
                            connectedServicesProvider: connectedServicesProvider,
                            connectedServicesCache: connectedServicesCache
                        )
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityHint("Manage Brainz and ListenBrainz settings")
                }
            }
            .mediaDestinations(model: model)
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

    private func profileMetric(_ value: String, label: LocalizedStringResource) -> some View {
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
                    if let destination = artist.detailDestination() {
                        NavigationLink(value: destination) {
                            favoriteArtistCard(artist)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens artist details")
                    } else {
                        favoriteArtistCard(artist)
                    }
                }
            }
        }
    }

    private func favoriteArtistCard(_ artist: RankedArtist) -> some View {
        let accessibilityLabel = artist.listenCount == 1
            ? String(localized: "\(artist.name), 1 listen")
            : String(localized: "\(artist.name), \(artist.listenCount) listens")
        return VStack(spacing: 8) {
            ArtistArtworkView(artist: artist)
                .aspectRatio(1, contentMode: .fit)
            Text(artist.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
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

    private var favoriteRecordings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Most played tracks",
                subtitle: "Tracks you return to most"
            )
            UserProfileTopRecordingsList(recordings: Array(model.snapshot.topRecordings.prefix(6)))
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

}
