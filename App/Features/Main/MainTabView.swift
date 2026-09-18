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
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-recommendations")
                    || ProcessInfo.processInfo.arguments.contains("-brainz-open-feed") {
                    selectedTab = .discover
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
    #endif
}

#if DEBUG
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
