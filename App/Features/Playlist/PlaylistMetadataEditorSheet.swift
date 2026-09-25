import SwiftUI

struct PlaylistMetadataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaylistMetadataEditorModel
    @State private var isShowingCollaboratorPicker = false
    private let onSaved: @MainActor (PlaylistMetadataMutation) -> Void
    private let onIndeterminateResult: @MainActor () -> Void
    private let collaboratorSearchProvider: (any SearchProviding)?

    init(
        account: Account,
        mode: PlaylistMetadataEditorModel.Mode = .create,
        draft: PlaylistMetadataDraft = .init(),
        provider: (any PlaylistMutationProviding)? = nil,
        collaboratorSearchProvider: (any SearchProviding)? = nil,
        onIndeterminateResult: @escaping @MainActor () -> Void = {},
        onSaved: @escaping @MainActor (PlaylistMetadataMutation) -> Void
    ) {
        _model = State(initialValue: PlaylistMetadataEditorModel(
            account: account,
            mode: mode,
            draft: draft,
            provider: provider
        ))
        self.collaboratorSearchProvider = collaboratorSearchProvider
        self.onIndeterminateResult = onIndeterminateResult
        self.onSaved = onSaved
    }

    init(
        account: Account,
        detail: PlaylistDetail,
        editPreflight: (@MainActor @Sendable () async throws -> PlaylistDetail)? = nil,
        provider: (any PlaylistMutationProviding)? = nil,
        collaboratorSearchProvider: (any SearchProviding)? = nil,
        onIndeterminateResult: @escaping @MainActor () -> Void = {},
        onSaved: @escaping @MainActor (PlaylistMetadataMutation) -> Void
    ) {
        _model = State(initialValue: PlaylistMetadataEditorModel(
            account: account,
            detail: detail,
            editPreflight: editPreflight,
            provider: provider
        ))
        self.collaboratorSearchProvider = collaboratorSearchProvider
        self.onIndeterminateResult = onIndeterminateResult
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.title)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)

                    TextField(
                        "Description (optional)",
                        text: $model.annotation,
                        axis: .vertical
                    )
                    .lineLimit(3 ... 7)
                } header: {
                    Text("Playlist")
                } footer: {
                    Text("A clear name and a short note make the playlist easier to recognize across ListenBrainz.")
                }

                Section {
                    Toggle(isOn: $model.isPublic) {
                        Label(
                            model.isPublic ? "Public playlist" : "Private playlist",
                            systemImage: model.isPublic ? "globe" : "lock.fill"
                        )
                    }
                } header: {
                    Text("Visibility")
                } footer: {
                    Text(
                        model.isPublic
                            ? "Anyone can find and open this playlist."
                            : "Only you and existing collaborators can open this playlist."
                    )
                }

                Section {
                    if model.collaborators.isEmpty {
                        Text("No collaborators yet")
                            .foregroundStyle(.secondary)
                    } else {
                        // Preserve even malformed legacy snapshots safely: the
                        // server normally de-duplicates collaborators, but an
                        // index remains a stable row identity if duplicate
                        // usernames ever arrive.
                        ForEach(Array(model.collaborators.enumerated()), id: \.offset) { _, username in
                            HStack(spacing: 12) {
                                UserAvatar(username: username, size: 32)
                                Text(username)
                                Spacer(minLength: 12)
                                Button(role: .destructive) {
                                    model.removeCollaborator(username)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(username)")
                            }
                        }
                    }

                    Button {
                        isShowingCollaboratorPicker = true
                    } label: {
                        Label("Add Collaborator", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Collaborators")
                } footer: {
                    Text("Collaborators can manage tracks. Only you can edit playlist details or collaborators.")
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Couldn’t save playlist. \(errorMessage)")
                    }
                }
            }
            .disabled(model.isSaving)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if model.isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving playlist")
                        } else {
                            Text(model.actionTitle)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!model.canSave)
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .sheet(isPresented: $isShowingCollaboratorPicker) {
                PlaylistCollaboratorPicker(
                    account: model.account,
                    collaborators: model.collaborators,
                    provider: collaboratorSearchProvider
                ) { user in
                    model.addCollaborator(user)
                }
            }
        }
    }

    private var navigationTitle: LocalizedStringResource {
        switch model.mode {
        case .create: "New Playlist"
        case .edit: "Edit Playlist"
        }
    }

    private func save() async {
        guard let mutation = await model.save() else {
            if model.requiresReconciliation {
                onIndeterminateResult()
            }
            return
        }
        onSaved(mutation)
        dismiss()
    }
}

