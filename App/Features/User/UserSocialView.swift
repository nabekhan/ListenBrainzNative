import Observation
import SwiftUI

struct ProfileSocialLink: View {
    let account: Account
    private let provider: (any SocialProviding)?
    private let cache: UserSocialCache

    init(
        account: Account,
        provider: (any SocialProviding)? = nil,
        cache: UserSocialCache = .shared
    ) {
        self.account = account
        self.provider = provider
        self.cache = cache
    }

    var body: some View {
        NavigationLink {
            UserSocialView(
                user: SearchUser(username: account.username),
                viewer: account,
                provider: provider,
                cache: cache
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.3.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.heroGradient, in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Listening connections")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Followers, people you follow, and listeners with similar taste")
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
        .accessibilityHint("Opens your followers, following, and similar listeners")
        .accessibilityIdentifier("profile-social-link")
    }
}

struct UserSocialView: View {
    private enum Connection: String, CaseIterable, Identifiable {
        case followers = "Followers"
        case following = "Following"

        var id: Self { self }
    }

    @State private var model: UserSocialModel
    @State private var connection: Connection = .followers
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        user: SearchUser,
        viewer: Account,
        provider: (any SocialProviding)? = nil,
        cache: UserSocialCache = .shared
    ) {
        _model = State(initialValue: UserSocialModel(
            target: user,
            viewer: viewer,
            provider: provider,
            cache: cache
        ))
    }

