import Foundation
import Observation

struct PlaylistMetadataDraft: Equatable, Sendable {
    var title: String
    var annotation: String
    var isPublic: Bool
    var collaborators: [String]

    init(
        title: String = "",
        annotation: String = "",
        isPublic: Bool = false,
        collaborators: [String] = []
    ) {
        self.title = title
        self.annotation = annotation
        self.isPublic = isPublic
        self.collaborators = collaborators
    }

    init(detail: PlaylistDetail) {
        self.init(
            title: detail.title,
            annotation: detail.annotation ?? "",
            isPublic: detail.isPublic,
            collaborators: detail.collaborators
        )
    }

    var hasValidTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func normalized(ownerUsername: String) throws -> PlaylistMetadataDraft {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw PlaylistMetadataDraftError.missingTitle }

        let normalizedOwner = Self.usernameKey(ownerUsername)
        var seen: Set<String> = []
        let normalizedCollaborators = collaborators.compactMap { value -> String? in
            let username = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty else { return nil }
            let key = Self.usernameKey(username)
            guard key != normalizedOwner, seen.insert(key).inserted else { return nil }
            return username
        }

        let normalizedAnnotation = annotation.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlaylistMetadataDraft(
            title: normalizedTitle,
            annotation: normalizedAnnotation,
            isPublic: isPublic,
            collaborators: normalizedCollaborators
        )
    }

    var optionalAnnotation: String? {
        annotation.isEmpty ? nil : annotation
    }

    func hasSameServerMetadata(
        as other: PlaylistMetadataDraft,
        ownerUsername: String
    ) -> Bool {
        guard let lhs = try? normalized(ownerUsername: ownerUsername),
              let rhs = try? other.normalized(ownerUsername: ownerUsername)
        else { return false }

        return lhs.title == rhs.title
            && lhs.optionalAnnotation == rhs.optionalAnnotation
            && lhs.isPublic == rhs.isPublic
            && lhs.collaboratorKeys == rhs.collaboratorKeys
    }

    private var collaboratorKeys: [String] {
        collaborators.map(Self.usernameKey).sorted()
    }

    private static func usernameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum PlaylistMetadataDraftError: LocalizedError, Sendable {
    case missingTitle

    var errorDescription: String? {
        "Give this playlist a name before saving it."
    }
}

enum PlaylistMetadataMutation: Equatable, Sendable {
    case created(UUID)
    case edited(PlaylistMetadataDraft)
}

struct ConfirmedPlaylistMetadataEdit: Equatable, Sendable {
    let mbid: UUID
    let ownerUsername: String
    let draft: PlaylistMetadataDraft
}

/// A tiny process-local journal keeps already-loaded playlist lists coherent
/// when an edit originates from Search, Discover, or another tab. It carries
/// only confirmed metadata and never a token.
@MainActor
@Observable
final class PlaylistMutationJournal {
    static let shared = PlaylistMutationJournal()

    private(set) var revision = 0
    private(set) var latestConfirmedEdit: ConfirmedPlaylistMetadataEdit?

    func recordConfirmedEdit(
        mbid: UUID,
        ownerUsername: String,
        draft: PlaylistMetadataDraft
    ) {
        latestConfirmedEdit = ConfirmedPlaylistMetadataEdit(
            mbid: mbid,
            ownerUsername: Self.usernameKey(ownerUsername),
            draft: draft
        )
        revision = revision == Int.max ? 1 : revision + 1
    }

    private static func usernameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
