// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBTopReleaseGroups: Decodable {
    public let releaseGroups: [ReleaseGroup]
    /// Number of rows the server accepted for this page.
    public let requestedCount: Int?
    /// Zero-based page offset returned by the server.
    public let offset: Int?
    /// Statistics range returned by the server.
    public let range: String?
    /// Total release groups available for this range.
    public let totalReleaseGroupCount: Int?
    public let lastUpdated: Date
    public let from: Date
    public let to: Date

    public struct ReleaseGroup: Decodable {
        public let artistMbids: [UUID]?
        public let artistName: String
        /// Only populated by user request
        public let artists: [Artist]?
        public let releaseGroupMbid: UUID?
        public let releaseGroupName: String
        public let listenCount: Int
    }

    public struct Artist: Decodable {
        public let credit: String
        public let mbid: UUID

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case credit = "artistCreditName"
            case mbid = "artistMbid"
        }
    }

    enum CodingKeys: String, CodingKey {
        case releaseGroups
        case requestedCount = "count"
        case offset
        case range
        case totalReleaseGroupCount
        case lastUpdated
        case from = "fromTs"
        case to = "toTs"
    }
}
