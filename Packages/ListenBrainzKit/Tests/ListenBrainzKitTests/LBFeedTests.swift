// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBFeedTests {
    @Test("Feed endpoints use documented paths, timestamps, and count bounds")
    func requestPathsAndQueryItems() async throws {
        let response = try pageResponse()
        let maximum = Date(timeIntervalSince1970: 1_700_000_123.9)
        let minimum = Date(timeIntervalSince1970: 1_600_000_456.1)

        let aggregateMock = MockAPIClient(result: .success(response))
        _ = try await LBFeedClient(aggregateMock).events(
            username: "listener",
            count: 4_000,
            maxTimestamp: maximum,
            minTimestamp: minimum
        )
        let aggregate = try #require(aggregateMock.request as? FeedEventsRequest)
        #expect(aggregate.data.path == "/1/user/listener/feed/events")
        #expect(!aggregate.data.preservesTrailingSlash)
        #expect(aggregate.data.queryItems["count"] == ["1000"])
        #expect(aggregate.data.queryItems["max_ts"] == ["1700000123"])
        #expect(aggregate.data.queryItems["min_ts"] == ["1600000456"])

        let followingMock = MockAPIClient(result: .success(response))
        _ = try await LBFeedClient(followingMock).followingListens(username: "listener", count: -1)
        let following = try #require(followingMock.request as? FeedEventsRequest)
        #expect(following.data.path == "/1/user/listener/feed/events/listens/following")
        #expect(following.data.queryItems == ["count": ["1"]])

        let similarMock = MockAPIClient(result: .success(response))
        _ = try await LBFeedClient(similarMock).similarListens(username: "listener", count: 40)
        let similar = try #require(similarMock.request as? FeedEventsRequest)
        #expect(similar.data.path == "/1/user/listener/feed/events/listens/similar")
        #expect(similar.data.queryItems == ["count": ["40"]])
        #expect(similar.data.statusErrors[400] == .badRequest)
        #expect(similar.data.statusErrors[401] == .invalidAuth)
        #expect(similar.data.statusErrors[403] == .forbidden)
        #expect(similar.data.statusErrors[404] == .notFound)
    }

    @Test("Feed decodes every current metadata shape while ignoring new event types and fields")
    func decodingIsTolerant() throws {
        let page = try pageResponse().payload
        #expect(page.count == 5)
        #expect(page.userID == "listener")

        let listen = try #require(page.events.first)
        #expect(listen.id == nil)
        #expect(listen.eventType == "brand_new_event")
        #expect(listen.hidden == false)
        #expect(listen.similarity == 0.83)
        #expect(listen.metadata.trackMetadata?.artist == "Artist")
        #expect(listen.metadata.trackMetadata?.additionalInfo?.recordingMsid?.uuidString == "526BD613-FDDD-4BD6-9137-AB709AC74CAB")
        #expect(listen.metadata.listenedAt?.timeIntervalSince1970 == 1_700_000_000)

        let personal = page.events[1]
        #expect(personal.id == 9)
        #expect(personal.metadata.users == ["alice", "bob"])
        #expect(personal.metadata.blurbContent == "A personal note")

        let follow = page.events[2]
        #expect(follow.metadata.userName0 == "alice")
        #expect(follow.metadata.userName1 == "bob")
        #expect(follow.metadata.relationshipType == "follow")

        let detailed = page.events[3]
        #expect(detailed.metadata.message == "Welcome")
        #expect(detailed.metadata.entityID == "release-group-id")
        #expect(detailed.metadata.reviewMBID == "review-id")
        #expect(detailed.metadata.originalEventID == 4)
        #expect(detailed.metadata.originalEventType == "recording_pin")
        #expect(detailed.metadata.thankerID == 5)
        #expect(detailed.metadata.thankeeID == 6)

        let malformedTrack = page.events[4]
        #expect(malformedTrack.metadata.message == "The event still survives")
        #expect(malformedTrack.metadata.trackMetadata == nil)
        #expect(malformedTrack.metadata.playingNow == nil)
    }

    private func pageResponse() throws -> LBFeedPageResponse {
        try JSONDecoder.ListenBrainz.decode(LBFeedPageResponse.self, from: Data(#"""
        {"payload":{"count":5,"user_id":"listener","events":[
          {"event_type":"brand_new_event","user_name":"alice","created":1700000010,"hidden":false,"similarity":0.83,"metadata":{
            "listened_at":1700000000,"inserted_at":1700000001,"playing_now":false,"recording_msid":"526bd613-fddd-4bd6-9137-ab709ac74cab",
            "track_metadata":{"artist_name":"Artist","track_name":"Track","release_name":"Release","additional_info":{"recording_msid":"526bd613-fddd-4bd6-9137-ab709ac74cab","unrecognized_future_key":"kept tolerant"}},"future_key":"ignored"
          }},
          {"id":9,"event_type":"personal_recording_recommendation","user_name":"listener","created":1700000009,"hidden":false,"metadata":{"users":["alice","bob"],"blurb_content":"A personal note","track_metadata":{"artist_name":"Artist","track_name":"Track"}}},
          {"event_type":"follow","user_name":"alice","created":1700000008,"hidden":false,"metadata":{"user_name_0":"alice","user_name_1":"bob","relationship_type":"follow","created":1700000008}},
          {"id":11,"event_type":"thanks","user_name":"listener","created":1700000007,"hidden":true,"metadata":{"message":"Welcome","entity_name":"Example","entity_id":"release-group-id","entity_type":"release_group","rating":4,"text":"Great","review_mbid":"review-id","original_event_id":4,"original_event_type":"recording_pin","thanker_id":5,"thanker_username":"alice","thankee_id":6,"thankee_username":"bob","blurb_content":"Thanks","created":1700000007}},
          {"id":12,"event_type":"notification","user_name":"listenbrainz","created":1700000006,"metadata":{"message":"The event still survives","playing_now":"legacy-value","track_metadata":{"artist_name":"Artist","track_name":"Track","additional_info":{"tracknumber":"A1"}}}}
        ]}}
        """#.utf8))
    }
}
