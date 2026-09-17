// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBTopReleaseGroups: Decodable {
    public let releaseGroups: [ReleaseGroup]
    /// Total release groups listened to beyond what's in .releaseGroups. Only populated from user
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
        case totalReleaseGroupCount
        case lastUpdated
        case from = "fromTs"
        case to = "toTs"
    }
}
