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

struct ConfirmedPlaylistCopy: Equatable, Sendable {
    let ownerUsername: String
    let playlist: SearchPlaylist
}

enum PlaylistAccessLossReason: Equatable, Sendable {
    case authentication
    case sourceVisibility
}

struct PlaylistAccessLossEvent: Equatable, Sendable {
    let viewerUsername: String
    let sourceMBID: UUID
    let reason: PlaylistAccessLossReason
    let message: String
}

enum PlaylistJournalEvent: Equatable, Sendable {
    case edit(ConfirmedPlaylistMetadataEdit)
    case copy(ConfirmedPlaylistCopy)
    case accessLoss(PlaylistAccessLossEvent)
}

struct PlaylistJournalEntry: Equatable, Sendable {
    let revision: Int
    let event: PlaylistJournalEvent
}

/// A tiny process-local journal keeps already-loaded playlist lists coherent
/// when a mutation or access failure originates from Search, Discover, or
/// another tab. It carries no token.
@MainActor
@Observable
final class PlaylistMutationJournal {
    static let shared = PlaylistMutationJournal()

    private(set) var revision = 0
    private(set) var events: [PlaylistJournalEntry] = []

    func entries(after revision: Int) -> [PlaylistJournalEntry] {
        events.filter { $0.revision > revision }
    }

    func recordConfirmedEdit(
        mbid: UUID,
        ownerUsername: String,
        draft: PlaylistMetadataDraft
    ) {
        record(.edit(ConfirmedPlaylistMetadataEdit(
            mbid: mbid,
            ownerUsername: Self.usernameKey(ownerUsername),
            draft: draft
        )))
    }

    func recordConfirmedCopy(
        _ playlist: SearchPlaylist,
        ownerUsername: String
    ) {
        record(.copy(ConfirmedPlaylistCopy(
            ownerUsername: Self.usernameKey(ownerUsername),
            playlist: playlist
        )))
    }

    func recordAccessLoss(
        sourceMBID: UUID,
        viewerUsername: String,
        reason: PlaylistAccessLossReason,
        message: String,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) async {
        // New Profile models intentionally start at the current journal
        // revision instead of replaying historic events. Evict list snapshots
        // before publishing so such a model cannot serve a freshly cached row
        // whose visibility was just revoked.
        await profilePageCache.removeAll()
        record(.accessLoss(PlaylistAccessLossEvent(
            viewerUsername: Self.usernameKey(viewerUsername),
            sourceMBID: sourceMBID,
            reason: reason,
            message: message
        )))
    }

    private func record(_ event: PlaylistJournalEvent) {
        revision += 1
        events.append(.init(revision: revision, event: event))
    }

    private static func usernameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
