import SwiftUI

struct MainTabView: View {
    private enum Destination: String, Hashable {
        case home
        case history
        case discover
        case taste
        case profile
    }

    let account: Account
    @Bindable var session: SessionModel
    @State private var model: ListeningModel
    @State private var pins: PinsModel
    @State private var presentedListen: Listen?
    @AppStorage("main.selectedTab") private var selectedTab: Destination = .home

    init(account: Account, session: SessionModel) {
        self.account = account
        _session = Bindable(wrappedValue: session)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-collab-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-edit-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-add-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-copy-demo") {
            let visualAccount = Account(username: "visual-listener", token: "visual-token")
            _model = State(initialValue: ListeningModel(
                account: visualAccount,
                provider: VisualQATasteProvider()
            ))
            _pins = State(initialValue: PinsModel(
                account: visualAccount,
                provider: VisualQAPinProvider()
            ))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-all-time-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-genre-activity-demo") {
            let visualAccount = Account(username: "visual-taste", token: "visual-taste")
            _model = State(initialValue: ListeningModel(
                account: visualAccount,
                provider: VisualQATasteProvider()
            ))
            _pins = State(initialValue: PinsModel(
                account: visualAccount,
                provider: VisualQAPinProvider()
            ))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-brainz-popularity-detail-demo") {
            let visualAccount = Account(username: "visual-popularity", token: "visual-popularity")
            _model = State(initialValue: ListeningModel(
                account: visualAccount,
                provider: VisualQAPopularityListeningProvider()
            ))
            _pins = State(initialValue: PinsModel(
                account: visualAccount,
                provider: VisualQAPinProvider()
            ))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-demo") {
            let visualAccount = Account(username: "visual-taste", token: "visual-taste")
            _model = State(initialValue: ListeningModel(
                account: visualAccount,
                provider: VisualQATasteProvider()
            ))
            _pins = State(initialValue: PinsModel(
                account: visualAccount,
                provider: VisualQAPinProvider()
            ))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-brainz-radio-demo") {
            let visualAccount = Account(username: "visual-radio", token: "visual-radio")
            _model = State(initialValue: ListeningModel(
                account: visualAccount,
                provider: VisualQATasteProvider()
            ))
            _pins = State(initialValue: PinsModel(
                account: visualAccount,
                provider: VisualQAPinProvider()
            ))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-brainz-history-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-history-day-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-long-title-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-recovery-demo") {
            let visualAccount = Account(username: "visual-history", token: "visual-history")
            _model = State(initialValue: ListeningModel(
                account: visualAccount,
                provider: VisualQAHistoryProvider()
            ))
            _pins = State(initialValue: PinsModel(
                account: visualAccount,
                provider: VisualQAPinProvider()
            ))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-brainz-taste-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-taste-heatmap-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-teaser-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-zoom-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-card-demo") {
            let visualAccount = Account(username: "visual-taste", token: "visual-taste")
            _model = State(initialValue: ListeningModel(
                account: visualAccount,
                provider: VisualQATasteProvider()
            ))
            _pins = State(initialValue: PinsModel(
                account: visualAccount,
                provider: VisualQAPinProvider()
            ))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-brainz-recording-share-demo") {
            let visualAccount = Account(username: "visual-qa", token: "visual-qa")
            _model = State(initialValue: ListeningModel(account: visualAccount))
            _pins = State(initialValue: PinsModel(
                account: visualAccount,
                provider: VisualQAPinProvider()
            ))
            return
        }
        #endif
        _model = State(initialValue: ListeningModel(account: account))
        _pins = State(initialValue: PinsModel(account: account))
    }

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-copy-demo") {
            PlaylistCopyVisualQAScreen()
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-edit-demo") {
            PlaylistMutationVisualQAScreen()
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-add-demo") {
            PlaylistAddVisualQAScreen()
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-collab-demo") {
            ProfilePlaylistVisualQAScreen(
                selection: ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-collab-demo")
                    ? .collaborating
                    : .owned
            )
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-taste-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-taste-heatmap-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-teaser-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-zoom-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-card-demo") {
            TasteView(model: model)
                .task { await model.load() }
                .environment(pins)
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-all-time-demo") {
            NavigationStack {
                ArtistEvolutionView(
                    model: model,
                    period: .constant(
                        ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-all-time-demo")
                            ? .allTime
                            : .thisYear
                    )
                )
                    .mediaDestinations(model: model)
            }
            .environment(pins)
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-genre-activity-demo") {
            NavigationStack {
                GenreActivityView(model: model, period: .constant(.thisMonth))
            }
            .environment(pins)
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-popularity-detail-demo") {
            NavigationStack {
                ArtistDetailView(artist: Self.popularityPreviewArtist, model: model)
            }
            .task { await model.load() }
            .environment(pins)
            .environment(\.popularityProvider, VisualQAPopularityProvider())
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-demo") {
            NavigationStack {
                if ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-art-demo") {
                    YearInMusicView(
                        account: account,
                        listeningModel: model,
                        provider: VisualQAYearInMusicProvider(),
                        artworkProvider: VisualQAYearInMusicArtworkProvider(),
                        cache: EntityDetailCache()
                    )
                } else {
                    YearInMusicView(
                        account: account,
                        listeningModel: model,
                        provider: VisualQAYearInMusicProvider(),
                        cache: EntityDetailCache()
                    )
                }
            }
            .environment(pins)
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-radio-demo") {
            NavigationStack {
                RadioView(
                    account: model.account,
                    listeningModel: model,
                    provider: VisualQARadioProvider()
                )
            }
            .environment(pins)
        } else if ProcessInfo.processInfo.arguments.contains("-brainz-release-detail-demo") {
            NavigationStack {
                ReleaseDetailView(
                    release: Self.releasePreviewSeed,
                    provider: VisualQAReleaseDetailProvider(),
                    cache: EntityDetailCache()
                )
            }
        } else {
            mainContent
        }
        #else
        mainContent
        #endif
    }

    private var mainContent: some View {
        accessoryTabs
            .task {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                guard !arguments.contains("-brainz-recording-share-demo"),
                      !arguments.contains("-brainz-feed-demo"),
                      !arguments.contains("-brainz-recommendations-demo")
                else { return }
                #endif
                await model.load()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-brainz-history-day-demo"),
                   let day = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -2, to: .now) {
                    await model.selectHistoryDay(day)
                }
                #endif
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-recommendations")
                    || ProcessInfo.processInfo.arguments.contains("-brainz-open-feed") {
                    selectedTab = .discover
                }
                if ProcessInfo.processInfo.arguments.contains("-brainz-history-demo")
                    || ProcessInfo.processInfo.arguments.contains("-brainz-history-day-demo")
                    || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-demo")
                    || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-long-title-demo")
                    || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-recovery-demo") {
                    selectedTab = .history
                }
                if ProcessInfo.processInfo.arguments.contains("-brainz-recording-share-demo"),
                   presentedListen == nil {
                    presentedListen = Self.recommendationPreviewListen
                }
                #endif
            }
            .environment(pins)
            .sheet(item: $presentedListen) { listen in
                NavigationStack {
                    RecordingDetailView(recording: listen.recording, model: model)
                }
                .environment(pins)
            }
            .alert(
                "ListenBrainz",
                isPresented: Binding(
                    get: { model.actionError != nil || pins.actionError != nil },
                    set: {
                        if !$0 {
                            model.actionError = nil
                            pins.actionError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.actionError = nil
                    pins.actionError = nil
                }
            } message: {
                Text(pins.actionError ?? model.actionError ?? "")
            }
    }

    @ViewBuilder
    private var accessoryTabs: some View {
        if let nowPlaying = model.snapshot.playingNow {
            if #available(iOS 26.0, *) {
                tabs
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        MiniListenBar(listen: nowPlaying) { presentedListen = nowPlaying }
                    }
            } else {
                tabs.safeAreaInset(edge: .bottom, spacing: 0) {
                    MiniListenBar(listen: nowPlaying) { presentedListen = nowPlaying }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(model: model)
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView(model: model)
            }
            Tab("Discover", systemImage: "sparkles", value: .discover) {
                DiscoverView(account: account, listeningModel: model)
            }
            Tab("Taste", systemImage: "chart.bar.xaxis", value: .taste) {
                TasteView(model: model)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                ProfileView(model: model, session: session)
            }
        }
    }

    #if DEBUG
    private static let recommendationPreviewListen = Listen(
        recording: Recording(
            identity: RecordingIdentity(
                mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab"),
                msid: nil
            ),
            title: "Dreams Tonite",
            artistName: "Alvvays",
            artistMBIDs: [],
            releaseTitle: "Antisocialites",
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: 196_000,
            source: "ListenBrainz"
        ),
        listenedAt: .now,
        insertedAt: .now,
        isPlayingNow: false
    )

    private static let releasePreviewSeed = ReleaseSeed(
        mbid: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!,
        title: "Four You",
        artistName: "Karan Aujla, Ikky",
        artistMBIDs: [
            UUID(uuidString: "4a779683-5404-4b90-a0d7-242495158265")!,
            UUID(uuidString: "3ea12c3c-8596-4d70-b327-208b0a459a97")!,
        ],
        releaseGroupMBID: UUID(uuidString: "eb8734c9-127d-495e-b908-9194cdbac45d"),
        releaseDate: "2023-02-04",
        primaryType: "EP",
        artworkReleaseMBID: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"),
        discoveryContext: ReleaseDiscoveryContext(
            tags: ["punjabi pop", "hip hop", "desi"],
            confidence: 2,
            listenCount: 4_312
        )
    )

    private static let popularityPreviewArtist = RankedArtist(
        mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab"),
        name: "Alvvays",
        listenCount: 1_283
    )
    #endif
}

