import SwiftUI

struct UserSocialView: View {
    private enum Connection: String, CaseIterable, Identifiable {
        case followers = "Followers"
        case following = "Following"

        var id: Self { self }
    }

    @State private var model: UserSocialModel
    @State private var connection: Connection = .followers
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(user: SearchUser, viewer: Account) {
        _model = State(initialValue: UserSocialModel(target: user, viewer: viewer))
    }

    var body: some View {
        List {
            identitySection
            if model.canFollow { relationshipSection }
            similarListenersSection
            connectionsSection
        }
        .listStyle(.insetGrouped)
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
            Text(model.actionError ?? "ListenBrainz did not accept the change.")
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
        title: String,
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

private struct ListenerRow: View {
    let user: SearchUser
    var similarity: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        UserAvatar(username: user.username, size: 42)
                        Text(user.username)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                    }
                    similarityLabel
                        .padding(.leading, 54)
                }
            } else {
                HStack(spacing: 12) {
                    UserAvatar(username: user.username, size: 42)
                    Text(user.username)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    similarityLabel
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var similarityLabel: some View {
        if let similarity {
            Text(similarity, format: .percent.precision(.fractionLength(0)))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(similarity.formatted(.percent)) similar")
        }
    }
}
