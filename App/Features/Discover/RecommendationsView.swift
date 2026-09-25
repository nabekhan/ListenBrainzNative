import SwiftUI

struct RecommendationsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case tracks
        case playlists

        var id: Self { self }
        var title: String { self == .tracks ? String(localized: "Tracks") : String(localized: "Playlists") }
    }

    let account: Account
    @Bindable var listeningModel: ListeningModel
    @State private var model: RecommendationsModel
    @State private var selection: Section = .tracks
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(account: Account, listeningModel: ListeningModel) {
        self.account = account
        _listeningModel = Bindable(wrappedValue: listeningModel)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-brainz-recommendations-demo") {
            _model = State(initialValue: RecommendationsModel(
                account: Account(username: "visual-qa", token: "visual-qa"),
                provider: RecommendationsPreviewProvider(),
                recordingCache: EntityDetailCache(),
                playlistCache: EntityDetailCache()
            ))
        } else {
            _model = State(initialValue: RecommendationsModel(account: account))
        }
        let initialSelection: Section = arguments.contains(
            "-brainz-open-recommendation-playlists"
        ) ? .playlists : .tracks
        _selection = State(initialValue: initialSelection)
        #else
        _model = State(initialValue: RecommendationsModel(account: account))
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                Picker("Recommendation type", selection: $selection) {
                    ForEach(Section.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                switch selection {
                case .tracks: tracksContent
                case .playlists: playlistsContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        .navigationTitle("For You")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .refreshable {
            switch selection {
            case .tracks: await model.refreshRecommendations()
            case .playlists: await model.refreshPlaylists()
            }
        }
        .task(id: selection) {
            switch selection {
            case .tracks: await model.loadRecommendations()
            case .playlists: await model.loadPlaylists()
            }
        }
        .mediaDestinations(model: listeningModel)
        .alert(
            "Couldn’t update recommendation feedback",
            isPresented: Binding(
                get: { model.feedbackActionError != nil },
                set: { if !$0 { model.feedbackActionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.feedbackActionError = nil }
        } message: {
            Text(model.feedbackActionError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Made from your listening history", systemImage: "wand.and.stars")
                .font((dynamicTypeSize.isAccessibilitySize ? Font.caption : .headline).weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(dynamicTypeSize.isAccessibilitySize
                ? "Tracks and playlists shaped by your ListenBrainz history."
                : "Recommendations and generated playlists from ListenBrainz, with the music—not the algorithm—front and center.")
                .font(dynamicTypeSize.isAccessibilitySize ? .footnote : .subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.heroGradient.opacity(0.13), in: .rect(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var tracksContent: some View {
        switch model.recordingPhase {
        case .idle, .loading:
            loading("Finding tracks for you…")
        case .unavailable:
            ContentUnavailableView(
                "Still learning your taste",
                systemImage: "sparkles",
                description: Text("ListenBrainz has not generated track recommendations for this profile yet. New listening history can take time to appear here.")
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        case let .failed(message):
            failure(title: "Recommendations unavailable", message: message) {
                await model.refreshRecommendations()
            }
        case .refreshing, .ready:
            if model.recommendations.isEmpty {
                ContentUnavailableView(
                    "No recommendations yet",
                    systemImage: "music.note",
                    description: Text("Check back after ListenBrainz processes more of your listening history.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                recommendationList
            }
        }
    }

    private var recommendationList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Recommended tracks",
                subtitle: recommendationSubtitle
            )

            if let message = model.recordingRefreshMessage {
                inlineWarning(message) { await model.refreshRecommendations() }
            }

            if !model.account.isAuthenticated {
                Label(
                    "Sign in with a token to tune these recommendations.",
                    systemImage: "lock.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            LazyVStack(spacing: 0) {
                ForEach(model.recommendations) { recommendation in
                    VStack(spacing: 0) {
                        NavigationLink(value: recommendation.recording) {
                            RecommendationRow(recommendation: recommendation)
                        }
                        .buttonStyle(.plain)

                        if model.account.isAuthenticated {
                            Divider().padding(.leading, 66)
                            RecommendationFeedbackControl(
                                selected: model.feedback(for: recommendation),
                                isUpdating: model.isUpdatingFeedback(for: recommendation)
                            ) { rating in
                                Task { await model.setFeedback(rating, for: recommendation) }
                            }
                        }
                    }
                    .task {
                        guard recommendation.id == model.recommendations.last?.id else { return }
                        await model.loadMoreRecommendations()
                    }

                    if recommendation.id != model.recommendations.last?.id {
                        Divider().padding(.leading, 78)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))

            if model.isLoadingMore {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading more recommendations…")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else if let message = model.loadMoreError {
                inlineWarning(message) { await model.loadMoreRecommendations() }
            }
        }
    }

    @ViewBuilder
    private var playlistsContent: some View {
        switch model.playlistPhase {
        case .idle, .loading:
            loading("Loading playlists made for you…")
        case .unavailable:
            EmptyView()
        case let .failed(message):
            failure(title: "Playlists unavailable", message: message) {
                await model.refreshPlaylists()
            }
        case .refreshing, .ready:
            if model.playlists.isEmpty {
                ContentUnavailableView(
                    "No generated playlists yet",
                    systemImage: "music.note.list",
                    description: Text("Weekly Jams and exploration playlists will appear when ListenBrainz has enough recent listening data.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                playlistList
            }
        }
    }

    private var playlistList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Created for you",
                subtitle: "Generated playlists you can inspect track by track"
            )

            if let message = model.playlistRefreshMessage {
                inlineWarning(message) { await model.refreshPlaylists() }
            }

            LazyVStack(spacing: 12) {
                ForEach(model.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist, viewer: account)
                    } label: {
                        RecommendationPlaylistCard(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recommendationSubtitle: LocalizedStringResource? {
        let count = model.totalCount
        let updated = model.lastUpdated?.formatted(.relative(presentation: .named))
        switch (count > 0, updated) {
        case (true, let updated?):
            return "\(count) available · Updated \(updated)"
        case (true, nil):
            return "\(count) available"
        case (false, let updated?):
            return "Updated \(updated)"
        case (false, nil):
            return nil
        }
    }

    private func loading(_ title: LocalizedStringResource) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func failure(
        title: LocalizedStringResource,
        message: String,
        retry: @escaping @Sendable () async -> Void
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await retry() } }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func inlineWarning(
        _ message: String,
        retry: @escaping @Sendable () async -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Retry") { Task { await retry() } }
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct RecommendationRow: View {
    let recommendation: RecommendedRecording

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                url: recommendation.recording.artworkURL,
                title: recommendation.recording.title,
                cornerRadius: 10
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.recording.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(recommendation.recording.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(discoveryContext)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open recording details")
    }

    private var discoveryContext: String {
        guard let date = recommendation.lastListenedAt else { return String(localized: "New to your history") }
        return String(localized: "Last heard \(date.formatted(.relative(presentation: .named)))")
    }
}

private struct RecommendationFeedbackControl: View {
    let selected: RecommendationRating?
    let isUpdating: Bool
    let action: (RecommendationRating) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) {
                    status
                    choices.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 8) {
                    status
                    Spacer(minLength: 4)
                    choices
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var status: some View {
        HStack(spacing: 7) {
            if isUpdating {
                ProgressView().controlSize(.small)
            }
            Text(selected?.confirmationTitle ?? String(localized: "Tune this pick"))
                .font(.caption.weight(.medium))
                .foregroundStyle(selected == nil ? Color.secondary : Color.primary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var choices: some View {
        HStack(spacing: 0) {
            ForEach(RecommendationRating.allCases, id: \.self) { rating in
                let isSelected = selected == rating
                Button {
                    action(rating)
                } label: {
                    Image(systemName: rating.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 34)
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .background(
                            isSelected ? rating.tint : Color.secondary.opacity(0.09),
                            in: .capsule
                        )
                        .padding(.horizontal, 3)
                        .padding(.vertical, 5)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .accessibilityLabel("\(rating.title) this recommendation")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint(isSelected ? "Double tap to clear" : "Double tap to save")
            }
        }
    }
}

private extension RecommendationRating {
    var title: String {
        switch self {
        case .hate: String(localized: "Hate")
        case .dislike: String(localized: "Dislike")
        case .like: String(localized: "Like")
        case .love: String(localized: "Love")
        }
    }

    var confirmationTitle: String {
        switch self {
        case .hate: String(localized: "Marked as hated")
        case .dislike: String(localized: "Marked as disliked")
        case .like: String(localized: "Marked as liked")
        case .love: String(localized: "Marked as loved")
        }
    }

    var systemImage: String {
        switch self {
        case .hate: "hand.thumbsdown.fill"
        case .dislike: "hand.thumbsdown"
        case .like: "hand.thumbsup"
        case .love: "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .hate: .red
        case .dislike: .orange
        case .like: AppTheme.accent
        case .love: .pink
        }
    }
}

private struct RecommendationPlaylistCard: View {
    let playlist: SearchPlaylist

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.artworkGradient(seed: playlist.title))
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text(kindTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if kindTitle != playlist.title {
                    Text(playlist.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open playlist")
    }

    private var kindTitle: String {
        switch playlist.recommendationType {
        case "weekly-jams": String(localized: "Weekly Jams")
        case "weekly-exploration": String(localized: "Weekly Exploration")
        case "daily-jams": String(localized: "Daily Jams")
        case let value? where value.hasPrefix("top-discoveries-of-"): String(localized: "Top Discoveries")
        case let value? where value.hasPrefix("top-missed-recordings-of-"): String(localized: "Missed Tracks")
        default: playlist.title
        }
    }

    private var symbol: String {
        switch playlist.recommendationType {
        case "weekly-exploration": "safari.fill"
        case let value? where value.hasPrefix("top-discoveries-of-"): "sparkles"
        case let value? where value.hasPrefix("top-missed-recordings-of-"): "arrow.uturn.backward.circle.fill"
        default: "music.note.list"
        }
    }

    private var detailText: String {
        if let expiresAt = playlist.expiresAt, expiresAt > .now {
            return String(localized: "Available \(expiresAt.formatted(.relative(presentation: .named)))")
        }
        if let updated = playlist.lastModifiedAt {
            return String(localized: "Updated \(updated.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "By \(playlist.creator)")
    }
}

#if DEBUG
private actor RecommendationsPreviewProvider: RecommendationsProviding {
    private let values: [RecommendedRecording]
    private var feedback: [UUID: RecommendationRating]

    init() {
        let first = Self.recording(
            mbid: "526bd613-fddd-4bd6-9137-ab709ac74cab",
            title: "Midnight City",
            artist: "M83",
            release: "Hurry Up, We’re Dreaming",
            score: 9.84,
            lastListenedAt: nil
        )
        let second = Self.recording(
            mbid: "a6081bc1-2a76-4984-b21f-38bc3dcca3a5",
            title: "A Very Long Song Title That Still Needs Room to Breathe",
            artist: "The Listening Historians",
            release: "Signals from the Archive",
            score: 8.72,
            lastListenedAt: Date.now.addingTimeInterval(-21 * 24 * 60 * 60)
        )
        let third = Self.recording(
            mbid: "2fb127aa-3181-4f36-8a7d-d59f66e85360",
            title: "Everything in Its Right Place",
            artist: "Radiohead",
            release: "Kid A",
            score: 8.31,
            lastListenedAt: Date.now.addingTimeInterval(-180 * 24 * 60 * 60)
        )
        values = [first, second, third]
        feedback = [
            first.recording.identity.mbid!: .love,
            second.recording.identity.mbid!: .dislike,
        ]
    }

    func recordingRecommendations(
        username: String,
        offset: Int,
        count: Int
    ) async throws -> RecordingRecommendationPage? {
        let page = Array(values.dropFirst(offset).prefix(count))
        return RecordingRecommendationPage(
            username: username,
            lastUpdated: .now.addingTimeInterval(-45 * 60),
            offset: offset,
            serverCount: page.count,
            totalCount: values.count,
            recommendations: page
        )
    }

    func recommendationFeedback(
        username: String,
        recordingMBIDs: [UUID]
    ) async throws -> [UUID: RecommendationRating] {
        feedback.filter { recordingMBIDs.contains($0.key) }
    }

    func setRecommendationFeedback(
        _ rating: RecommendationRating?,
        recordingMBID: UUID
    ) async throws {
        try await Task.sleep(for: .milliseconds(350))
        feedback[recordingMBID] = rating
    }

    func recommendationPlaylists(username: String) async throws -> [SearchPlaylist] {
        []
    }

    private static func recording(
        mbid: String,
        title: String,
        artist: String,
        release: String,
        score: Double,
        lastListenedAt: Date?
    ) -> RecommendedRecording {
        RecommendedRecording(
            recording: Recording(
                identity: .init(mbid: UUID(uuidString: mbid), msid: nil),
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: release,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            score: score,
            lastListenedAt: lastListenedAt
        )
    }
}
#endif
