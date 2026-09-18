// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Metadata for a ListenBrainz playlist
public struct LBPlaylistMetadata: Equatable, Sendable {
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

    /// ListenBrainz generator slug, for example `weekly-jams`.
    public let recommendationType: String?

    /// When an ephemeral generated playlist is scheduled to expire.
    public let expiresAt: Date?

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
        self.recommendationType = raw.ext.listenbrainz.additionalMetadata?.algorithmMetadata?.sourcePatch
        self.expiresAt = parsePlaylistDate(raw.ext.listenbrainz.additionalMetadata?.expiresAt)
    }
}

/// One metadata-only page returned by a ListenBrainz user-playlist endpoint.
///
/// The list endpoints report pagination using `count`, `offset`, and
/// `playlist_count`. `count` is the requested page size rather than the number
/// of returned playlists, so it is exposed as ``requestedCount``. These values
/// intentionally remain optional because the server may omit them on older or
/// empty responses.
public struct LBPlaylistPage: Equatable, Sendable {
    /// Playlists returned in this page. Track lists are not included.
    public let playlists: [LBPlaylistMetadata]

    /// The page size requested from the server (`count` in the API response).
    ///
    /// This is not necessarily equal to `playlists.count`; use the latter for
    /// the number of rows actually returned.
    public let requestedCount: Int?

    /// The server-reported offset of this page.
    public let offset: Int?

    /// Total playlists available from the endpoint.
    public let playlistCount: Int?

    public init(
        playlists: [LBPlaylistMetadata],
        requestedCount: Int?,
        offset: Int?,
        playlistCount: Int?
    ) {
        self.playlists = playlists
        self.requestedCount = requestedCount
        self.offset = offset
        self.playlistCount = playlistCount
    }

    init(raw: RawPlaylistResponse) {
        self.init(
            playlists: raw.playlists.map { LBPlaylistMetadata(raw: $0.playlist) },
            requestedCount: raw.count,
            offset: raw.offset,
            playlistCount: raw.playlistCount
        )
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