#if DEBUG
private struct VisualQAReleaseDetailProvider: ConcreteReleaseDetailProviding {
    func release(seed: ReleaseSeed) async throws -> ReleaseDetail {
        ReleaseDetail(
            mbid: seed.mbid,
            title: seed.title,
            artistCreditName: seed.artistName,
            releaseDate: seed.releaseDate,
            country: "IN",
            status: "Official",
            barcode: "859770181552",
            packaging: "None",
            labels: ["Rehaan Records"],
            releaseGroupMBID: seed.releaseGroupMBID,
            releaseGroupPrimaryType: "EP",
            media: [
                ReleaseMedium(
                    position: 1,
                    format: "Digital Media",
                    title: nil,
                    tracks: [
                        track(seed: seed, position: 1, title: "52 Bars", duration: 214_024, mapped: true),
                        track(seed: seed, position: 2, title: "Take It Easy", duration: 210_361, mapped: true),
                        track(seed: seed, position: 3, title: "Fallin Apart", duration: 198_000, mapped: false),
                        track(seed: seed, position: 4, title: "Yeah Naah", duration: 182_375, mapped: true),
                    ]
                ),
            ]
        )
    }

    private func track(
        seed: ReleaseSeed,
        position: Int,
        title: String,
        duration: Int,
        mapped: Bool
    ) -> ReleaseTrack {
        ReleaseTrack(
            position: position,
            number: String(position),
            recording: Recording(
                identity: .init(mbid: mapped ? UUID() : nil, msid: nil),
                title: title,
                artistName: seed.artistName,
                artistMBIDs: seed.artistMBIDs,
                releaseTitle: seed.title,
                releaseMBID: seed.mbid,
                releaseGroupMBID: seed.releaseGroupMBID,
                artworkReleaseMBID: seed.artworkReleaseMBID,
                durationMilliseconds: duration,
                source: nil
            )
        )
    }
}

