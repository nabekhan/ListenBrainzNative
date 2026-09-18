import SwiftUI

struct ProfilePlaylistSection: View {
    @Bindable var model: ProfilePlaylistsModel
    @Binding var selection: ProfilePlaylistCategory
    let viewer: Account
    var mutationProvider: (any PlaylistMutationProviding)? = nil
    private let mutationJournal = PlaylistMutationJournal.shared
    @State private var showsCreator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                SectionHeader(title: "Playlists", subtitle: sectionSubtitle)
                if canCreate {
                    Button {
                        showsCreator = true
                    } label: {
                        Label("New", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Create playlist")
                }
            }

            Picker("Playlist category", selection: $selection) {
                ForEach(ProfilePlaylistCategory.allCases, id: \.self) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Playlist category")

            stateContent
        }
        .task(id: selection) {
            await model.load(category: selection)
        }
        .task(id: mutationJournal.revision) {
            guard let edit = mutationJournal.latestConfirmedEdit else { return }
            await model.reconcileAfterConfirmedEdit(edit)
        }
        .sheet(isPresented: $showsCreator) {
            PlaylistMetadataEditorSheet(
                account: viewer,
                provider: resolvedMutationProvider,
                onIndeterminateResult: {
                    Task { await model.refreshAfterMutation() }
                }
            ) { mutation in
                guard case .created = mutation else { return }
                Task { await model.refreshAfterMutation() }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        let state = model.state(for: selection)
        switch state.phase {
        case .idle, .loading:
            loadingCard
        case let .failed(message):
            issueCard(
                title: "Couldn’t load playlists",
                message: message,
                actionTitle: "Try Again"
            ) {
                await model.refresh(category: selection)
            }
        case .refreshing, .ready:
            if state.playlists.isEmpty {
                emptyCard
            } else {
                playlistRows(state.playlists)
            }

            if state.phase == .refreshing {
                Label("Refreshing playlists…", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let message = state.refreshMessage {
                issueCard(
                    title: "Showing saved playlists",
                    message: message,
                    actionTitle: "Refresh"
                ) {
                    await model.refresh(category: selection)
                }
            }

            paginationFooter(state)
        }
    }

    private func playlistRows(_ playlists: [SearchPlaylist]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(playlists) { playlist in
                if playlist.playlistMBID != nil {
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist, viewer: viewer)
                    } label: {
                        ProfilePlaylistRow(
                            playlist: playlist,
                            category: selection,
                            showsDisclosure: true
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ProfilePlaylistRow(
                        playlist: playlist,
                        category: selection,
                        showsDisclosure: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func paginationFooter(_ state: ProfilePlaylistCategoryState) -> some View {
        if state.isLoadingMore {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading more…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } else if let message = state.loadMoreError {
            issueCard(
                title: "More playlists are available",
                message: message,
                actionTitle: "Retry"
            ) {
                await model.loadMore(category: selection)
            }
        } else if state.hasMore {
            Button {
                Task { await model.loadMore(category: selection) }
            } label: {
                Label("Load more playlists", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Loading \(selection.shortTitle.lowercased()) playlists…")
                    .font(.subheadline.weight(.semibold))
                Text("Only playlist details are fetched here; tracks load when opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var emptyCard: some View {
        ContentUnavailableView(
            selection == .owned ? "No playlists yet" : "No collaborations yet",
            systemImage: selection == .owned ? "music.note.list" : "person.2.wave.2",
            description: Text(selection.emptyDescription(for: viewer))
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func issueCard(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle) { Task { await action() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var sectionSubtitle: String {
        let state = model.state(for: selection)
        if let totalCount = state.totalCount, state.phase == .ready {
            return "\(totalCount.formatted()) \(selection.countLabel(for: totalCount))"
        }
        return selection.description(isAuthenticated: viewer.isAuthenticated)
    }

    private var canCreate: Bool {
        selection == .owned && viewer.isAuthenticated
    }

    private var resolvedMutationProvider: any PlaylistMutationProviding {
        mutationProvider ?? ListenBrainzPlaylistMutationProvider(token: viewer.token)
    }
}

private struct ProfilePlaylistRow: View {
    let playlist: SearchPlaylist
    let category: ProfilePlaylistCategory
    let showsDisclosure: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else {
                compactContent
            }
        }
        .padding(13)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(showsDisclosure ? "Open playlist" : "Playlist link unavailable")
    }

    private var compactContent: some View {
        HStack(alignment: .center, spacing: 13) {
            artwork

            VStack(alignment: .leading, spacing: 5) {
                title
                    .lineLimit(2)
                creator
                    .lineLimit(1)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { metadataLabels }
                    VStack(alignment: .leading, spacing: 3) { metadataLabels }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                collaborators
            }

            Spacer(minLength: 4)
            disclosure
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                artwork
                Spacer(minLength: 8)
                disclosure
                    .padding(.top, 6)
            }
            title
            creator
            VStack(alignment: .leading, spacing: 7) { metadataLabels }
                .font(.caption)
                .foregroundStyle(.secondary)
            collaborators
        }
    }

    private var title: some View {
        Text(playlist.title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var creator: some View {
        Text("By \(playlist.creator)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var collaborators: some View {
        if category == .collaborating, !playlist.collaborators.isEmpty {
            Text(collaboratorDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        if showsDisclosure {
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Playlist link unavailable")
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.artworkGradient(seed: playlist.identifier))
            Image(systemName: "music.note.list")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
        }
        .frame(width: 68, height: 68)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var metadataLabels: some View {
        Label(
            playlist.isPublic ? "Public" : "Private",
            systemImage: playlist.isPublic ? "globe" : "lock.fill"
        )
        if let duration = durationDescription {
            Label(duration, systemImage: "clock")
        }
        if let dateDescription {
            Text(dateDescription)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dateDescription: String? {
        if let updated = playlist.lastModifiedAt {
            return "Updated \(updated.formatted(date: .abbreviated, time: .omitted))"
        }
        if let created = playlist.createdAt {
            return "Created \(created.formatted(date: .abbreviated, time: .omitted))"
        }
        return nil
    }

    private var durationDescription: String? {
        guard let milliseconds = playlist.durationMilliseconds, milliseconds > 0 else { return nil }
        let totalMinutes = milliseconds / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var collaboratorDescription: String {
        let names = playlist.collaborators.prefix(2).joined(separator: ", ")
        let remainder = playlist.collaborators.count - min(playlist.collaborators.count, 2)
        return remainder > 0 ? "With \(names) +\(remainder)" : "With \(names)"
    }

    private var accessibilityLabel: String {
        var parts = [playlist.title, "by \(playlist.creator)", playlist.isPublic ? "Public" : "Private"]
        if let durationDescription { parts.append(durationDescription) }
        if let dateDescription { parts.append(dateDescription) }
        if category == .collaborating, !playlist.collaborators.isEmpty {
            parts.append(collaboratorDescription)
        }
        return parts.joined(separator: ", ")
    }
}

private extension ProfilePlaylistCategory {
    var title: String {
        switch self {
        case .owned: "Owned"
        case .collaborating: "Collaborating"
        }
    }

    var shortTitle: String {
        switch self {
        case .owned: "Owned"
        case .collaborating: "Shared"
        }
    }

    func description(isAuthenticated: Bool) -> String {
        switch (self, isAuthenticated) {
        case (.owned, true): "Collections you created, including private playlists"
        case (.owned, false): "Public collections created by this listener"
        case (.collaborating, true): "Collections you help shape with other listeners"
        case (.collaborating, false): "Public collections shared with other listeners"
        }
    }

    func emptyDescription(for viewer: Account) -> String {
        switch (self, viewer.isAuthenticated) {
        case (.owned, true): "Playlists you create on ListenBrainz will appear here."
        case (.owned, false): "This listener has no public playlists."
        case (.collaborating, true): "Playlists shared with you will appear here."
        case (.collaborating, false): "This listener has no public collaborative playlists."
        }
    }

    func countLabel(for count: Int) -> String {
        let noun = count == 1 ? "playlist" : "playlists"
        switch self {
        case .owned: return "owned \(noun)"
        case .collaborating: return "collaborative \(noun)"
        }
    }
}

#if DEBUG
struct ProfilePlaylistVisualQAScreen: View {
    @State private var model: ProfilePlaylistsModel
    @State private var selection: ProfilePlaylistCategory
    private let account = Account(username: "visual-listener", token: "visual-token")

    init(selection: ProfilePlaylistCategory) {
        _selection = State(initialValue: selection)
        _model = State(initialValue: ProfilePlaylistsModel(
            account: Account(username: "visual-listener", token: "visual-token"),
            provider: VisualQAProfilePlaylistsProvider(),
            cache: EntityDetailCache(),
            pageSize: 20
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ProfilePlaylistSection(
                    model: model,
                    selection: $selection,
                    viewer: account,
                    mutationProvider: VisualQAPlaylistMutationProvider()
                )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 24)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct VisualQAProfilePlaylistsProvider: ProfilePlaylistsProviding {
    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        let rows = category == .owned ? Self.owned : Self.collaborating
        let page = Array(rows.dropFirst(offset).prefix(count))
        return ProfilePlaylistPage(
            username: username,
            category: category,
            playlists: page,
            requestedCount: count,
            offset: offset,
            totalCount: rows.count
        )
    }

    private static let owned = [
        playlist(
            title: "Soft Focus — late-night favorites",
            creator: "visual-listener",
            id: "11111111-1111-4111-8111-111111111111",
            isPublic: true,
            duration: 5_820_000,
            daysAgo: 2
        ),
        playlist(
            title: "Songs I keep coming back to",
            creator: "visual-listener",
            id: "22222222-2222-4222-8222-222222222222",
            isPublic: false,
            duration: 9_300_000,
            daysAgo: 18
        ),
        playlist(
            title: "Prairie drives",
            creator: "visual-listener",
            id: "not-a-valid-playlist-id",
            isPublic: true,
            duration: nil,
            daysAgo: 61
        ),
    ]

    private static let collaborating = [
        playlist(
            title: "Indie discoveries for the long weekend",
            creator: "mira",
            id: "33333333-3333-4333-8333-333333333333",
            isPublic: true,
            duration: 7_740_000,
            daysAgo: 1,
            collaborators: ["visual-listener", "mira", "owen"]
        ),
        playlist(
            title: "Midnight listening club",
            creator: "owen",
            id: "44444444-4444-4444-8444-444444444444",
            isPublic: false,
            duration: 12_180_000,
            daysAgo: 7,
            collaborators: ["visual-listener", "owen"]
        ),
        playlist(
            title: "New releases worth sharing",
            creator: "mira",
            id: "55555555-5555-4555-8555-555555555555",
            isPublic: true,
            duration: 4_320_000,
            daysAgo: 29,
            collaborators: ["visual-listener", "mira"]
        ),
    ]

    private static func playlist(
        title: String,
        creator: String,
        id: String,
        isPublic: Bool,
        duration: Int?,
        daysAgo: Int,
        collaborators: [String] = []
    ) -> SearchPlaylist {
        SearchPlaylist(
            title: title,
            creator: creator,
            annotation: nil,
            identifier: "https://listenbrainz.org/playlist/\(id)",
            isPublic: isPublic,
            lastModifiedAt: Calendar(identifier: .gregorian).date(
                byAdding: .day,
                value: -daysAgo,
                to: Date(timeIntervalSince1970: 1_789_689_600)
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationMilliseconds: duration,
            collaborators: collaborators
        )
    }
}
#endif
