import SwiftUI

struct PlaylistMetadataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaylistMetadataEditorModel
    private let onSaved: @MainActor (PlaylistMetadataMutation) -> Void
    private let onIndeterminateResult: @MainActor () -> Void

    init(
        account: Account,
        mode: PlaylistMetadataEditorModel.Mode = .create,
        draft: PlaylistMetadataDraft = .init(),
        provider: (any PlaylistMutationProviding)? = nil,
        onIndeterminateResult: @escaping @MainActor () -> Void = {},
        onSaved: @escaping @MainActor (PlaylistMetadataMutation) -> Void
    ) {
        _model = State(initialValue: PlaylistMetadataEditorModel(
            account: account,
            mode: mode,
            draft: draft,
            provider: provider
        ))
        self.onIndeterminateResult = onIndeterminateResult
        self.onSaved = onSaved
    }

    init(
        account: Account,
        detail: PlaylistDetail,
        editPreflight: (@MainActor @Sendable () async throws -> PlaylistDetail)? = nil,
        provider: (any PlaylistMutationProviding)? = nil,
        onIndeterminateResult: @escaping @MainActor () -> Void = {},
        onSaved: @escaping @MainActor (PlaylistMetadataMutation) -> Void
    ) {
        _model = State(initialValue: PlaylistMetadataEditorModel(
            account: account,
            detail: detail,
            editPreflight: editPreflight,
            provider: provider
        ))
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

                if !model.collaborators.isEmpty {
                    Section {
                        ForEach(Array(model.collaborators.enumerated()), id: \.offset) { _, username in
                            Label(username, systemImage: "person.fill")
                        }
                    } header: {
                        Text("Collaborators")
                    } footer: {
                        Text("Existing collaborators are preserved. Manage collaborators on the ListenBrainz website for now.")
                    }
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
        }
    }

    private var navigationTitle: String {
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
#endif
