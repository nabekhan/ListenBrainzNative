// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A server-calculated breakdown of listened artists by their country of origin.
///
/// The same model is returned for a user and for the sitewide endpoint. The
/// latter deliberately omits `user_id`.
public struct LBArtistMap: Decodable {
    public let userID: String?
    public let artistMap: [Country]
    public let range: String
    public let from: Date
    public let to: Date
    public let lastUpdated: Int

    public struct Country: Decodable {
        public let country: String
        public let artistCount: Int
        public let listenCount: Int
        public let artists: [Artist]

        enum CodingKeys: String, CodingKey {
            case country
            case artistCount
            case listenCount
            case artists
        }

        /// Older aggregates occasionally contain absent or string-encoded
        /// numbers. Preserve the response and let the app-domain model discard
        /// unusable rows instead of making the full map unavailable.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            country = (try? values.decode(String.self, forKey: .country)) ?? ""
            artistCount = Self.integer(for: .artistCount, in: values) ?? 0
            listenCount = Self.integer(for: .listenCount, in: values) ?? 0
            artists = (try? values.decode([Artist].self, forKey: .artists)) ?? []
        }

        private static func integer(
            for key: CodingKeys,
            in values: KeyedDecodingContainer<CodingKeys>
        ) -> Int? {
            if let value = try? values.decode(Int.self, forKey: key) { return value }
            guard let value = try? values.decode(String.self, forKey: key) else { return nil }
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public struct Artist: Decodable {
        public let artistName: String
        public let artistMBID: String?
        public let listenCount: Int

        enum CodingKeys: String, CodingKey {
            case artistName
            case artistMBID = "artistMbid"
            case listenCount
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            artistName = (try? values.decode(String.self, forKey: .artistName)) ?? ""
            artistMBID = try? values.decode(String.self, forKey: .artistMBID)
            if let value = try? values.decode(Int.self, forKey: .listenCount) {
                listenCount = value
            } else if let value = try? values.decode(String.self, forKey: .listenCount),
                let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                listenCount = parsed
            } else {
                listenCount = 0
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case artistMap
        case range
        case from = "fromTs"
        case to = "toTs"
        case lastUpdated
    }
}