private struct VisualQAPinProvider: PinProviding {
    func currentPin(username: String) async throws -> PinnedRecording? { nil }
    func pin(_ recording: Recording, blurb: String?) async throws -> PinnedRecording {
        throw PinProviderError.pinNeedsIdentifier
    }
    func pinHistory(username: String, count: Int, offset: Int) async throws -> (pins: [PinnedRecording], totalCount: Int) {
        ([], 0)
    }
    func unpin() async throws {}
    func updatePinBlurb(rowID: Int, blurb: String) async throws {}
    func deletePin(rowID: Int) async throws {}
}

private struct VisualQARadioProvider: RadioProviding {
    private static let artworkReleaseMBID = UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!
    private static let secondArtworkReleaseMBID = UUID(uuidString: "5fbea312-0b73-4e2d-9e42-e25f972f6041")!

    func generate(options: RadioGenerationOptions) async throws -> RadioMix {
        try await ContinuousClock().sleep(for: .milliseconds(180))
        let rows: [(String, String, String?, UUID?, UUID?)] = [
            ("After the Earthquake", "Alvvays", "Blue Rev", UUID(uuidString: "39ad19e5-c0b0-454a-985b-201fb92898a0"), Self.artworkReleaseMBID),
            ("Be Sweet", "Japanese Breakfast", "Jubilee", UUID(uuidString: "42d36a20-621a-4c34-b2fe-01c85447f9e8"), Self.secondArtworkReleaseMBID),
            ("Only in My Dreams", "The Marías", "Superclean, Vol. I", UUID(uuidString: "9b84f25f-c7a4-4b60-8c59-0d5774f5d568"), Self.artworkReleaseMBID),
            ("Andromeda", "Weyes Blood", "Titanic Rising", UUID(uuidString: "173fc72a-efb8-4e58-a15e-86eecf7ac58d"), Self.secondArtworkReleaseMBID),
            ("Show Me How", "Men I Trust", "Oncle Jazz", UUID(uuidString: "5a7d9f53-44d0-492c-9c63-dce87d467424"), Self.artworkReleaseMBID),
            ("A very long recording title that still belongs in a calm late-night mix", "An Artist With a Longer Credit", nil, nil, nil),
            ("Your Best American Girl", "Mitski", "Puberty 2", UUID(uuidString: "8348bd91-4b34-4bfc-bfaa-e9d958e5fc2f"), Self.secondArtworkReleaseMBID),
            ("Space Song", "Beach House", "Depression Cherry", UUID(uuidString: "25a575ec-570f-4a27-9bd6-634026add2a7"), Self.artworkReleaseMBID),
        ]
        let tracks = rows.enumerated().map { index, row in
            PlaylistTrack(
                position: index + 1,
                recording: Recording(
                    identity: .init(mbid: row.3, msid: nil),
                    title: row.0,
                    artistName: row.1,
                    artistMBIDs: [],
                    releaseTitle: row.2,
                    releaseMBID: row.4,
                    releaseGroupMBID: nil,
                    artworkReleaseMBID: row.4,
                    durationMilliseconds: index.isMultiple(of: 2) ? 198_000 + index * 3_000 : nil,
                    source: "LB Radio"
                ),
                addedAt: nil,
                addedBy: nil
            )
        }
        return RadioMix(
            options: options,
            title: "Familiar corners, new turns",
            annotation: "A late-night mix drawn from your listening history and nearby artists.",
            feedback: [
                "Using all-time statistics for visual-radio.",
                "Easy mode favors the most relevant recordings in the source.",
            ],
            tracks: tracks,
            metadataEnrichmentFailed: false,
            generatedAt: .now
        )
    }
}

