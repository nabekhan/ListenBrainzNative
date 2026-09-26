import SwiftUI

struct UserDetailView: View {
    let viewer: Account
    @State private var model: UserDetailModel
    @State private var pins: PinsModel
    @State private var viewerListeningModel: ListeningModel
    @State private var isShowingSocial = false

    init(user: SearchUser, viewer: Account) {
        self.viewer = viewer
        _model = State(initialValue: UserDetailModel(user: user, token: viewer.token))
        _pins = State(initialValue: PinsModel(account: Account(username: user.username, token: "")))
        _viewerListeningModel = State(initialValue: ListeningModel(account: viewer))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                identityHeader

                if model.snapshot.recentListens.isEmpty, model.phase == .loading {
                    LoadingStateView(title: "Opening this music life")
                        .frame(minHeight: 230)
                } else if model.snapshot.recentListens.isEmpty,
                          case let .failed(message) = model.phase {
                    FailureStateView(message: message) { await model.refresh() }
                        .frame(minHeight: 230)
                } else {
                    profileContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background {
            AppTheme.artworkGradient(seed: model.user.username)
                .opacity(0.14)
                .ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
        }
        .navigationTitle(model.user.username)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingSocial) {
            UserSocialView(user: model.user, viewer: viewer)
        }
        .toolbar {
            if let url = model.user.listenBrainzURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                        .accessibilityLabel("Open profile in ListenBrainz")
                }
            }
        }
        .refreshable {
            await model.refresh()
            await pins.refresh()
        }
        .task {
            await model.load()
            await pins.load()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-brainz-open-user-social") {
                isShowingSocial = true
            }
            #endif
        }
    }

    private var identityHeader: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle().fill(AppTheme.heroGradient)
                Text(model.user.username.prefix(1).uppercased())
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 116, height: 116)
            .shadow(color: AppTheme.accent.opacity(0.22), radius: 20, y: 9)

            VStack(spacing: 4) {
                Text(model.user.username)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("ListenBrainz listener")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                metric(
                    model.snapshot.listenCount?.formatted(.number.notation(.compactName)) ?? "—",
                    label: "Listens"
                )
                Divider().frame(height: 36)
                metric(latestActivityDescription, label: "Latest activity")
            }
            .padding(.vertical, 15)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var profileContent: some View {
        if let listen = model.featuredListen {
            FeaturedListenCard(
                listen: listen,
                label: listen.isPlayingNow ? "Playing now" : "Latest listen",
                systemImage: listen.isPlayingNow ? "waveform" : "clock.fill"
            )
        }

        CurrentPinSection(isOwner: false)
            .environment(pins)

        socialLink
        UserProfileExploreSection(
            user: model.user,
            viewer: viewer,
            listeningModel: viewerListeningModel
        )

        recentListens
        topArtists
        topReleases
        topRecordings
    }

    private var socialLink: some View {
        Button { isShowingSocial = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.heroGradient, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Social")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Followers, similar listeners, and your match")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this listener’s social connections")
    }

    private var recentListens: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Recently played",
                subtitle: "The latest moments in \(model.user.username)’s listening history"
            )
            if model.snapshot.recentListens.isEmpty {
                ContentUnavailableView(
                    "No listens yet",
                    systemImage: "waveform.slash",
                    description: Text("This profile has no public listening history yet.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ForEach(model.snapshot.recentListens.prefix(8)) { listen in
                    NavigationLink(value: listen.recording) {
                        ListenRow(listen: listen, showsDate: true)
                    }
                    .buttonStyle(.plain)
                    if listen.id != model.snapshot.recentListens.prefix(8).last?.id {
                        Divider().padding(.leading, 66)
                    }
                }
            }
        }
    }

    private var topArtists: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Defining artists", subtitle: "All-time favorites from ListenBrainz")
            switch model.topArtistsPhase {
            case .idle, .loading:
                HStack { Spacer(); ProgressView("Loading artists…"); Spacer() }
                    .frame(minHeight: 116)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Artists unavailable", systemImage: "music.mic")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.loadTopArtists(retrying: true) } }
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            case .ready where model.snapshot.topArtists.isEmpty:
                ContentUnavailableView("No artist stats yet", systemImage: "music.mic")
                    .frame(maxWidth: .infinity, minHeight: 130)
            case .ready:
                DefiningArtistsCarousel(
                    artists: Array(model.snapshot.topArtists.prefix(12)),
                    includesListenCountInDestination: model.user.isSameListener(as: viewer)
                )
            }
        }
        .task { await model.loadTopArtists() }
    }

    private var topReleases: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Most played albums",
                subtitle: "Albums this listener returns to most"
            )
            switch model.topReleasesPhase {
            case .idle, .loading:
                HStack { Spacer(); ProgressView("Loading albums…"); Spacer() }
                    .frame(minHeight: 116)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Albums unavailable", systemImage: "opticaldisc")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.loadTopReleases(retrying: true) } }
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            case .ready where model.snapshot.topReleases.isEmpty:
                ContentUnavailableView("No album stats yet", systemImage: "opticaldisc")
                    .frame(maxWidth: .infinity, minHeight: 130)
            case .ready:
                UserProfileTopReleasesList(releases: Array(model.snapshot.topReleases.prefix(6)))
            }
        }
        .task { await model.loadTopReleases() }
    }

    private var topRecordings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Most played tracks",
                subtitle: "Tracks this listener returns to most"
            )
            switch model.topRecordingsPhase {
            case .idle, .loading:
                HStack { Spacer(); ProgressView("Loading tracks…"); Spacer() }
                    .frame(minHeight: 116)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Tracks unavailable", systemImage: "music.note.list")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await model.loadTopRecordings(retrying: true) } }
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            case .ready where model.snapshot.topRecordings.isEmpty:
                ContentUnavailableView("No track stats yet", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, minHeight: 130)
            case .ready:
                VStack(alignment: .leading, spacing: 10) {
                    UserProfileTopRecordingsList(recordings: Array(model.snapshot.topRecordings.prefix(6)))
                    if let message = model.topRecordingsErrorMessage {
                        trackRefreshNotice(message: message)
                    }
                }
            }
        }
        .task { await model.loadTopRecordings() }
    }

    private func trackRefreshNotice(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn’t update tracks", systemImage: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text("Saved tracks are still shown. \(message)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await model.loadTopRecordings(retrying: true) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func metric(_ value: String, label: LocalizedStringResource) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var latestActivityDescription: String {
        if model.snapshot.playingNow != nil { return String(localized: "Now") }
        guard let date = model.snapshot.recentListens.first?.listenedAt else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }
}

