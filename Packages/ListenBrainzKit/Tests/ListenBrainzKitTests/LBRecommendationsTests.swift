// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBRecommendationsTests {
    @Test("Recording recommendations use the public CF endpoint and clamp paging")
    func requestPathAndPaging() async throws {
        let data = Data(#"""
        {"payload":{
          "model_id":"model-1",
          "model_url":"https://example.com/model",
          "mbids":[],
          "entity":"recording",
          "user_name":"listener",
          "last_updated":1700000000,
          "count":0,
          "total_mbid_count":0,
          "offset":0
        }}
        """#.utf8)
        let response = try JSONDecoder.ListenBrainz.decode(
            RecordingRecommendationsResponse.self,
            from: data
        )
        let mock = MockAPIClient(result: .success(response))
        let client = LBRecommendationsClient(mock)

        _ = try await client.recordings(user: "listener", count: 4_000, offset: -7)

        let request = try #require(mock.request as? RecordingRecommendationsRequest)
        #expect(request.data.path == "/1/cf/recommendation/user/listener/recording")
        #expect(!request.data.preservesTrailingSlash)
        #expect(request.data.queryItems["count"] == ["1000"])
        #expect(request.data.queryItems["offset"] == ["0"])
    }

    @Test("Recording recommendations preserve score, order, and optional discovery date")
    func decoding() throws {
        let data = Data(#"""
        {"payload":{
          "model_id":"model-1",
          "model_url":"https://example.com/model",
          "mbids":[
            {"recording_mbid":"526bd613-fddd-4bd6-9137-ab709ac74cab","score":9.345,"latest_listened_at":"2021-12-17T05:32:11.000Z"},
            {"recording_mbid":"a6081bc1-2a76-4984-b21f-38bc3dcca3a5","score":6.998,"latest_listened_at":null}
          ],
          "entity":"recording",
          "user_name":"listener",
          "last_updated":1700000000,
          "count":2,
          "total_mbid_count":30,
          "offset":0
        }}
        """#.utf8)

        let page = try JSONDecoder.ListenBrainz.decode(
            RecordingRecommendationsResponse.self,
            from: data
        ).payload

        #expect(page.recommendations.map(\.recordingMBID.uuidString) == [
            "526BD613-FDDD-4BD6-9137-AB709AC74CAB",
            "A6081BC1-2A76-4984-B21F-38BC3DCCA3A5",
        ])
        #expect(page.recommendations.first?.score == 9.345)
        #expect(page.recommendations.first?.latestListenedAt != nil)
        #expect(page.recommendations.last?.latestListenedAt == nil)
        #expect(page.totalCount == 30)
    }

    @Test("HTTP 204 is an unavailable recommendation state")
    func noContent() async throws {
        let client = LBRecommendationsClient(MockAPIClient(result: .failure(.noContent)))
        let result = try await client.recordings(user: "listener")
        #expect(result == nil)
    }
}
