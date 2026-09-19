// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Listen counts for ListenBrainz's leading artists and their release groups.
///
/// The server returns a bounded ranked sample, rather than a complete listening
/// history. Albums are release groups used to aggregate the matching listens.
public struct LBArtistActivity: Decodable {
    public let userID: String?
    public let artistActivity: [Artist]
    public let range: String
    public let from: Date
    public let to: Date
    public let lastUpdated: Int

    public struct Artist: Decodable {
        /// The credited artist name used by the statistic.
        public let name: String
        /// The canonical artist name when the server resolved one.
        public let artistName: String?
        public let artistMBID: String?
        public let listenCount: Int
        public let albums: [Album]

        public struct Album: Decodable {
            public let name: String
            public let listenCount: Int
            public let releaseGroupMBID: String?

            enum CodingKeys: String, CodingKey {
                case name, listenCount, releaseGroupMBID = "releaseGroupMbid"
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                name = (try? values.decode(String.self, forKey: .name)) ?? ""
                listenCount = Self.integer(for: .listenCount, in: values) ?? 0
                releaseGroupMBID = try? values.decode(String.self, forKey: .releaseGroupMBID)
            }
        }

        enum CodingKeys: String, CodingKey {
            case name, artistName, artistMBID = "artistMbid", listenCount, albums
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? values.decode(String.self, forKey: .name)) ?? ""
            artistName = try? values.decode(String.self, forKey: .artistName)
            artistMBID = try? values.decode(String.self, forKey: .artistMBID)
            listenCount = LBArtistActivity.integer(for: .listenCount, in: values) ?? 0
            albums = (try? values.decode([Album].self, forKey: .albums)) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case userID = "userId", artistActivity, range, from = "fromTs", to = "toTs", lastUpdated
    }

    fileprivate static func integer<Key: CodingKey>(for key: Key, in values: KeyedDecodingContainer<Key>) -> Int? {
        if let value = try? values.decode(Int.self, forKey: key) { return value }
        guard let value = try? values.decode(String.self, forKey: key) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension LBArtistActivity.Artist.Album {
    static func integer(for key: CodingKeys, in values: KeyedDecodingContainer<CodingKeys>) -> Int? {
        if let value = try? values.decode(Int.self, forKey: key) { return value }
        guard let value = try? values.decode(String.self, forKey: key) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
