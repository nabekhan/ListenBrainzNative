// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The complete editable metadata snapshot for a ListenBrainz playlist.
///
/// Use the same snapshot for creation and editing. ListenBrainz treats playlist
/// edits as replacements: omitting collaborators clears them, and an explicit
/// `nil` annotation clears the description. Requiring every editable field here
/// makes that behavior visible at the call site.
public struct LBPlaylistMutationMetadata: Equatable, Sendable {
    /// The playlist title. It must contain at least one non-whitespace character.
    public let title: String

    /// The optional playlist description. `nil` explicitly removes an existing
    /// description when used with ``LBCoreClient/editPlaylist(mbid:metadata:)``.
    public let annotation: String?

    /// Whether the playlist is visible publicly on ListenBrainz.
    public let isPublic: Bool

    /// The complete list of collaborator usernames. Pass an empty array to
    /// remove all collaborators when editing.
    public let collaborators: [String]

    public init(
        title: String,
        annotation: String? = nil,
        isPublic: Bool,
        collaborators: [String] = []
    ) {
        self.title = title
        self.annotation = annotation
        self.isPublic = isPublic
        self.collaborators = collaborators
    }

    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              collaborators.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw LBError.invalidParam
        }
    }
}
