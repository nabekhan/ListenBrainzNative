// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct LBFeedPageResponse: Decodable {
    let payload: LBFeedPage
}

/// One page of events from a ListenBrainz social feed endpoint.
public struct LBFeedPage: Decodable, Equatable, Sendable {
    public let count: Int
    public let userID: String
    public let events: [LBFeedEvent]

    enum CodingKeys: String, CodingKey {
        case count
        case userID = "userId"
        case events
    }
}

/// A social-feed event. `eventType` deliberately remains a string so that
/// newly introduced server event types do not make an entire page undecodable.
public struct LBFeedEvent: Decodable, Equatable, Sendable {
    public let id: Int?
    public let eventType: String
    public let userName: String
    public let created: Date
    public let metadata: LBFeedEventMetadata
    public let hidden: Bool
    public let similarity: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case eventType
        case userName
        case created
        case metadata
        case hidden
        case similarity
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        eventType = try container.decode(String.self, forKey: .eventType)
        userName = try container.decode(String.self, forKey: .userName)
        created = try container.decode(Date.self, forKey: .created)
        metadata = try container.decodeIfPresent(LBFeedEventMetadata.self, forKey: .metadata) ?? .init()
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        similarity = try container.decodeIfPresent(Double.self, forKey: .similarity)
    }
}

/// A tolerant union of the metadata currently returned by ListenBrainz feed
/// events. Unknown keys are intentionally ignored for forward compatibility.
public struct LBFeedEventMetadata: Decodable, Equatable, Sendable {
    public let trackMetadata: LBTrackMetadata?
    public let listenedAt: Date?
    public let insertedAt: Date?
    public let playingNow: Bool?
    public let recordingMsid: UUID?
    public let blurbContent: String?
    public let users: [String]?
    public let userName0: String?
    public let userName1: String?
    public let relationshipType: String?
    public let message: String?
    public let entityName: String?
    public let entityID: String?
    public let entityType: String?
    public let rating: Int?
    public let text: String?
    public let reviewMBID: String?
    public let originalEventID: Int?
    public let originalEventType: String?
    public let thankerID: Int?
    public let thankerUsername: String?
    public let thankeeID: Int?
    public let thankeeUsername: String?
    public let created: Date?

    enum CodingKeys: String, CodingKey {
        case trackMetadata
        case listenedAt
        case insertedAt
        case playingNow
        case recordingMsid
        case blurbContent
        case users
        case userName0
        case userName1
        case relationshipType
        case message
        case entityName
        case entityID = "entityId"
        case entityType
        case rating
        case text
        case reviewMBID = "reviewMbid"
        case originalEventID = "originalEventId"
        case originalEventType
        case thankerID = "thankerId"
        case thankerUsername
        case thankeeID = "thankeeId"
        case thankeeUsername
        case created
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Feed metadata is a heterogeneous, evolving union. A malformed field
        // must not discard the whole event (or page), so each known value is
        // decoded independently and incompatible values are treated as absent.
        trackMetadata = try? container.decode(LBTrackMetadata.self, forKey: .trackMetadata)
        listenedAt = try? container.decode(Date.self, forKey: .listenedAt)
        insertedAt = try? container.decode(Date.self, forKey: .insertedAt)
        playingNow = try? container.decode(Bool.self, forKey: .playingNow)
        recordingMsid = try? container.decode(UUID.self, forKey: .recordingMsid)
        blurbContent = try? container.decode(String.self, forKey: .blurbContent)
        users = try? container.decode([String].self, forKey: .users)
        userName0 = try? container.decode(String.self, forKey: .userName0)
        userName1 = try? container.decode(String.self, forKey: .userName1)
        relationshipType = try? container.decode(String.self, forKey: .relationshipType)
        message = try? container.decode(String.self, forKey: .message)
        entityName = try? container.decode(String.self, forKey: .entityName)
        entityID = try? container.decode(String.self, forKey: .entityID)
        entityType = try? container.decode(String.self, forKey: .entityType)
        rating = try? container.decode(Int.self, forKey: .rating)
        text = try? container.decode(String.self, forKey: .text)
        reviewMBID = try? container.decode(String.self, forKey: .reviewMBID)
        originalEventID = try? container.decode(Int.self, forKey: .originalEventID)
        originalEventType = try? container.decode(String.self, forKey: .originalEventType)
        thankerID = try? container.decode(Int.self, forKey: .thankerID)
        thankerUsername = try? container.decode(String.self, forKey: .thankerUsername)
        thankeeID = try? container.decode(Int.self, forKey: .thankeeID)
        thankeeUsername = try? container.decode(String.self, forKey: .thankeeUsername)
        created = try? container.decode(Date.self, forKey: .created)
    }

    public init(
        trackMetadata: LBTrackMetadata? = nil,
        listenedAt: Date? = nil,
        insertedAt: Date? = nil,
        playingNow: Bool? = nil,
        recordingMsid: UUID? = nil,
        blurbContent: String? = nil,
        users: [String]? = nil,
        userName0: String? = nil,
        userName1: String? = nil,
        relationshipType: String? = nil,
        message: String? = nil,
        entityName: String? = nil,
        entityID: String? = nil,
        entityType: String? = nil,
        rating: Int? = nil,
        text: String? = nil,
        reviewMBID: String? = nil,
        originalEventID: Int? = nil,
        originalEventType: String? = nil,
        thankerID: Int? = nil,
        thankerUsername: String? = nil,
        thankeeID: Int? = nil,
        thankeeUsername: String? = nil,
        created: Date? = nil
    ) {
        self.trackMetadata = trackMetadata
        self.listenedAt = listenedAt
        self.insertedAt = insertedAt
        self.playingNow = playingNow
        self.recordingMsid = recordingMsid
        self.blurbContent = blurbContent
        self.users = users
        self.userName0 = userName0
        self.userName1 = userName1
        self.relationshipType = relationshipType
        self.message = message
        self.entityName = entityName
        self.entityID = entityID
        self.entityType = entityType
        self.rating = rating
        self.text = text
        self.reviewMBID = reviewMBID
        self.originalEventID = originalEventID
        self.originalEventType = originalEventType
        self.thankerID = thankerID
        self.thankerUsername = thankerUsername
        self.thankeeID = thankeeID
        self.thankeeUsername = thankeeUsername
        self.created = created
    }
}
