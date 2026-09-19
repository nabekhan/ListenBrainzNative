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

/// A validated SVG document produced by a ListenBrainz Art endpoint.
public struct LBGeneratedArtwork: Equatable, Sendable {
    public let svg: String

    public init(svg: String) {
        self.svg = svg
    }
}

public enum LBArtGridLayout: Int, CaseIterable, Sendable {
    case zero = 0
    case one
    case two
    case three

    func isValid(for dimension: Int) -> Bool {
        switch dimension {
        case 1, 2:
            self == .zero
        case 3:
            rawValue <= 2
        case 4:
            rawValue <= 3
        case 5:
            self == .zero || self == .one
        default:
            false
        }
    }
}

public enum LBStatsArtRange: String, CaseIterable, Sendable {
    case thisWeek = "this_week"
    case thisMonth = "this_month"
    case thisYear = "this_year"
    case week
    case month
    case quarter
    case halfYearly = "half_yearly"
    case year
    case allTime = "all_time"
}

public struct LBArtGridOptions: Hashable, Sendable {
    public var captions: Bool
    public var skipMissing: Bool
    public var showRank: Bool
    public var showListenCount: Bool
    public var showRelease: Bool
    public var showArtist: Bool

    public init(
        captions: Bool = true,
        skipMissing: Bool = true,
        showRank: Bool = false,
        showListenCount: Bool = false,
        showRelease: Bool = true,
        showArtist: Bool = true
    ) {
        self.captions = captions
        self.skipMissing = skipMissing
        self.showRank = showRank
        self.showListenCount = showListenCount
        self.showRelease = showRelease
        self.showArtist = showArtist
    }

    public static let nativeDefault = Self(
        captions: true,
        skipMissing: true,
        showRank: true,
        showListenCount: true,
        showRelease: true,
        showArtist: true
    )
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

    public func statisticsGrid(
        username: String,
        range: LBStatsArtRange,
        dimension: Int = 3,
        layout: LBArtGridLayout = .one,
        imageSize: Int = 924,
        options: LBArtGridOptions = .nativeDefault
    ) async throws -> LBGeneratedArtwork? {
        try await apiClient.execute(
            try StatisticsGridArtworkRequest(
                username: username,
                range: range,
                dimension: dimension,
                layout: layout,
                imageSize: imageSize,
                options: options
            )
        )
    }

    public func artistGrid(
        artistMBID: UUID,
        dimension: Int = 3,
        layout: LBArtGridLayout = .one,
        imageSize: Int = 924,
        options: LBArtGridOptions = .nativeDefault
    ) async throws -> LBGeneratedArtwork? {
        try await apiClient.execute(
            try ArtistGridArtworkRequest(
                artistMBID: artistMBID,
                dimension: dimension,
                layout: layout,
                imageSize: imageSize,
                options: options
            )
        )
    }

    public func playlistArtwork(
        playlistMBID: UUID,
        dimension: Int,
        layout: LBArtGridLayout
    ) async throws -> LBGeneratedArtwork? {
        try await apiClient.execute(
            try PlaylistArtworkRequest(
                playlistMBID: playlistMBID,
                dimension: dimension,
                layout: layout
            )
        )
    }
}