private struct UserProfileTopReleasesList: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let releases: [RankedRelease]
    var loadsArtwork = true

    var body: some View {
        VStack(spacing: 10) {
            ForEach(releases) { release in
                releaseRow(release)
            }
        }
    }

    @ViewBuilder
    private func releaseRow(_ release: RankedRelease) -> some View {
        if let seed = release.releaseSeed {
            NavigationLink(value: seed) {
                releaseRowContents(release, showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens album details")
        } else {
            releaseRowContents(release, showsDisclosure: false)
        }
    }

    @ViewBuilder
    private func releaseRowContents(_ release: RankedRelease, showsDisclosure: Bool) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        ArtworkView(
                            url: loadsArtwork ? release.artworkURL : nil,
                            title: release.name,
                            cornerRadius: 12
                        )
                        .frame(width: 76, height: 76)
                        Spacer(minLength: 12)
                        if showsDisclosure {
                            Image(systemName: "chevron.forward")
                                .font(.body.bold())
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(release.name)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(release.artistName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(listenCountLabel(release.listenCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 13) {
                    ArtworkView(
                        url: loadsArtwork ? release.artworkURL : nil,
                        title: release.name,
                        cornerRadius: 10
                    )
                    .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(release.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(release.artistName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(listenCountLabel(release.listenCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if showsDisclosure {
                        Image(systemName: "chevron.forward")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "\(release.name), \(release.artistName), \(listenCountLabel(release.listenCount))")
        )
    }

    private func listenCountLabel(_ count: Int) -> String {
        String(localized: "\(count) listens")
    }
}

struct UserProfileTopRecordingsList: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let recordings: [RankedRecording]
    var loadsArtwork = true

    var body: some View {
        VStack(spacing: 10) {
            ForEach(recordings) { recording in
                recordingRow(recording)
            }
        }
    }

    @ViewBuilder
    private func recordingRow(_ recording: RankedRecording) -> some View {
        if let destination = recording.detailDestination {
            NavigationLink(value: destination) {
                recordingRowContents(recording, showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens track details")
        } else {
            recordingRowContents(recording, showsDisclosure: false)
        }
    }

    @ViewBuilder
    private func recordingRowContents(_ recording: RankedRecording, showsDisclosure: Bool) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        ArtworkView(
                            url: loadsArtwork ? recording.recording.artworkURL : nil,
                            title: recording.title,
                            cornerRadius: 12
                        )
                        .frame(width: 76, height: 76)
                        Spacer(minLength: 12)
                        if showsDisclosure {
                            Image(systemName: "chevron.forward")
                                .font(.body.bold())
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    recordingText(recording, titleFont: .headline, secondaryFont: .body)
                    Text(listenCountLabel(recording.listenCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 13) {
                    ArtworkView(
                        url: loadsArtwork ? recording.recording.artworkURL : nil,
                        title: recording.title,
                        cornerRadius: 10
                    )
                    .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        recordingText(recording, titleFont: .body.weight(.semibold), secondaryFont: .subheadline)
                        Text(listenCountLabel(recording.listenCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if showsDisclosure {
                        Image(systemName: "chevron.forward")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: recording))
    }

    @ViewBuilder
    private func recordingText(
        _ recording: RankedRecording,
        titleFont: Font,
        secondaryFont: Font
    ) -> some View {
        Text(recording.title)
            .font(titleFont)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
        Text(recording.artistName)
            .font(secondaryFont)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
        if let releaseTitle = recording.releaseTitle, !releaseTitle.isEmpty {
            Text(releaseTitle)
                .font(secondaryFont)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accessibilityLabel(for recording: RankedRecording) -> String {
        let count = listenCountLabel(recording.listenCount)
        if let releaseTitle = recording.releaseTitle {
            return String(localized: "\(recording.title), \(recording.artistName), \(releaseTitle), \(count)")
        }
        return String(localized: "\(recording.title), \(recording.artistName), \(count)")
    }

    private func listenCountLabel(_ count: Int) -> String {
        String(localized: "\(count) listens")
    }
}

private struct DefiningArtistsCarousel: View {
    let artists: [RankedArtist]
    let includesListenCountInDestination: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVStack(spacing: 12) {
                ForEach(artists) { artist in
                    artistCard(artist)
                }
            }
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(artists) { artist in
                        artistCard(artist)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func artistCard(_ artist: RankedArtist) -> some View {
        if let destination = artist.detailDestination(
            includingListenCount: includesListenCountInDestination
        ) {
            NavigationLink(value: destination) {
                cardContents(artist, showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens artist details")
        } else {
            cardContents(artist, showsDisclosure: false)
        }
    }

    @ViewBuilder
    private func cardContents(_ artist: RankedArtist, showsDisclosure: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ArtistArtworkView(artist: artist)
                        .frame(width: 76, height: 76)
                    Spacer(minLength: 8)
                    if showsDisclosure {
                        Image(systemName: "chevron.forward")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                            .accessibilityHidden(true)
                    }
                }
                Text(artist.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(listenCountLabel(artist.listenCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(localized: "\(artist.name), \(listenCountLabel(artist.listenCount))")
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ArtistArtworkView(artist: artist)
                    .frame(width: 116, height: 116)
                Text(artist.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                Text(listenCountLabel(artist.listenCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 116, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(localized: "\(artist.name), \(listenCountLabel(artist.listenCount))")
            )
        }
    }

    private func listenCountLabel(_ count: Int) -> String {
        String(localized: "\(count) listens")
    }
}

#if DEBUG
struct UserDefiningArtistsVisualQAScreen: View {
    @Bindable var model: ListeningModel

    private let artists = [
        RankedArtist(
            mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab"),
            name: "Alvvays",
            listenCount: 1_283
        ),
        RankedArtist(mbid: nil, name: "Unmapped Demo Artist", listenCount: 36),
        RankedArtist(
            mbid: UUID(uuidString: "6c0b31f3-2e41-4d70-bd16-5fa8551bd59b"),
            name: "Japanese Breakfast",
            listenCount: 947
        ),
        RankedArtist(
            mbid: UUID(uuidString: "a1d4c987-9c07-4c71-8f75-6505e2e8f554"),
            name: "The Marías",
            listenCount: 1
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        title: "Defining artists",
                        subtitle: "All-time favorites from ListenBrainz"
                    )
                    DefiningArtistsCarousel(
                        artists: artists,
                        includesListenCountInDestination: false
                    )
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("music-friend")
            .navigationBarTitleDisplayMode(.inline)
            .mediaDestinations(model: model)
        }
    }
}

struct UserProfileAlbumsVisualQAScreen: View {
    @Bindable var model: ListeningModel

    private let releases = [
        RankedRelease(
            mbid: nil,
            name: "A Very Long Unmapped Album Title for Layout Inspection",
            artistName: "Japanese Breakfast",
            artistMBIDs: [],
            listenCount: 587
        ),
        RankedRelease(
            mbid: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"),
            name: "Blue Rev",
            artistName: "Alvvays",
            artistMBIDs: [UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!],
            listenCount: 423
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        title: "Most played albums",
                        subtitle: "Albums this listener returns to most"
                    )
                    UserProfileTopReleasesList(releases: releases, loadsArtwork: false)
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("music-friend")
            .navigationBarTitleDisplayMode(.inline)
            .mediaDestinations(model: model)
        }
    }
}

struct UserProfileTracksVisualQAScreen: View {
    @Bindable var model: ListeningModel

    private let recordings = [
        RankedRecording(
            mbid: nil,
            releaseMBID: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"),
            title: "A Very Long Unmapped Track Title for Layout Inspection and VoiceOver",
            artistName: "Japanese Breakfast",
            artistMBIDs: [],
            releaseTitle: "A Very Long Unmapped Album Title for Layout Inspection",
            listenCount: 587
        ),
        RankedRecording(
            mbid: UUID(uuidString: "1bf70850-1a66-4e77-b751-51410977ff04"),
            releaseMBID: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"),
            title: "Belinda Says",
            artistName: "Alvvays",
            artistMBIDs: [UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!],
            releaseTitle: "Blue Rev",
            listenCount: 423
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        title: "Most played tracks",
                        subtitle: "Tracks this listener returns to most"
                    )
                    UserProfileTopRecordingsList(recordings: recordings, loadsArtwork: false)
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("music-friend")
            .navigationBarTitleDisplayMode(.inline)
            .mediaDestinations(model: model)
        }
    }
}
#endif
