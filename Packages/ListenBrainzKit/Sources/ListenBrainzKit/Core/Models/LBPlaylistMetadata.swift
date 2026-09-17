// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Metadata for a ListenBrainz playlist
public struct LBPlaylistMetadata: Sendable {
    /// Title of the playlist
    public let title: String

    /// Optional description
    public let annotation: String?

    /// Username of the creator
    public let creator: String

    /// Link to this playlist on ListenBrainz
    public let identifier: String

    /// Date this was created
    public let date: Date?
    public let duration: Int?

    // Extended:

    /// Is this playlist public on ListenBrainz
    public let isPublic: Bool

    /// When this playlist was last modified
    public let lastModifiedAt: Date?

    /// The user this playlist was created for
    public let createdFor: String?

    /// The usernames of the collaborators
    public let collaborators: [String]?

    /// Where this playlist was imported from
    public let copiedFrom: String?
    public let copiedFromDeleted: Bool?

    init(raw: RawPlaylist) {
        self.title = raw.title
        self.annotation = raw.annotation
        self.creator = raw.creator
        self.identifier = raw.identifier
        self.date = parsePlaylistDate(raw.date)
        self.duration = raw.duration
        self.isPublic = raw.ext.listenbrainz.isPublic
        self.lastModifiedAt = parsePlaylistDate(raw.ext.listenbrainz.lastModifiedAt)
        self.createdFor = raw.ext.listenbrainz.createdFor
        self.collaborators = raw.ext.listenbrainz.collaborators
        self.copiedFrom = raw.ext.listenbrainz.copiedFromMbid
        self.copiedFromDeleted = raw.ext.listenbrainz.copiedFromDeleted
    }
}

func parsePlaylistDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
