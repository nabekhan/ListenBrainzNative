import SwiftUI

struct ArtistHeroPresentation: Equatable {
    let artistName: String
    let identity: ArtistPageIdentity?

    var artworkAccessibilityLabel: String { "Artwork for \(artistName)" }

    var metadataLine: String? {
        guard let identity else { return nil }
        var details: [String] = []
        switch (identity.beginYear, identity.endYear) {
        case let (.some(begin), .some(end)):
            details.append("\(begin)–\(end)")
        case let (.some(begin), .none):
            details.append("Since \(begin)")
        case let (.none, .some(end)):
            details.append("Until \(end)")
        case (.none, .none):
            break
        }
        if let area = identity.area { details.append(area) }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }
}

struct ArtistDetailView: View {
    let artist: RankedArtist
    @Bindable var model: ListeningModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsArtwork = false
    @State private var pageContext: ArtistPageContext?
    @State private var pageContextFailed = false
    @State private var isRetryingPageContext = false
    @State private var pageContextRevision = 0
    @State private var heroArtworkImage: UIImage?
    private let pageContextProvider: any ArtistPageContextProviding

    init(
        artist: RankedArtist,
        model: ListeningModel,
        pageContextProvider: (any ArtistPageContextProviding)? = nil
    ) {
        self.artist = artist
        _model = Bindable(wrappedValue: model)
        self.pageContextProvider = pageContextProvider
            ?? ListenBrainzArtistPageContextProvider()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                hero
                artistPageFailure
                popularity
                topListeners
                reviews
                topRecordings
                artistHighlights
                similarArtists
                recentListens
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background {
            AppTheme.artworkGradient(seed: artist.name)
                .opacity(0.16)
                .ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artist.mbid) {
            await loadPageContext()
        }
        .navigationDestination(for: Recording.self) { recording in
            RecordingDetailView(recording: recording, model: model)
        }
        .navigationDestination(for: SearchUser.self) { user in
            UserDetailView(user: user, viewer: model.account)
        }
        .toolbar {
            if artist.mbid != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsArtwork = true } label: { Image(systemName: "photo") }
                    .accessibilityLabel("Create artist artwork")
                }
            }
            if let mbid = artist.mbid {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: URL(string: "https://musicbrainz.org/artist/\(mbid.uuidString)")!) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open artist in MusicBrainz")
                }
            }
        }
        .sheet(isPresented: $showsArtwork) {
            if let mbid = artist.mbid {
                GeneratedArtworkSheet(
                    presentation: .artist(name: artist.name, mbid: mbid),
                    request: .artist(mbid: mbid),
                    provider: ListenBrainzGeneratedArtworkProvider(
                        token: model.account.token
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var similarArtists: some View {
        if let mbid = artist.mbid {
            SimilarArtistsSummaryView(artistMBID: mbid)
                .environment(
                    \.similarArtistsProvider,
                    ListenBrainzSimilarArtistsProvider(
                        contextProvider: pageContextProvider,
                        suppressesErrors: true
                    )
                )
                .id(pageContextRevision)
        }
    }

    @ViewBuilder
    private var artistHighlights: some View {
        if let mbid = artist.mbid {
            ArtistHighlightsSummaryView(artistMBID: mbid)
                .environment(
                    \.artistHighlightsProvider,
                    ListenBrainzArtistHighlightsProvider(
                        contextProvider: pageContextProvider,
                        suppressesErrors: true
                    )
                )
                .id(pageContextRevision)
        }
    }

    @ViewBuilder
    private var popularity: some View {
        if let mbid = artist.mbid {
            PopularitySummaryView(entity: PopularityEntity(kind: .artist, mbid: mbid))
                .environment(
                    \.popularityProvider,
                    ArtistPageContextPopularityProvider(contextProvider: pageContextProvider)
                )
                .id(pageContextRevision)
        }
    }

    @ViewBuilder
    private var topListeners: some View {
        if let mbid = artist.mbid {
            TopListenersSummaryView(
                entity: TopListenersEntity(kind: .artist, mbid: mbid),
                viewer: model.account
            )
            .environment(
                \.topListenersProvider,
                ArtistPageContextTopListenersProvider(contextProvider: pageContextProvider)
            )
            .id(pageContextRevision)
        }
    }

    @ViewBuilder
    private var reviews: some View {
        if let mbid = artist.mbid {
            CritiqueBrainzReviewSummaryView(entity: .init(kind: .artist, mbid: mbid))
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            heroArtwork
                .frame(width: 224, height: 224)
                .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                .padding(.top, 14)
            Text(artist.name)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if artist.listenCount > 0 {
                Label("\(artist.listenCount.formatted()) of your listens", systemImage: "waveform")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Label("MusicBrainz artist", systemImage: "music.mic")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let metadataLine = heroPresentation.metadataLine {
                Text(metadataLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var artistPageFailure: some View {
        if pageContextFailed {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        artistPageFailureMessage
                        artistPageRetryButton
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        artistPageFailureMessage
                        Spacer(minLength: 8)
                        artistPageRetryButton
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private var artistPageFailureMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("More artist details couldn’t load")
                    .font(.subheadline.weight(.semibold))
                Text("Try again for community totals, top listeners, and popular tracks and releases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var artistPageRetryButton: some View {
        Button("Try again") {
            Task { await loadPageContext(forceRefresh: true) }
        }
        .buttonStyle(.bordered)
        .disabled(isRetryingPageContext)
    }

    private var heroArtwork: some View {
        ZStack {
            if let svg = pageContext?.coverArtSVG {
                // Keep WebKit behind the app-owned fallback. Only its delayed,
                // complete snapshot becomes visible, avoiding partial object
                // paints while remote cover tiles finish loading.
                SVGArtworkPreview(
                    svg: svg,
                    reloadID: 0,
                    accessibilityLabel: heroPresentation.artworkAccessibilityLabel
                ) { phase in
                    switch phase {
                    case .preparing, .failed:
                        heroArtworkImage = nil
                    case let .ready(image):
                        heroArtworkImage = image
                    }
                }
                .accessibilityHidden(true)
            }

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.artworkGradient(seed: artist.name))
                .overlay {
                    Text(artist.name.prefix(1).uppercased())
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }

            if pageContext?.coverArtSVG != nil, let heroArtworkImage {
                Image(uiImage: heroArtworkImage)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroPresentation.artworkAccessibilityLabel)
    }

    private var heroPresentation: ArtistHeroPresentation {
        ArtistHeroPresentation(artistName: artist.name, identity: pageContext?.identity)
    }

    private func loadPageContext(forceRefresh: Bool = false) async {
        guard let artistMBID = artist.mbid else {
            heroArtworkImage = nil
            pageContext = nil
            pageContextFailed = false
            return
        }
        if forceRefresh { isRetryingPageContext = true }
        defer {
            if forceRefresh { isRetryingPageContext = false }
        }
        do {
            let value = try await pageContextProvider.context(
                for: artistMBID,
                forceRefresh: forceRefresh
            )
            try Task.checkCancellation()
            guard value?.artistMBID == artistMBID || value == nil else { return }
            if pageContext?.coverArtSVG != value?.coverArtSVG {
                heroArtworkImage = nil
            }
            pageContext = value
            pageContextFailed = false
            if forceRefresh {
                await SimilarArtistsCaches.values.removeValue(
                    for: SimilarArtistsCacheKey(artistMBID: artistMBID)
                )
                await TopListenersCaches.values.removeValue(
                    for: TopListenersCacheKey(
                        entity: TopListenersEntity(kind: .artist, mbid: artistMBID),
                        scope: .authenticated(token: model.account.token)
                    )
                )
                pageContextRevision += 1
            }
        } catch is CancellationError {
            return
        } catch {
            // The generated fallback is already visible. The Highlights
            // sections suppress duplicate errors; this card owns one retry.
            heroArtworkImage = nil
            pageContext = nil
            pageContextFailed = true
        }
    }

    @ViewBuilder
    private var topRecordings: some View {
        let recordings = model.recordings(for: artist)
        if !recordings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Your top recordings")
                ForEach(Array(recordings.prefix(10).enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item.recording) {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            ArtworkView(url: item.recording.artworkURL, title: item.title, cornerRadius: 7)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.body.weight(.semibold)).lineLimit(1)
                                Text("\(item.listenCount.formatted()) listens")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var recentListens: some View {
        let listens = model.listens(for: artist)
        if !listens.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Recent history", subtitle: "Recent listens from this artist")
                ForEach(listens.prefix(10)) { listen in
                    NavigationLink(value: listen.recording) {
                        ListenRow(listen: listen, showsDate: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
