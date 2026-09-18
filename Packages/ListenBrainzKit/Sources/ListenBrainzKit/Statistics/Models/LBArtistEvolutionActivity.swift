// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A user's most-listened-to artists, broken down across time buckets.
public struct LBArtistEvolutionActivity: Decodable {
    public let userID: String
    public let artistEvolutionActivity: [Entry]
    public let range: String
    public let from: Date
    public let to: Date
    public let lastUpdated: Int

    public struct Entry: Decodable {
        /// The bucket label supplied by ListenBrainz. Its meaning depends on `range`.
        ///
        /// The API documents this as a string, but production fixtures can encode
        /// numeric day or year buckets as JSON numbers, so both forms are accepted.
        public let timeUnit: String
        public let artistMBID: String?
        public let artistName: String
        public let listenCount: Int

        enum CodingKeys: String, CodingKey {
            case timeUnit
            case artistMBID = "artistMbid"
            case artistName
            case listenCount
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? values.decode(String.self, forKey: .timeUnit) {
                timeUnit = string
            } else {
                timeUnit = String(try values.decode(Int.self, forKey: .timeUnit))
            }
            artistMBID = try values.decodeIfPresent(String.self, forKey: .artistMBID)
            artistName = try values.decode(String.self, forKey: .artistName)
            listenCount = try values.decode(Int.self, forKey: .listenCount)
        }
    }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case artistEvolutionActivity
        case range
        case from = "fromTs"
        case to = "toTs"
        case lastUpdated
    }
}
