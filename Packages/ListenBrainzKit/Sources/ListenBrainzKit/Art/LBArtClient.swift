// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// ListenBrainz-generated artwork.
public struct LBYearInMusicArtwork: Equatable, Sendable {
    /// The server's SVG document, kept raw so callers can choose an appropriate
    /// platform renderer without a lossy conversion.
    public let svg: String

    public init(svg: String) {
        self.svg = svg
    }
}

/// The image layouts currently supported by ListenBrainz's Year in Music art API.
public enum LBYearInMusicArtVariant: String, CaseIterable, Sendable {
    case overview
    case stats
    case artists
    case albums
    case tracks
    case discoveryPlaylist = "discovery-playlist"
    case missedPlaylist = "missed-playlist"
}

public struct LBArtClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) {
        apiClient = client
    }

    /// Generate one Year in Music SVG. Returns `nil` when the report does not
    /// contain enough data for the requested image.
    public func yearInMusic(
        username: String,
        year: Int,
        variant: LBYearInMusicArtVariant = .overview,
        anonymous: Bool? = nil
    ) async throws -> LBYearInMusicArtwork? {
        try await apiClient.execute(
            YearInMusicArtworkRequest(
                username: username,
                year: year,
                variant: variant,
                anonymous: anonymous
            )
        )
    }
}
