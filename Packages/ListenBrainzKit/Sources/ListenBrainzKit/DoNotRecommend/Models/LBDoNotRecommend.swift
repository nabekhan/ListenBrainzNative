// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A MusicBrainz entity type supported by ListenBrainz' do-not-recommend API.
public enum LBDoNotRecommendEntity: String, Codable, CaseIterable, Sendable {
    case artist
    case release
    case releaseGroup = "release_group"
    case recording
}

/// One active do-not-recommend preference returned by ListenBrainz.
public struct LBDoNotRecommendEntry: Decodable, Equatable, Sendable {
    public let entity: LBDoNotRecommendEntity
    public let entityMBID: UUID
    public let until: Date?
    public let created: Date

    enum CodingKeys: String, CodingKey {
        case entity
        case entityMBID = "entityMbid"
        case until, created
    }

    public init(entity: LBDoNotRecommendEntity, entityMBID: UUID, until: Date?, created: Date) {
        self.entity = entity
        self.entityMBID = entityMBID
        self.until = until
        self.created = created
    }
}

/// One paginated, oldest-first page of a user's active preferences.
public struct LBDoNotRecommendPage: Decodable, Equatable, Sendable {
    public let entries: [LBDoNotRecommendEntry]
    public let totalCount: Int
    public let count: Int
    public let offset: Int
    public let userID: String

    enum CodingKeys: String, CodingKey {
        case entries = "results"
        case totalCount = "totalCount"
        case count, offset
        case userID = "userId"
    }

    public init(entries: [LBDoNotRecommendEntry], totalCount: Int, count: Int, offset: Int, userID: String) {
        self.entries = entries
        self.totalCount = totalCount
        self.count = count
        self.offset = offset
        self.userID = userID
    }
}

/// The status returned after adding or removing a preference.
public struct LBDoNotRecommendStatus: Decodable, Equatable, Sendable {
    public let status: String

    public init(status: String) { self.status = status }
}
