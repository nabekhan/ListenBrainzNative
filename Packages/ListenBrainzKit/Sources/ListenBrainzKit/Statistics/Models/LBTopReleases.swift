// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBTopReleases: Decodable {
    public let releases: [Release]
    /// Total releases listened to beyond what's in .releases.
    /// Only populated for user requests
    public let totalReleaseCount: Int?
    public let lastUpdated: Date
    public let from: Date
    public let to: Date

    public struct Release: Decodable {
        /// Only populated for user requests
        public let artists: [Artist]?
        public let artistMbids: [UUID]?
        public let artistName: String
        public let listenCount: Int
        public let releaseMbid: UUID?
        public let releaseName: String
    }

    public struct Artist: Decodable {
        public let name: String
        public let mbid: UUID
        public let joinPhrase: String

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case name = "artistCreditName"
            case mbid = "artistMbid"
            case joinPhrase
        }
    }

    enum CodingKeys: String, CodingKey {
        case releases
        case totalReleaseCount
        case lastUpdated
        case from = "fromTs"
        case to = "toTs"
    }
}
