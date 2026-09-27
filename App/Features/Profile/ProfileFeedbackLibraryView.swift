import SwiftUI

struct ProfileFeedbackLink: View {
    let username: String
    let isOwner: Bool
    @Bindable var listeningModel: ListeningModel

    private let provider: (any ProfileFeedbackProviding)?
    private let cache: EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage>

    init(
        username: String,
        isOwner: Bool,
        listeningModel: ListeningModel,
        provider: (any ProfileFeedbackProviding)? = nil,
        cache: EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage> = ProfileFeedbackCaches.pages
    ) {
        self.username = username
        self.isOwner = isOwner
        _listeningModel = Bindable(wrappedValue: listeningModel)
        self.provider = provider
        self.cache = cache
    }

    var body: some View {
        NavigationLink {
            ProfileFeedbackLibraryView(
                username: username,
                isOwner: isOwner,
                listeningModel: listeningModel,
                provider: provider,
                cache: cache
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.heroGradient, in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Loved & Hated")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(
                        isOwner
                            ? String(localized: "Review tracks you’ve rated on ListenBrainz")
                            : String(localized: "See track ratings from \(username)")
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(15)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            Text(
                isOwner
                    ? String(localized: "Opens your loved and hated tracks")
                    : String(localized: "Opens loved and hated tracks from \(username)")
            )
        )
    }
}

struct ProfileFeedbackLibraryView: View {
    let username: String
    let isOwner: Bool
    @Bindable var listeningModel: ListeningModel