private struct VisualQAPopularityProvider: PopularityProviding {
    func popularity(for entity: PopularityEntity) async throws -> GlobalPopularity {
        await Task.yield()
        return GlobalPopularity(
            entity: entity,
            totalListenCount: 2_418_731,
            totalUserCount: 148_206
        )
    }
}

private struct VisualQAPopularityListeningProvider: ListeningProvider {
    private static let artistMBID = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
    private static let recordingMBID = UUID(uuidString: "39ad19e5-c0b0-454a-985b-201fb92898a0")!

    func validateToken() async throws -> String { "visual-popularity" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 48_271 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
        [.init(mbid: Self.artistMBID, name: "Alvvays", listenCount: 1_283)]
    }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
        [
            .init(
                mbid: Self.recordingMBID,
                releaseMBID: nil,
                title: "After the Earthquake",
                artistName: "Alvvays",
                artistMBIDs: [Self.artistMBID],
                releaseTitle: "Blue Rev",
                listenCount: 96
            ),
        ]
    }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .now, buckets: [])
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
}

private struct VisualQAHistoryProvider: ListeningProvider {
    private static let artworkReleaseMBID = UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!
    private static let titles = [
        "Night Drive", "Wildflower", "Parallel Lines", "Between the Bars",
        "Soft Focus", "Silver Lining", "Afterimage", "Northbound",
        "Quiet Hours", "All My Friends", "Blue Rev",
        "Everything We Heard Through the Open Windows on the Long Way Home",
    ]
    private static let artists = ["The Marías", "Alvvays", "Japanese Breakfast", "Radiohead"]

