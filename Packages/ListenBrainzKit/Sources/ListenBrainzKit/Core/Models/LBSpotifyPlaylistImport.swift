// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A bounded set of Spotify playlists available for import.
public struct LBSpotifyPlaylistImportList: Equatable, Sendable {
    /// The playlist summaries retained by the client.
    public let playlists: [LBSpotifyPlaylistSummary]
    /// Whether ListenBrainz returned more playlists than this client retained.
    public let isTruncated: Bool

    public init(playlists: [LBSpotifyPlaylistSummary], isTruncated: Bool) {
        self.playlists = playlists
        self.isTruncated = isTruncated
    }
}

/// A Spotify playlist available to import into the authenticated
/// ListenBrainz account.
///
/// This is deliberately a summary. Fetching a playlist's tracks is a separate
/// server-side import operation which creates a ListenBrainz playlist.
public struct LBSpotifyPlaylistSummary: Equatable, Sendable {
    /// The opaque Spotify playlist identifier used to start an import.
    public let id: String
    /// The playlist name supplied by Spotify.
    public let title: String
    /// The optional playlist description supplied by Spotify.
    public let description: String?
    /// A representative Spotify-hosted image, when Spotify supplied one.
    public let artworkURL: URL?
    /// The Spotify owner's display name, when supplied.
    public let ownerName: String?
    /// The number of tracks Spotify reported, when supplied.
    public let trackCount: Int?
    /// The playlist's Spotify visibility, when Spotify supplied it.
    public let isPublic: Bool?
    /// Whether Spotify reports the playlist as collaborative.
    public let isCollaborative: Bool

    public init(
        id: String,
        title: String,
        description: String? = nil,
        artworkURL: URL? = nil,
        ownerName: String? = nil,
        trackCount: Int? = nil,
        isPublic: Bool? = nil,
        isCollaborative: Bool = false
    ) throws {
        guard SpotifyPlaylistIdentifier.isValid(id) else { throw LBError.invalidParam }
        self.id = id
        self.title = title
        self.description = description
        self.artworkURL = artworkURL.flatMap(SpotifyArtworkURL.validated)
        self.ownerName = ownerName
        self.trackCount = trackCount
        self.isPublic = isPublic
        self.isCollaborative = isCollaborative
    }

    init(raw: Raw) throws {
        guard SpotifyPlaylistIdentifier.isValid(raw.id) else { throw LBError.invalidResponse }
        id = raw.id
        title = raw.name
        description = raw.description
        artworkURL = raw.images?.compactMap { SpotifyArtworkURL(raw: $0)?.url }.first
        ownerName = raw.owner?.displayName
        trackCount = raw.tracks?.total
        isPublic = raw.isPublic
        isCollaborative = raw.isCollaborative
    }

    struct Raw: Decodable {
        let id: String
        let name: String
        let description: String?
        let images: [SpotifyArtworkURL.Raw]?
        let owner: Owner?
        let tracks: Tracks?
        let isPublic: Bool?
        let isCollaborative: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case description
            case images
            case owner
            case tracks
            case isPublic = "public"
            case isCollaborative = "collaborative"
        }

        struct Owner: Decodable {
            let displayName: String?
        }

        struct Tracks: Decodable {
            let total: Int?
        }
    }
}

enum SpotifyPlaylistIdentifier {
    /// Spotify currently uses 22-character base-62 identifiers. Keep the
    /// validation deliberately opaque enough for a future identifier-length
    /// change, while still admitting exactly one safe path segment.
    static func isValid(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122)
        }
    }
}

struct SpotifyArtworkURL {
    let url: URL

    init?(raw: Raw) {
        guard let url = URL(string: raw.url), let validated = Self.validated(url) else { return nil }
        self.url = validated
    }

    static func validated(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              isSpotifyArtworkHost(host),
              url.port == nil || url.port == 443,
              url.user == nil,
              url.password == nil
        else { return nil }
        return url
    }

    private static func isSpotifyArtworkHost(_ host: String) -> Bool {
        let value = host.lowercased()
        return value.hasSuffix(".scdn.co") || value.hasSuffix(".spotifycdn.com")
    }

    struct Raw: Decodable {
        let url: String
    }
}
