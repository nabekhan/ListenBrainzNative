// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A bounded, server-calculated list of the people who listen most to one
/// canonical artist or release group.
public struct LBTopListeners: Decodable, Sendable {
    public let artistMBID: String?
    public let artistName: String?
    public let releaseGroupMBID: String?
    public let releaseGroupName: String?
    public let artistMBIDs: [String]?
    public let coverArtArchiveID: Int?
    public let coverArtArchiveReleaseMBID: String?
    public let listeners: [Listener]
    public let totalListenCount: Int?
    public let totalUserCount: Int?
    public let range: String?
    public let from: Date?
    public let to: Date?
    public let lastUpdated: Int?

    public struct Listener: Decodable, Sendable {
        public let userName: String
        public let listenCount: Int

        enum CodingKeys: String, CodingKey {
            case userName, listenCount
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            userName = (try? values.decode(String.self, forKey: .userName)) ?? ""
            listenCount = LBTopListeners.integer(for: .listenCount, in: values) ?? 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case artistMBID = "artistMbid"
        case artistName
        case releaseGroupMBID = "releaseGroupMbid"
        case releaseGroupName
        case artistMBIDs = "artistMbids"
        case coverArtArchiveID = "caaId"
        case coverArtArchiveReleaseMBID = "caaReleaseMbid"
        case listeners, totalListenCount, totalUserCount, range
        case from = "fromTs", to = "toTs", lastUpdated
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        artistMBID = try? values.decode(String.self, forKey: .artistMBID)
        artistName = try? values.decode(String.self, forKey: .artistName)
        releaseGroupMBID = try? values.decode(String.self, forKey: .releaseGroupMBID)
        releaseGroupName = try? values.decode(String.self, forKey: .releaseGroupName)
        artistMBIDs = try? values.decode([String].self, forKey: .artistMBIDs)
        coverArtArchiveID = Self.integer(for: .coverArtArchiveID, in: values)
        coverArtArchiveReleaseMBID = try? values.decode(String.self, forKey: .coverArtArchiveReleaseMBID)
        listeners = (try? values.decode([Listener].self, forKey: .listeners)) ?? []
        totalListenCount = Self.integer(for: .totalListenCount, in: values)
        totalUserCount = Self.integer(for: .totalUserCount, in: values)
        range = try? values.decode(String.self, forKey: .range)
        from = try? values.decode(Date.self, forKey: .from)
        to = try? values.decode(Date.self, forKey: .to)
        lastUpdated = Self.integer(for: .lastUpdated, in: values)
    }

    fileprivate static func integer<Key: CodingKey>(
        for key: Key,
        in values: KeyedDecodingContainer<Key>
    ) -> Int? {
        if let value = try? values.decode(Int.self, forKey: key) { return value }
        guard let value = try? values.decode(String.self, forKey: key) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
