// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A user's most-listened genres for each UTC hour.
///
/// ListenBrainz returns only its top genres per hour, so this is not a complete
/// distribution of every genre a user has heard.
public struct LBGenreActivity: Decodable {
    public let userID: String
    public let genreActivity: [Entry]
    public let range: String
    public let from: Date
    public let to: Date
    public let lastUpdated: Int

    public struct Entry: Decodable {
        public let genre: String
        public let hour: Int
        public let listenCount: Int

        enum CodingKeys: String, CodingKey {
            case genre
            case hour
            case listenCount
        }

        /// The endpoint has historically been a loosely typed aggregate. Keep
        /// a single malformed row from invalidating an otherwise useful
        /// response by accepting numeric strings and representing absent or
        /// malformed values with safe sentinels for the app-domain filter.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            genre = (try? values.decode(String.self, forKey: .genre)) ?? ""
            hour = Self.integer(for: .hour, in: values) ?? -1
            listenCount = Self.integer(for: .listenCount, in: values) ?? 0
        }

        private static func integer(
            for key: CodingKeys,
            in values: KeyedDecodingContainer<CodingKeys>
        ) -> Int? {
            if let value = try? values.decode(Int.self, forKey: key) {
                return value
            }
            guard let value = try? values.decode(String.self, forKey: key) else {
                return nil
            }
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case genreActivity
        case range
        case from = "fromTs"
        case to = "toTs"
        case lastUpdated
    }
}
