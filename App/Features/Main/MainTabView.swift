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
        if ProcessInfo.processInfo.arguments.contains("-brainz-history-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-history-day-demo") {
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
        if ProcessInfo.processInfo.arguments.contains("-brainz-release-detail-demo") {
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
                    || ProcessInfo.processInfo.arguments.contains("-brainz-history-day-demo") {
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

private struct VisualQAHistoryProvider: ListeningProvider {
    private static let artworkReleaseMBID = UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!
    private static let titles = [
        "Night Drive", "Wildflower", "Parallel Lines", "Between the Bars",
        "Soft Focus", "Silver Lining", "Afterimage", "Northbound",
        "Quiet Hours", "All My Friends", "Blue Rev", "Daydreaming",
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
