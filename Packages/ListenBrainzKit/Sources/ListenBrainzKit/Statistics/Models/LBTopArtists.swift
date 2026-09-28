// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBTopArtists: Decodable {
    public let artists: [Artist]
    /// Number of rows the server accepted for this page.
    public let requestedCount: Int?
    /// Zero-based page offset returned by the server.
    public let offset: Int?
    /// Statistics range returned by the server.
    public let range: String?
    /// Total artists available for this range.
    public let totalArtistCount: Int?
    public let lastUpdated: Date
    public let from: Date
    public let to: Date

    public struct Artist: Decodable {
        public let mbid: UUID?
        public let name: String
        public let listenCount: Int

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case mbid = "artistMbid"
            case name = "artistName"
            case listenCount
        }
    }

    enum CodingKeys: String, CodingKey {
        case artists
        case requestedCount = "count"
        case offset
        case range
        case totalArtistCount
        case lastUpdated
        case from = "fromTs"
        case to = "toTs"
    }
}