    func validateToken() async throws -> String { "visual-history" }

    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
        if after != nil, let before {
            return (0 ..< 12).map { index in
                Self.makeListen(
                    index: index + 30,
                    listenedAt: before.addingTimeInterval(-1_800 - Double(index * 2_820))
                )
            }
        }
        guard before == nil else { return [] }
        return Self.makeListens(around: .now, count: 22)
    }

    func playingNow(username: String) async throws -> Listen? {
        Self.makeListen(index: 22, listenedAt: .now, isPlayingNow: true)
    }

    func listenCount(username: String) async throws -> Int { 48_271 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .now, buckets: [])
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    private static func makeListens(around newest: Date, count: Int) -> [Listen] {
        (0 ..< count).map { index in
            let dayOffset = index < 7 ? 0 : (index < 15 ? 1 : 2)
            let minuteOffset = (index * 47) % 360
            let listenedAt = Calendar.autoupdatingCurrent.date(
                byAdding: DateComponents(day: -dayOffset, minute: -minuteOffset),
                to: newest
            ) ?? newest.addingTimeInterval(TimeInterval(-index * 2_820))
            return makeListen(index: index, listenedAt: listenedAt)
        }
        .sorted { $0.listenedAt > $1.listenedAt }
    }

    private static func makeListen(index: Int, listenedAt: Date, isPlayingNow: Bool = false) -> Listen {
        let msid = UUID(uuidString: String(format: "70000000-0000-0000-0000-%012x", index + 1))
        let artist = artists[index % artists.count]
        return Listen(
            recording: Recording(
                identity: .init(mbid: nil, msid: msid),
                title: titles[index % titles.count],
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: index.isMultiple(of: 3) ? "Listening Room" : "Midnight Editions",
                releaseMBID: artworkReleaseMBID,
                releaseGroupMBID: nil,
                artworkReleaseMBID: artworkReleaseMBID,
                durationMilliseconds: 180_000 + index * 1_700,
                source: index.isMultiple(of: 2) ? "Apple Music" : "Spotify"
            ),
            listenedAt: listenedAt,
            insertedAt: listenedAt.addingTimeInterval(3),
            isPlayingNow: isPlayingNow
        )
    }
}

private struct VisualQATasteProvider: ListeningProvider {
    private static let artistMBIDs = [
        UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!,
        UUID(uuidString: "6c0b31f3-2e41-4d70-bd16-5fa8551bd59b")!,
        UUID(uuidString: "a1d4c987-9c07-4c71-8f75-6505e2e8f554")!,
    ]
    private static let releaseMBID = UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!

