// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Daily-rebuilt global ListenBrainz counts for one canonical MusicBrainz entity.
///
/// A `nil` count means ListenBrainz has no popularity record for the entity. It is
/// intentionally distinct from a count of zero.
public struct LBPopularity: Decodable, Equatable, Sendable {
    public let mbid: UUID
    public let totalListenCount: Int?
    public let totalUserCount: Int?

    private enum CodingKeys: String, CodingKey {
        case artistMBID = "artistMbid"
        case recordingMBID = "recordingMbid"
        case releaseMBID = "releaseMbid"
        case releaseGroupMBID = "releaseGroupMbid"
        case totalListenCount
        case totalUserCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifiers = [
            try container.decodeIfPresent(UUID.self, forKey: .artistMBID),
            try container.decodeIfPresent(UUID.self, forKey: .recordingMBID),
            try container.decodeIfPresent(UUID.self, forKey: .releaseMBID),
            try container.decodeIfPresent(UUID.self, forKey: .releaseGroupMBID),
        ].compactMap { $0 }

        guard identifiers.count == 1, let mbid = identifiers.first else {
            throw DecodingError.dataCorruptedError(
                forKey: .artistMBID,
                in: container,
                debugDescription: "A popularity row must contain exactly one canonical entity MBID."
            )
        }

        self.mbid = mbid
        self.totalListenCount = try container.decodeIfPresent(Int.self, forKey: .totalListenCount)
        self.totalUserCount = try container.decodeIfPresent(Int.self, forKey: .totalUserCount)
    }
}
