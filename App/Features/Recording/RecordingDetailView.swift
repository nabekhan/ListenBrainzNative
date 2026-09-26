import SwiftUI

struct RecordingDetailView: View {
    let recording: Recording
    @Bindable var model: ListeningModel
    @Environment(PinsModel.self) private var pins
    @State private var shareModel: RecordingShareModel
    @State private var isPinEditorPresented = false
    @State private var isPersonalRecommendationPresented = false
    @State private var didPresentRecommendationPreview = false
    @State private var pinBlurb = ""
    @State private var isPlaylistAddPresented = false
    @State private var isLogListenPresented = false

    init(recording: Recording, model: ListeningModel) {
        self.recording = recording
        _model = Bindable(wrappedValue: model)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-brainz-recording-share-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-recording-feedback-demo")
        {
            _shareModel = State(initialValue: RecordingShareModel(
                account: Account(username: "visual-qa", token: "visual-qa"),
                recording: recording,
                provider: RecordingSharePreviewProvider(),
                socialCache: UserSocialCache(),
                feedCache: EntityDetailCache()
            ))
            return
        }
        #endif
        _shareModel = State(initialValue: RecordingShareModel(account: model.account, recording: recording))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                hero
                feedbackControls
                pinControls
                metadata
                popularity
                reviews
                relatedListens
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background {
            AppTheme.artworkGradient(seed: recording.title)
                .opacity(0.12)
                .ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
        }
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await pins.load() }
        .onAppear {
            #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("-brainz-open-personal-recommendation"),
                  !didPresentRecommendationPreview
            else { return }
            didPresentRecommendationPreview = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                shareModel.preparePersonalRecommendation()
                isPersonalRecommendationPresented = true
            }
            #endif
        }
        .sheet(isPresented: $isPersonalRecommendationPresented) {
            PersonalRecommendationSheet(model: shareModel)
        }
        .sheet(isPresented: $isPlaylistAddPresented) {
            if let mbid = recording.identity.mbid {
                PlaylistAddSheet(account: model.account, recordingMBID: mbid)
            }
        }
        .sheet(isPresented: $isLogListenPresented) { LogListenSheet(account: model.account, recording: recording) }
        .alert(
            shareModel.notice?.kind == .confirmation ? "Recommendation Shared" : "Couldn’t Share Recommendation",
            isPresented: Binding(
                get: { !isPersonalRecommendationPresented && shareModel.notice != nil },
                set: { if !$0 { shareModel.dismissNotice() } }
            )
        ) {
            Button("OK", role: .cancel) { shareModel.dismissNotice() }
        } message: {
            Text(shareModel.notice?.message ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                recommendationMenu
            }
            if let mbid = recording.identity.mbid {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: URL(string: "https://musicbrainz.org/recording/\(mbid.uuidString)")!) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open in MusicBrainz")
                }
            }
        }
    }

    private var recommendationMenu: some View {
        Menu {
            Button { isLogListenPresented = true } label: {
                Label("Log a listen", systemImage: "plus.circle")
            }
            .disabled(!model.account.isAuthenticated)

            Button {
                isPlaylistAddPresented = true
            } label: {
                Label("Add to playlist", systemImage: "text.badge.plus")
            }
            .disabled(!canAddToPlaylist)

            Button {
                Task { await shareModel.recommendToFollowers() }
            } label: {
                Label("Recommend to followers", systemImage: "paperplane.fill")
            }
            .disabled(!shareModel.canRecommend || shareModel.isSubmitting)

            Button {
                shareModel.preparePersonalRecommendation()
                isPersonalRecommendationPresented = true
            } label: {
                Label("Recommend personally", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(!shareModel.canRecommend || shareModel.isSubmitting)
        } label: {
            if shareModel.isSubmitting {
                ProgressView()
            } else {
                Image(systemName: "paperplane.circle")
            }
        }
        .accessibilityLabel("Recording actions")
        .accessibilityHint(
            model.account.isAuthenticated
                ? "Log a listen, add this recording to a playlist, or share it through ListenBrainz"
                : "Sign in to log or share this recording"
        )
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ArtworkView(url: recording.artworkURL, title: recording.title, cornerRadius: 22)
                .frame(maxWidth: 320)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
                .padding(.top, 12)

            VStack(spacing: 5) {
                Text(recording.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(recording.artistName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.center)
                if let release = recording.releaseTitle {
                    if let seed = ReleaseSeed(recording: recording) {
                        NavigationLink(value: seed) {
                            Label(release, systemImage: "square.stack")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityHint("Open release details")
                    } else {
                        Text(release)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ExternalMediaDestinationButton(links: recording.externalMediaLinks)
            }
        }
    }

    private var canAddToPlaylist: Bool {
        PlaylistAddSheetModel.canPresent(
            account: model.account,
            recordingMBID: recording.identity.mbid
        )
    }

    private var feedbackControls: some View {
        HStack(spacing: 14) {
            feedbackButton(.love, title: "Love", systemImage: "heart.fill")
            feedbackButton(.hate, title: "Hate", systemImage: "hand.thumbsdown.fill")
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 13))
        }
    }

    private var pinControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.account.isAuthenticated {
                Label("Sign in with a token to pin this recording", systemImage: "lock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if recording.identity.mbid == nil && recording.identity.msid == nil {
                Label("This recording needs a MusicBrainz or MessyBrainz ID before it can be pinned", systemImage: "questionmark.diamond")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if pins.phase == .idle || pins.phase == .loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking your current pin…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if case .failed = pins.phase {
                Button { Task { await pins.refresh() } } label: {
                    Label("Retry pin status", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 13))
            } else if isCurrentPin {
                Button(role: .destructive) { Task { await pins.unpin() } } label: {
                    Label("Unpin recording", systemImage: "pin.slash")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 13))
                .disabled(!pins.canMutate)
            } else {
                Button { pinBlurb = ""; isPinEditorPresented = true } label: {
                    Label(pins.currentPin == nil ? "Pin recording" : "Replace pinned recording", systemImage: "pin.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 13))
                .tint(AppTheme.accent)
                .disabled(!pins.canMutate)
            }
        }
        .sheet(isPresented: $isPinEditorPresented) {
            NavigationStack {
                PinBlurbEditor(title: "Pin recording", blurb: $pinBlurb) {
                    Task { await pins.pin(recording, blurb: pinBlurb) }
                }
            }
        }
    }

    private var isCurrentPin: Bool {
        guard let current = pins.currentPin else { return false }
        if let mbid = recording.identity.mbid,
           current.recording.identity.mbid == mbid { return true }
        if let msid = recording.identity.msid,
           current.recording.identity.msid == msid { return true }
        return false
    }

    @ViewBuilder
    private func feedbackButton(
        _ value: RecordingFeedback,
        title: LocalizedStringResource,
        systemImage: String
    ) -> some View {
        let selected = model.feedback[recording.id] == value
        if selected {
            feedbackAction(value, title: title, systemImage: systemImage, selected: true)
                .buttonStyle(.borderedProminent)
        } else {
            feedbackAction(value, title: title, systemImage: systemImage, selected: false)
                .buttonStyle(.bordered)
        }
    }

    private func feedbackAction(
        _ value: RecordingFeedback,
        title: LocalizedStringResource,
        systemImage: String,
        selected: Bool
    ) -> some View {
        Button {
            Task { await model.setFeedback(selected ? .none : value, for: recording) }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonBorderShape(.roundedRectangle(radius: 13))
        .tint(value == .hate ? .secondary : AppTheme.accent)
        .accessibilityIdentifier(
            value == .love ? "recording-feedback-love" : "recording-feedback-hate"
        )
        .accessibilityValue(
            selected ? String(localized: "Selected") : String(localized: "Not selected")
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "ListenBrainz details")
            detailRow("Identity", value: identityLabel, icon: "link")
            if let duration = recording.durationMilliseconds {
                detailRow("Duration", value: durationLabel(duration), icon: "timer")
            }
            if let source = recording.source {
                detailRow("Submitted by", value: source, icon: "dot.radiowaves.left.and.right")
            }
            detailRow(
                "Metadata",
                value: recording.identity.mbid == nil
                    ? String(localized: "Unmapped recording")
                    : String(localized: "MusicBrainz mapped"),
                icon: recording.identity.mbid == nil ? "questionmark.diamond" : "checkmark.seal.fill"
            )
        }
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var popularity: some View {
        if let mbid = recording.identity.mbid {
            PopularitySummaryView(entity: PopularityEntity(kind: .recording, mbid: mbid))
        }
    }

    @ViewBuilder
    private var reviews: some View {
        if let mbid = recording.identity.mbid {
            CritiqueBrainzReviewSummaryView(entity: .init(kind: .recording, mbid: mbid))
        }
    }

    @ViewBuilder
    private var relatedListens: some View {
        let listens = model.snapshot.recentListens.filter { item in
            if let mbid = recording.identity.mbid {
                return item.recording.identity.mbid == mbid
            }
            if let msid = recording.identity.msid {
                return item.recording.identity.msid == msid
            }
            return item.recording.title == recording.title && item.recording.artistName == recording.artistName
        }
        if !listens.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Recent plays", subtitle: "In the currently loaded history")
                ForEach(listens.prefix(8)) { listen in
                    ListenRow(listen: listen, showsDate: true)
                }
            }
        }
    }

    private func detailRow(_ label: LocalizedStringResource, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).textSelection(.enabled)
            }
            Spacer()
        }
    }

    private var identityLabel: String {
        if let mbid = recording.identity.mbid { return String(localized: "Recording MBID · \(mbid.uuidString)") }
        if let msid = recording.identity.msid { return String(localized: "Recording MSID · \(msid.uuidString)") }
        return String(localized: "No recording identifier")
    }

    private var shareText: String {
        String(localized: "\(recording.title) by \(recording.artistName)")
    }

    private func durationLabel(_ milliseconds: Int) -> String {
        let seconds = max(milliseconds, 0) / 1_000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