    func validateToken() async throws -> String { "visual-taste" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 48_271 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
        [
            .init(mbid: Self.artistMBIDs[0], name: "Alvvays", listenCount: 1_283),
            .init(mbid: Self.artistMBIDs[1], name: "Japanese Breakfast", listenCount: 947),
            .init(mbid: Self.artistMBIDs[2], name: "The Marías", listenCount: 781),
        ]
    }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] {
        [
            .init(mbid: Self.releaseMBID, name: "Blue Rev", artistName: "Alvvays", artistMBIDs: [Self.artistMBIDs[0]], listenCount: 423),
            .init(mbid: nil, name: "Jubilee", artistName: "Japanese Breakfast", artistMBIDs: [Self.artistMBIDs[1]], listenCount: 287),
        ]
    }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
        [
            .init(mbid: nil, releaseMBID: Self.releaseMBID, title: "After the Earthquake", artistName: "Alvvays", artistMBIDs: [Self.artistMBIDs[0]], releaseTitle: "Blue Rev", listenCount: 96),
            .init(mbid: nil, releaseMBID: nil, title: "Be Sweet", artistName: "Japanese Breakfast", artistMBIDs: [Self.artistMBIDs[1]], releaseTitle: "Jubilee", listenCount: 83),
        ]
    }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        let now = Date.now
        return .init(
            period: period,
            from: now.addingTimeInterval(-7 * 86_400),
            to: now,
            lastUpdated: now,
            buckets: [
                .init(label: "Mon", from: now.addingTimeInterval(-7 * 86_400), to: now, listenCount: 112),
                .init(label: "Tue", from: now.addingTimeInterval(-6 * 86_400), to: now, listenCount: 176),
                .init(label: "Wed", from: now.addingTimeInterval(-5 * 86_400), to: now, listenCount: 94),
                .init(label: "Thu", from: now.addingTimeInterval(-4 * 86_400), to: now, listenCount: 203),
                .init(label: "Fri", from: now.addingTimeInterval(-3 * 86_400), to: now, listenCount: 138),
                .init(label: "Sat", from: now.addingTimeInterval(-2 * 86_400), to: now, listenCount: 232),
                .init(label: "Sun", from: now.addingTimeInterval(-86_400), to: now, listenCount: 156),
            ]
        )
    }
    func dailyActivity(username: String, period: ListeningActivityPeriod) async throws -> DailyActivity? {
        let values = Dictionary(uniqueKeysWithValues: ListeningWeekday.allCases.map { weekday in
            (weekday.rawValue, (0 ..< 24).map { hour in
                DailyActivity.Hour(hour: hour, listenCount: tasteCount(weekday: weekday, hour: hour))
            })
        })
        return DailyActivity(period: period, from: .now.addingTimeInterval(-7 * 86_400), to: .now, lastUpdated: .now, dailyActivity: values)
    }
    func eraActivity(username: String, period: ListeningActivityPeriod) async throws -> EraActivity? {
        EraActivity(
            period: period,
            from: .now.addingTimeInterval(-365 * 86_400),
            to: .now,
            lastUpdated: .now,
            years: [
                .init(year: 1967, listenCount: 12),
                .init(year: 1971, listenCount: 41),
                .init(year: 1977, listenCount: 67),
                .init(year: 1983, listenCount: 54),
                .init(year: 1989, listenCount: 88),
                .init(year: 1994, listenCount: 132),
                .init(year: 1997, listenCount: 176),
                .init(year: 2001, listenCount: 119),
                .init(year: 2007, listenCount: 143),
                .init(year: 2011, listenCount: 157),
                .init(year: 2018, listenCount: 214),
                .init(year: 2020, listenCount: 189),
                .init(year: 2022, listenCount: 268),
                .init(year: 2024, listenCount: 231),
                .init(year: 2025, listenCount: 204),
            ]
        )
    }
    func artistEvolutionActivity(
        username: String,
        period: ListeningActivityPeriod
    ) async throws -> ArtistEvolutionActivity? {
        let artistNames = ["Alvvays", "Japanese Breakfast", "The Marías", "Mitski", "Men I Trust"]
        let timeUnits: [String]
        switch period {
        case .thisWeek, .lastWeek:
            timeUnits = ListeningWeekday.allCases.map(\.rawValue)
        case .thisMonth, .lastMonth:
            timeUnits = (1 ... 31).map(String.init)
        case .thisYear, .lastYear:
            timeUnits = ArtistEvolutionActivity.monthNames
        case .allTime:
            timeUnits = (2011 ... 2026).map(String.init)
        }
        let yearCounts = [
            [34, 46, 39, 61, 72, 58, 84, 91, 75, 67, 88, 102],
            [21, 30, 42, 37, 55, 69, 63, 76, 82, 70, 61, 79],
            [18, 26, 19, 34, 41, 53, 49, 57, 46, 64, 72, 68],
            [28, 22, 31, 40, 36, 29, 45, 51, 59, 48, 43, 55],
            [12, 17, 24, 20, 29, 38, 35, 42, 50, 47, 58, 62],
        ]
        let rows = artistNames.enumerated().flatMap { artistIndex, name in
            timeUnits.enumerated().map { unitIndex, timeUnit in
                let listenCount: Int
                if period == .thisYear || period == .lastYear {
                    listenCount = yearCounts[artistIndex][unitIndex]
                } else {
                    listenCount = 10
                        + ((unitIndex * (artistIndex + 2) * 7 + artistIndex * 11) % 48)
                        + unitIndex * 2
                }
                return ArtistEvolutionActivity.Row(
                    timeUnit: timeUnit,
                    artistMBID: artistIndex < Self.artistMBIDs.count ? Self.artistMBIDs[artistIndex] : nil,
                    artistName: name,
                    listenCount: listenCount
                )
            }
        }
        return ArtistEvolutionActivity(
            period: period,
            from: period == .allTime
                ? Calendar(identifier: .gregorian).date(from: DateComponents(year: 2011, month: 1, day: 1))!
                : .now.addingTimeInterval(-365 * 86_400),
            to: .now,
            lastUpdated: .now,
            rows: rows
        )
    }
    func genreActivity(username: String, period: ListeningActivityPeriod) async throws -> GenreActivity? {
        let now = Date.now
        let rows: [GenreActivity.Row] = [
            .init(genre: "Ambient", hour: 0, listenCount: 42),
            .init(genre: "Electronic", hour: 0, listenCount: 31),
            .init(genre: "Dream Pop", hour: 2, listenCount: 38),
            .init(genre: "Shoegaze", hour: 3, listenCount: 29),
            .init(genre: "Indie Pop", hour: 7, listenCount: 51),
            .init(genre: "Alternative Rock", hour: 8, listenCount: 37),
            .init(genre: "Art Pop", hour: 10, listenCount: 28),
            .init(genre: "Neo-Psychedelia", hour: 12, listenCount: 46),
            .init(genre: "Indie Rock", hour: 14, listenCount: 63),
            .init(genre: "Synthpop", hour: 16, listenCount: 35),
            .init(genre: "Dream Pop", hour: 18, listenCount: 71),
            .init(genre: "Indie Pop", hour: 20, listenCount: 58),
            .init(genre: "Electronic", hour: 22, listenCount: 49),
            .init(genre: "Ambient", hour: 23, listenCount: 33),
        ]
        return GenreActivity(
            period: period,
            from: now.addingTimeInterval(-30 * 86_400),
            to: now,
            lastUpdated: now,
            rows: rows
        )
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

    private func tasteCount(weekday: ListeningWeekday, hour: Int) -> Int {
        let weekdayOffset = ListeningWeekday.allCases.firstIndex(of: weekday) ?? 0
        if (19 ... 23).contains(hour) { return 5 + ((weekdayOffset * 3 + hour) % 12) }
        if (12 ... 15).contains(hour) { return 1 + ((weekdayOffset + hour) % 5) }
        return (weekdayOffset + hour).isMultiple(of: 11) ? 2 : 0
    }
}
#endif

private struct MiniListenBar: View {
    let listen: Listen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ArtworkView(url: listen.recording.artworkURL, title: listen.recording.title, cornerRadius: 7)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(listen.recording.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(listen.recording.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "waveform")
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.variableColor.iterative)
                Image(systemName: "chevron.up")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playing now: \(listen.recording.title) by \(listen.recording.artistName)")
    }
}
