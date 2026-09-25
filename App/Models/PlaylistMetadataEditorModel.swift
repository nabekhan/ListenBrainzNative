import Foundation
import Observation

@MainActor
@Observable
final class PlaylistMetadataEditorModel {
    enum Mode: Equatable, Sendable {
        case create
        case edit(UUID)
    }

    let account: Account
    let mode: Mode
    private let provider: any PlaylistMutationProviding
    private let originalMetadata: PlaylistMetadataDraft?
    private let editPreflight: (@MainActor @Sendable () async throws -> PlaylistDetail)?

    var title: String
    var annotation: String
    var isPublic: Bool
    private(set) var collaborators: [String]
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var requiresReconciliation = false

    init(
        account: Account,
        mode: Mode = .create,
        draft: PlaylistMetadataDraft = .init(),
        originalMetadata: PlaylistMetadataDraft? = nil,
        editPreflight: (@MainActor @Sendable () async throws -> PlaylistDetail)? = nil,
        provider: (any PlaylistMutationProviding)? = nil
    ) {
        self.account = account
        self.mode = mode
        self.provider = provider ?? ListenBrainzPlaylistMutationProvider(token: account.token)
        self.originalMetadata = originalMetadata
        self.editPreflight = editPreflight
        title = draft.title
        annotation = draft.annotation
        isPublic = draft.isPublic
        collaborators = draft.collaborators
    }

    convenience init(
        account: Account,
        detail: PlaylistDetail,
        editPreflight: (@MainActor @Sendable () async throws -> PlaylistDetail)? = nil,
        provider: (any PlaylistMutationProviding)? = nil
    ) {
        let draft = PlaylistMetadataDraft(detail: detail)
        self.init(
            account: account,
            mode: .edit(detail.mbid),
            draft: draft,
            originalMetadata: draft,
            editPreflight: editPreflight,
            provider: provider
        )
    }

    var canSave: Bool {
        account.isAuthenticated
            && !isSaving
            && !requiresReconciliation
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var actionTitle: String {
        switch mode {
        case .create: String(localized: "Create")
        case .edit: String(localized: "Save")
        }
    }

    /// Collaborators are selected from a concrete ListenBrainz search result in
    /// the UI. Keep the same owner and duplicate safeguards here as well so a
    /// future presentation cannot accidentally put an invalid snapshot on the
    /// mutation path.
    @discardableResult
    func addCollaborator(_ user: SearchUser) -> Bool {
        let username = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSaving,
              !username.isEmpty,
              !isSameUsername(username, account.username),
              !collaborators.contains(where: { isSameUsername($0, username) })
        else { return false }

        collaborators.append(username)
        return true
    }

    func removeCollaborator(_ username: String) {
        guard !isSaving else { return }
        collaborators.removeAll { isSameUsername($0, username) }
    }

    func save() async -> PlaylistMetadataMutation? {
        guard !isSaving else { return nil }
        guard account.isAuthenticated else {
            errorMessage = PlaylistMutationProviderError.invalidAuthentication.localizedDescription
            return nil
        }

        let draft = PlaylistMetadataDraft(
            title: title,
            annotation: annotation,
            isPublic: isPublic,
            collaborators: collaborators
        )
        let normalized: PlaylistMetadataDraft
        do {
            normalized = try draft.normalized(ownerUsername: account.username)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            switch mode {
            case .create:
                let mbid = try await provider.create(
                    metadata: normalized,
                    ownerUsername: account.username
                )
                return .created(mbid)
            case let .edit(mbid):
                if let originalMetadata, let editPreflight {
                    let latest: PlaylistDetail
                    do {
                        latest = try await editPreflight()
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw PlaylistMetadataEditorError.couldNotVerifyLatest
                    }
                    guard originalMetadata.hasSameServerMetadata(
                        as: PlaylistMetadataDraft(detail: latest),
                        ownerUsername: account.username
                    ) else {
                        throw PlaylistMetadataEditorError.changedElsewhere
                    }
                }
                try await provider.edit(
                    mbid: mbid,
                    metadata: normalized,
                    ownerUsername: account.username
                )
                return .edited(normalized)
            }
        } catch is CancellationError {
            return nil
        } catch {
            if let mutationError = error as? PlaylistMutationProviderError,
               mutationError.isIndeterminate {
                requiresReconciliation = true
            }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func isSameUsername(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

enum PlaylistMetadataEditorError: LocalizedError, Sendable {
    case couldNotVerifyLatest
    case changedElsewhere

    var errorDescription: String? {
        switch self {
        case .couldNotVerifyLatest:
            String(localized: "Couldn’t verify the latest playlist details, so nothing was changed. Try again when the playlist can be refreshed.")
        case .changedElsewhere:
            String(localized: "This playlist changed after the editor opened. Close and reopen the editor so nobody’s changes are overwritten.")
        }
    }
}
