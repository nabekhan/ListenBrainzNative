import SwiftUI

struct UserDetailView: View {
    let viewer: Account
    @State private var model: UserDetailModel
    @State private var pins: PinsModel
    @State private var isShowingSocial = false

    init(user: SearchUser, viewer: Account) {
        self.viewer = viewer
        _model = State(initialValue: UserDetailModel(user: user, token: viewer.token))
        _pins = State(initialValue: PinsModel(account: Account(username: user.username, token: "")))
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

        recentListens
        topArtists
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
                Image(systemName: "chevron.right")
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
                subtitle: "The latest moments in (model.user.username)’s listening history"
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
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(model.snapshot.topArtists.prefix(12)) { artist in
                            VStack(alignment: .leading, spacing: 8) {
                                ArtistArtworkView(artist: artist)
                                    .frame(width: 116, height: 116)
                                Text(artist.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(artist.listenCount.formatted()) listens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 116, alignment: .leading)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
        .task { await model.loadTopArtists() }
    }

    private func metric(_ value: String, label: String) -> some View {
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
        if model.snapshot.playingNow != nil { return "Now" }
        guard let date = model.snapshot.recentListens.first?.listenedAt else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }
}