    @State private var model: ProfileFeedbackModel
    @State private var selection: ProfileFeedbackCategory = .loved
    @State private var actionTask: Task<Void, Never>?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        username: String,
        isOwner: Bool,
        listeningModel: ListeningModel,
        provider: (any ProfileFeedbackProviding)? = nil,
        cache: EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage> = ProfileFeedbackCaches.pages,
        pageSize: Int = 25
    ) {
        self.username = username
        self.isOwner = isOwner
        _listeningModel = Bindable(wrappedValue: listeningModel)
        _model = State(
            initialValue: ProfileFeedbackModel(
                username: username,
                provider: provider,
                cache: cache,
                pageSize: pageSize
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !dynamicTypeSize.isAccessibilitySize {
                    hero
                }
                categoryPicker
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        .accessibilityIdentifier("feedback-library-screen")
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Loved & Hated")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .refreshable { await model.refresh(category: selection) }
        .task(id: selection) { await model.load(category: selection) }
        .onChange(of: selection) { previous, _ in
            actionTask?.cancel()
            actionTask = nil
            model.cancel(category: previous)
        }
        .onDisappear {
            actionTask?.cancel()
            actionTask = nil
            model.cancelAll()
        }
        .mediaDestinations(model: listeningModel)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    AppTheme.artworkGradient(seed: "feedback-\(username)"),
                    in: .rect(cornerRadius: 17, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(
                    isOwner
                        ? String(localized: "Your track ratings")
                        : String(localized: "Track ratings from \(username)")
                )
                .font(.headline)
                Text(
                    isOwner
                        ? String(localized: "Tracks you marked on ListenBrainz")
                        : String(localized: "Tracks this listener marked on ListenBrainz")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var categoryPicker: some View {
        Picker("Rating", selection: $selection) {
            Label("Loved", systemImage: "heart.fill")
                .tag(ProfileFeedbackCategory.loved)
            Label("Hated", systemImage: "hand.thumbsdown.fill")
                .tag(ProfileFeedbackCategory.hated)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("feedback-segment-picker")
    }

    @ViewBuilder
    private var content: some View {
        let state = model.state(for: selection)
        switch state.phase {
        case .idle, .loading:
            ProgressView(
                selection == .loved
                    ? String(localized: "Loading loved tracks…")
                    : String(localized: "Loading hated tracks…")
            )
                .frame(maxWidth: .infinity, minHeight: 260)
        case let .failed(message):
            ContentUnavailableView {
                Label("Ratings couldn’t load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { startAction { await model.refresh(category: selection) } }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        case .refreshing, .ready:
            if state.items.isEmpty {
                emptyState
            } else {
                feedbackList(state)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if selection == .loved {
            ContentUnavailableView(
                "No loved tracks yet",
                systemImage: "heart.slash",
                description: Text(
                    isOwner
                        ? String(localized: "Tracks you love on ListenBrainz will appear here.")
                        : String(localized: "This listener hasn’t loved any tracks yet.")
                )
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            ContentUnavailableView(
                "No hated tracks yet",
                systemImage: "hand.thumbsdown",
                description: Text(
                    isOwner
                        ? String(localized: "Tracks you hate on ListenBrainz will appear here.")
                        : String(localized: "This listener hasn’t hated any tracks yet.")
                )
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    private func feedbackList(_ state: ProfileFeedbackCategoryState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            feedbackHeader(state)

            if let message = state.refreshMessage {
                warning(message) { await model.refresh(category: selection) }
            }

            ForEach(state.items) { item in
                ProfileFeedbackRow(item: item)
            }

            if state.isLoadingMore {
                ProgressView("Loading more tracks…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if let message = state.loadMoreError {
                warning(message) { await model.loadMore(category: selection) }
            } else if state.hasMore {
                Button("Load more") { startAction { await model.loadMore(category: selection) } }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("feedback-load-more")
            }
        }
    }

    @ViewBuilder
    private func feedbackHeader(_ state: ProfileFeedbackCategoryState) -> some View {
        let title = selection == .loved
            ? String(localized: "Loved tracks")
            : String(localized: "Hated tracks")
        let count = String(localized: "Showing \(state.items.count) of \(state.totalCount)")

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                Text(count)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.bold())
                Spacer(minLength: 8)
                Text(count)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func warning(
        _ message: String,
        retry: @escaping @MainActor () async -> Void
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    warningMessage(message)
                    Button("Retry") { startAction(retry) }
                        .font(.footnote.weight(.semibold))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    warningMessage(message)
                    Spacer(minLength: 8)
                    Button("Retry") { startAction(retry) }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func warningMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func startAction(_ action: @escaping @MainActor () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { await action() }
    }
}

private struct ProfileFeedbackRow: View {
    let item: ProfileFeedbackItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if item.recording.identity.mbid != nil {
                NavigationLink(value: item.recording) {
                    rowContent(showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens recording details")
            } else {
                rowContent(showsDisclosure: false)
            }
        }
        .accessibilityIdentifier("feedback-row-\(identifierSuffix)")
    }

    private func rowContent(showsDisclosure: Bool) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    artwork(size: 76)
                    metadata
                    status
                }
            } else {
                HStack(spacing: 13) {
                    artwork(size: 64)
                    metadata
                    Spacer(minLength: 8)
                    status
                    if showsDisclosure {
                        Image(systemName: "chevron.forward")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(13)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func artwork(size: CGFloat) -> some View {
        ArtworkView(
            url: item.recording.artworkURL,
            title: item.recording.releaseTitle ?? item.recording.title,
            cornerRadius: 12
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.recording.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            Text(item.recording.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if let release = item.recording.releaseTitle, !release.isEmpty {
                Text(release)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
            if item.recording.identity.mbid == nil {
                Label("Details unavailable", systemImage: "link.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 5) {
            Label(
                item.category == .loved
                    ? String(localized: "Loved")
                    : String(localized: "Hated"),
                systemImage: item.category == .loved ? "heart.fill" : "hand.thumbsdown.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(item.category == .loved ? AppTheme.accent : .secondary)

            if let createdAt = item.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var identifierSuffix: String {
        switch item.id {
        case let .mbid(id): id.uuidString.lowercased()
        case let .msid(id): id.uuidString.lowercased()
        }
    }
}

#if DEBUG
enum ProfileFeedbackVisualState: Equatable {
    case populated
    case empty
    case failure
    case partialFailure
}

struct ProfileFeedbackLibraryVisualQAScreen: View {
    let state: ProfileFeedbackVisualState
    @State private var listeningModel: ListeningModel

    init(state: ProfileFeedbackVisualState) {
        self.state = state
        _listeningModel = State(
            initialValue: ListeningModel(
                account: Account(username: "visual-listener", token: "visual-token"),
                provider: VisualQAProfileFeedbackListeningProvider()
            )
        )
    }

    var body: some View {
        NavigationStack {
            ProfileFeedbackLibraryView(
                username: "visual-listener",
                isOwner: true,
                listeningModel: listeningModel,
                provider: VisualQAProfileFeedbackProvider(state: state),
                cache: EntityDetailCache(),
                pageSize: 3
            )
        }
    }
}

private struct VisualQAProfileFeedbackProvider: ProfileFeedbackProviding {
    let state: ProfileFeedbackVisualState

    func page(
        username: String,
        category: ProfileFeedbackCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfileFeedbackPage {
        if state == .failure || state == .partialFailure && offset > 0 {
            throw VisualQAProfileFeedbackError.unavailable
        }
        if state == .empty {
            return .init(
                username: username,
                category: category,
                items: [],
                serverCount: 0,
                offset: offset,
                totalCount: 0
            )
        }

        let items = category == .loved ? Self.loved : Self.hated
        let page = Array(items.dropFirst(offset).prefix(count))
        return .init(
            username: username,
            category: category,
            items: page,
            serverCount: page.count,
            offset: offset,
            totalCount: items.count
        )
    }

    private static let loved = [
        item(1, .loved, "A Long Way Home Through the Quietest Part of the Night", "The Cartographers", "Paper Cities"),
        item(2, .loved, "Horizon", "Still Corners", "The Last Exit"),
        item(3, .loved, "Soft Focus", "Fazerdaze", nil),
        item(4, .loved, "Signals", "Kelly Lee Owens", "Inner Song"),
        item(5, .loved, "New Grass", "Talk Talk", "Laughing Stock"),
    ]

    private static let hated = [
        item(11, .hated, "Skip This One", "The Test Fixtures", "A Difficult Second Album"),
        item(12, .hated, "Unmapped Demo", "Unknown Source", nil, mapped: false),
    ]

    private static func item(
        _ seed: Int,
        _ category: ProfileFeedbackCategory,
        _ title: String,
        _ artist: String,
        _ release: String?,
        mapped: Bool = true
    ) -> ProfileFeedbackItem {
        let value = String(format: "%012d", seed)
        let mbid = mapped ? UUID(uuidString: "00000000-0000-0000-0000-\(value)") : nil
        let msid = mapped ? nil : UUID(uuidString: "11111111-1111-1111-1111-\(value)")
        return ProfileFeedbackItem(
            id: mbid.map(ProfileFeedbackIdentity.mbid) ?? .msid(msid!),
            recording: Recording(
                identity: .init(mbid: mbid, msid: msid),
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
            createdAt: .now.addingTimeInterval(TimeInterval(-seed * 86_400)),
            category: category
        )
    }
}

private enum VisualQAProfileFeedbackError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "Check your connection, then try again.")
    }
}

private struct VisualQAProfileFeedbackListeningProvider: ListeningProvider {
    func validateToken() async throws -> String { "visual-listener" }
    func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
    func playingNow(username: String) async throws -> Listen? { nil }
    func listenCount(username: String) async throws -> Int { 0 }
    func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
    func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        .init(period: period, from: .now, to: .now, lastUpdated: .now, buckets: [])
    }
    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
}
#endif
