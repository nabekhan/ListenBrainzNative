import SwiftUI

struct RecommendationsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case tracks
        case playlists

        var id: Self { self }
        var title: String { self == .tracks ? "Tracks" : "Playlists" }
    }

    let account: Account
    @Bindable var listeningModel: ListeningModel
    @State private var model: RecommendationsModel
    @State private var selection: Section = .tracks

    init(account: Account, listeningModel: ListeningModel) {
        self.account = account
        _listeningModel = Bindable(wrappedValue: listeningModel)
        _model = State(initialValue: RecommendationsModel(account: account))
        #if DEBUG
        let initialSelection: Section = ProcessInfo.processInfo.arguments.contains(
            "-brainz-open-recommendation-playlists"
        ) ? .playlists : .tracks
        _selection = State(initialValue: initialSelection)
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
        .navigationBarTitleDisplayMode(.large)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Made from your listening history", systemImage: "wand.and.stars")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            Text("Recommendations and generated playlists from ListenBrainz, with the music—not the algorithm—front and center.")
                .font(.subheadline)
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

            LazyVStack(spacing: 0) {
                ForEach(model.recommendations) { recommendation in
                    NavigationLink(value: recommendation.recording) {
                        RecommendationRow(recommendation: recommendation)
                    }
                    .buttonStyle(.plain)
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

    private var recommendationSubtitle: String {
        var components: [String] = []
        if model.totalCount > 0 {
            components.append("\(model.totalCount.formatted()) available")
        }
        if let lastUpdated = model.lastUpdated {
            components.append("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
        }
        return components.joined(separator: " · ")
    }

    private func loading(_ title: String) -> some View {
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
        title: String,
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
        guard let date = recommendation.lastListenedAt else { return "New to your history" }
        return "Last heard \(date.formatted(.relative(presentation: .named)))"
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
        case "weekly-jams": "Weekly Jams"
        case "weekly-exploration": "Weekly Exploration"
        case "daily-jams": "Daily Jams"
        case let value? where value.hasPrefix("top-discoveries-of-"): "Top Discoveries"
        case let value? where value.hasPrefix("top-missed-recordings-of-"): "Missed Tracks"
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
            return "Available \(expiresAt.formatted(.relative(presentation: .named)))"
        }
        if let updated = playlist.lastModifiedAt {
            return "Updated \(updated.formatted(.relative(presentation: .named)))"
        }
        return "By \(playlist.creator)"
    }
}