    var body: some View {
        List {
            identitySection
            if model.canFollow { relationshipSection }
            similarListenersSection
            connectionsSection
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("user-social-screen")
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.refresh() }
        .alert(
            "Couldn’t update this relationship",
            isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.dismissActionError() } }
            )
        ) {
            Button("OK") { model.dismissActionError() }
        } message: {
            Text(model.actionError ?? String(localized: "ListenBrainz did not accept the change."))
        }
    }

    private var identitySection: some View {
        Section {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            UserAvatar(username: model.target.username, size: 58)
                            Text(model.target.username)
                                .font(.title3.bold())
                                .lineLimit(2)
                        }
                        Text("Listening connections")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        followControl
                    }
                } else {
                    HStack(spacing: 14) {
                        UserAvatar(username: model.target.username, size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.target.username)
                                .font(.title3.bold())
                            Text("Listening connections")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        followControl
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }

    @ViewBuilder
    private var followControl: some View {
        if model.canFollow {
            if let isFollowing = model.isFollowing {
                if isFollowing {
                    Button {
                        Task { await model.toggleFollow() }
                    } label: {
                        Label("Following", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isMutating)
                } else {
                    Button {
                        Task { await model.toggleFollow() }
                    } label: {
                        Text("Follow")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(model.isMutating)
                }
            } else {
                ProgressView()
                    .accessibilityLabel("Loading follow status")
            }
        }
    }

    private var relationshipSection: some View {
        Section("Your match") {
            switch model.compatibilityPhase {
            case .idle, .loading:
                HStack {
                    ProgressView()
                    Text("Calculating from ListenBrainz…")
                        .foregroundStyle(.secondary)
                }
            case .ready:
                HStack(spacing: 14) {
                    Image(systemName: model.normalizedCompatibility == nil ? "person.2.slash" : "person.2.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        if let similarity = model.normalizedCompatibility {
                            Text(similarity, format: .percent.precision(.fractionLength(0)))
                                .font(.title2.bold().monospacedDigit())
                            Text("taste compatibility")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No calculated match yet")
                                .font(.headline)
                            Text("ListenBrainz has not placed this listener in your similarity set.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            case let .failed(message):
                retryRow(title: "Match unavailable", message: message) {
                    await model.retryCompatibility()
                }
            }
        }
    }

    private var connectionsSection: some View {
        Section {
            Picker("Connections", selection: $connection) {
                Text("Followers \(model.followers.count)").tag(Connection.followers)
                Text("Following \(model.following.count)").tag(Connection.following)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            connectionRows
        } header: {
            Text("Connections")
        } footer: {
            Text("ListenBrainz returns complete username lists; rows are not expanded with extra profile requests.")
        }
    }

    @ViewBuilder
    private var connectionRows: some View {
        let phase = connection == .followers ? model.followersPhase : model.followingPhase
        let users = connection == .followers ? model.followers : model.following

        switch phase {
        case .idle, .loading:
            HStack { Spacer(); ProgressView("Loading listeners…"); Spacer() }
        case let .failed(message):
            retryRow(title: "Connections unavailable", message: message) {
                if connection == .followers {
                    await model.retryFollowers()
                } else {
                    await model.retryFollowing()
                }
            }
        case .ready where users.isEmpty:
            ContentUnavailableView(
                connection == .followers ? "No followers yet" : "Not following anyone yet",
                systemImage: "person.2"
            )
        case .ready:
            ForEach(users) { user in
                NavigationLink {
                    UserDetailView(user: user, viewer: model.viewer)
                } label: {
                    ListenerRow(user: user)
                }
            }
        }
    }

    private var similarListenersSection: some View {
        Section {
            switch model.similarUsersPhase {
            case .idle, .loading:
                HStack { Spacer(); ProgressView("Finding similar listeners…"); Spacer() }
            case let .failed(message):
                retryRow(title: "Similar listeners unavailable", message: message) {
                    await model.retrySimilarUsers()
                }
            case .ready where model.similarUsers.isEmpty:
                ContentUnavailableView("No similar listeners yet", systemImage: "person.2.wave.2")
            case .ready:
                ForEach(model.similarUsers.prefix(5)) { listener in
                    NavigationLink {
                        UserDetailView(user: listener.user, viewer: model.viewer)
                    } label: {
                        ListenerRow(user: listener.user, similarity: listener.normalizedSimilarity)
                    }
                }
                if model.similarUsers.count > 5 {
                    NavigationLink("Show all \(model.similarUsers.count)") {
                        SimilarListenersView(listeners: model.similarUsers, viewer: model.viewer)
                    }
                }
            }
        } header: {
            Text("Similar listeners")
        } footer: {
            Text("Similarity is calculated by ListenBrainz from listening taste.")
        }
    }

    private func retryRow(
        title: LocalizedStringResource,
        message: String,
        retry: @escaping @MainActor () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button("Try Again") { Task { await retry() } }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct ProfileSocialVisualQAScreen: View {
    private let account: Account
    private let socialCache = UserSocialCache()
    @State private var listeningModel: ListeningModel
    @State private var session: SessionModel
    @State private var pins: PinsModel
    @State private var socialProvider: VisualQAUserSocialProvider

    init() {
        let account = Account(username: "visual-listener", token: "visual-token")
        let provider = VisualQAUserSocialProvider()
        self.account = account
        _listeningModel = State(initialValue: ListeningModel(account: account))
        _session = State(initialValue: SessionModel())
        _pins = State(initialValue: PinsModel(
            account: account,
            provider: VisualQAProfileSocialPinProvider()
        ))
        _socialProvider = State(initialValue: provider)
    }

    var body: some View {
        ProfileView(
            model: listeningModel,
            session: session,
            playlistProvider: VisualQAProfileSocialPlaylistsProvider(),
            socialProvider: socialProvider,
            socialCache: socialCache
        )
        .environment(pins)
        .safeAreaInset(edge: .bottom) {
            Text("Social")
                .font(.caption2.bold())
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: .capsule)
                .accessibilityValue(socialProvider.callCount.formatted())
                .accessibilityIdentifier("profile-social-request-count")
        }
    }
}

@MainActor
@Observable
private final class VisualQAUserSocialProvider: SocialProviding {
    private(set) var callCount = 0

    func followers(of username: String) async throws -> [SearchUser] {
        callCount += 1
        return [
            SearchUser(username: "mira"),
            SearchUser(username: "owen"),
            SearchUser(username: "river-song"),
        ]
    }

    func following(of username: String) async throws -> [SearchUser] {
        callCount += 1
        return [
            SearchUser(username: "aya"),
            SearchUser(username: "cassette-club"),
        ]
    }

    func similarUsers(to username: String) async throws -> [SimilarListener] {
        callCount += 1
        return [
            SimilarListener(user: SearchUser(username: "night-tracks"), similarity: 0.91),
            SimilarListener(user: SearchUser(username: "soft-focus"), similarity: 0.84),
            SimilarListener(user: SearchUser(username: "prairie-radio"), similarity: 0.77),
        ]
    }

    func compatibility(between viewer: String, and username: String) async throws -> Double? {
        callCount += 1
        return 0.88
    }

    func follow(username: String) async throws { callCount += 1 }
    func unfollow(username: String) async throws { callCount += 1 }
}

private struct VisualQAProfileSocialPlaylistsProvider: ProfilePlaylistsProviding {
    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        ProfilePlaylistPage(
            username: username,
            category: category,
            playlists: [],
            requestedCount: count,
            offset: offset,
            totalCount: 0
        )
    }
}

private struct VisualQAProfileSocialPinProvider: PinProviding {
    func currentPin(username: String) async throws -> PinnedRecording? { nil }
    func pin(_ recording: Recording, blurb: String?) async throws -> PinnedRecording {
        throw PinProviderError.pinNeedsIdentifier
    }
    func pinHistory(username: String, count: Int, offset: Int) async throws -> (
        pins: [PinnedRecording], totalCount: Int
    ) {
        ([], 0)
    }
    func unpin() async throws {}
    func updatePinBlurb(rowID: Int, blurb: String) async throws {}
    func deletePin(rowID: Int) async throws {}
}
#endif

private struct SimilarListenersView: View {
    let listeners: [SimilarListener]
    let viewer: Account

    var body: some View {
        List(listeners) { listener in
            NavigationLink {
                UserDetailView(user: listener.user, viewer: viewer)
            } label: {
                ListenerRow(user: listener.user, similarity: listener.normalizedSimilarity)
            }
        }
        .navigationTitle("Similar listeners")
        .navigationBarTitleDisplayMode(.inline)
    }
}