private struct PlaylistCollaboratorPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SearchModel
    private let account: Account
    private let collaborators: [String]
    private let onSelect: (SearchUser) -> Void

    init(
        account: Account,
        collaborators: [String],
        provider: (any SearchProviding)? = nil,
        initialQuery: String = "",
        onSelect: @escaping (SearchUser) -> Void
    ) {
        self.account = account
        self.collaborators = collaborators
        self.onSelect = onSelect
        _model = State(initialValue: SearchModel(
            account: account,
            provider: provider,
            initialQuery: initialQuery,
            initialScope: .users
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Find a collaborator",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Search for a ListenBrainz user.")
                    )
                } else {
                    results
                }
            }
            .navigationTitle("Add Collaborator")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: Binding(get: { model.query }, set: { model.update(query: $0) }),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "ListenBrainz username"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { model.startInitialSearchIfNeeded() }
            .onDisappear { model.cancel() }
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .waiting, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(model.state == .waiting ? "Waiting to search…" : "Searching…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded where eligibleUsers.isEmpty:
            ContentUnavailableView(
                "No new users found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Try another username.")
            )
        case let .failed(message):
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.retry() } }
            }
        case .loaded:
            List(eligibleUsers) { user in
                Button {
                    onSelect(user)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        UserAvatar(username: user.username, size: 40)
                        Text(user.username)
                            .font(.body.weight(.semibold))
                        Spacer(minLength: 12)
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(user.username) as collaborator")
            }
            .listStyle(.plain)
        case .idle:
            EmptyView()
        }
    }

    private var eligibleUsers: [SearchUser] {
        model.results.compactMap { result in
            guard case let .user(user) = result,
                  !user.isSameListener(as: account),
                  !collaborators.contains(where: { isSameUsername($0, user.username) })
            else { return nil }
            return user
        }
    }

    private func isSameUsername(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

#if DEBUG
struct VisualQAPlaylistMutationProvider: PlaylistMutationProviding {
    func create(metadata: PlaylistMetadataDraft, ownerUsername: String) async throws -> UUID {
        try await Task.sleep(for: .milliseconds(300))
        return UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
    }

    func edit(mbid: UUID, metadata: PlaylistMetadataDraft, ownerUsername: String) async throws {
        try await Task.sleep(for: .milliseconds(300))
    }
}

/// A request-free collaborator fixture for the visual-QA route. The sheet
/// accepts any `SearchProviding`, so production continues to use the shared,
/// debounced `SearchProvider` path.
struct VisualQAPlaylistCollaboratorSearchProvider: SearchProviding {
    func search(query: String, scope: SearchScope) async throws -> [SearchResult] {
        guard scope == .users else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["anika", "briar", "cora"]
            .filter { normalizedQuery.isEmpty || $0.contains(normalizedQuery) }
            .map { .user(.init(username: $0)) }
    }
}

struct PlaylistCollaboratorPickerVisualQAScreen: View {
    var body: some View {
        PlaylistCollaboratorPicker(
            account: .init(username: "visual-listener", token: "visual-token"),
            collaborators: ["anika"],
            provider: VisualQAPlaylistCollaboratorSearchProvider(),
            initialQuery: "a"
        ) { _ in }
    }
}
#endif
