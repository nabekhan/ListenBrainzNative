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

    @Test("Recommendation feedback mutations use exact paths and JSON bodies")
    func feedbackMutationRequests() async throws {
        let recordingMBID = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
        let status = LBRecommendationFeedbackStatus(status: "ok")

        let submitMock = MockAPIClient(result: .success(status))
        let submitResult = try await LBRecommendationsClient(submitMock).submitFeedback(
            recordingMBID: recordingMBID,
            rating: .badRecommendation
        )
        let submit = try #require(submitMock.request as? SubmitRecommendationFeedbackRequest)
        #expect(submitResult.status == "ok")
        #expect(submit.data.path == "/1/recommendation/feedback/submit")
        #expect(submit.data.method == .post)
        #expect(submit.data.headers["Content-Type"] == "application/json")
        #expect(submit.data.statusErrors == [400: .invalidJSON, 401: .invalidAuth])
        #expect(try jsonObject(submit.data.body) as? [String: String] == [
            "recording_mbid": recordingMBID.uuidString,
            "rating": "bad_recommendation",
        ])

        let deleteMock = MockAPIClient(result: .success(status))
        let deleteResult = try await LBRecommendationsClient(deleteMock).clearFeedback(
            recordingMBID: recordingMBID
        )
        let delete = try #require(deleteMock.request as? DeleteRecommendationFeedbackRequest)
        #expect(deleteResult.status == "ok")
        #expect(delete.data.path == "/1/recommendation/feedback/delete")
        #expect(delete.data.method == .post)
        #expect(delete.data.headers["Content-Type"] == "application/json")
        #expect(delete.data.statusErrors == [400: .invalidJSON, 401: .invalidAuth])
        #expect(try jsonObject(delete.data.body) as? [String: String] == [
            "recording_mbid": recordingMBID.uuidString,
        ])
    }

    @Test("Recommendation feedback reads use documented paging and batch queries")
    func feedbackReadRequests() async throws {
        let first = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
        let second = UUID(uuidString: "a6081bc1-2a76-4984-b21f-38bc3dcca3a5")!
        let page = recommendationFeedbackPage()

        let pageMock = MockAPIClient(result: .success(page))
        let result = try await LBRecommendationsClient(pageMock).feedback(
            user: "listener",
            rating: .love,
            count: 4_000,
            offset: -2
        )
        let request = try #require(pageMock.request as? UserRecommendationFeedbackRequest)
        #expect(request.data.path == "/1/recommendation/feedback/user/listener")
        #expect(!request.data.preservesTrailingSlash)
        #expect(request.data.queryItems == [
            "rating": ["love"],
            "count": ["1000"],
            "offset": ["0"],
        ])
        #expect(request.data.statusErrors == [400: .badRequest, 404: .notFound])
        #expect(result.totalCount == 7)

        let batch = LBRecommendationFeedbackBatch(feedback: page.feedback, userName: "listener")
        let batchMock = MockAPIClient(result: .success(batch))
        let batchResult = try await LBRecommendationsClient(batchMock).feedback(
            user: "listener",
            recordingMBIDs: [first, second]
        )
        let batchRequest = try #require(batchMock.request as? BatchedRecommendationFeedbackRequest)
        #expect(batchRequest.data.path == "/1/recommendation/feedback/user/listener/recordings")
        #expect(batchRequest.data.queryItems == [
            "mbids": ["\(first.uuidString),\(second.uuidString)"],
        ])
        #expect(batchRequest.data.statusErrors == [400: .badRequest, 404: .notFound])
        #expect(batchResult.feedback.map(\.recordingMBID) == page.feedback.map(\.recordingMBID))

        let emptyBatchMock = MockAPIClient(result: .success(batch))
        await #expect(throws: LBError.invalidParam) {
            _ = try await LBRecommendationsClient(emptyBatchMock).feedback(
                user: "listener",
                recordingMBIDs: []
            )
        }
        #expect(emptyBatchMock.request == nil)
    }

    @Test("Recommendation feedback pages and batches decode Unix dates and every rating")
    func feedbackDecoding() throws {
        let page = try JSONDecoder.ListenBrainz.decode(
            LBRecommendationFeedbackPage.self,
            from: Data(#"""
            {"feedback":[
              {"created":1700000123,"recording_mbid":"526bd613-fddd-4bd6-9137-ab709ac74cab","rating":"like"},
              {"created":1700000122,"recording_mbid":"a6081bc1-2a76-4984-b21f-38bc3dcca3a5","rating":"bad_recommendation"}
            ],"count":2,"total_count":7,"offset":3,"user_name":"listener"}
            """#.utf8)
        )
        let batch = try JSONDecoder.ListenBrainz.decode(
            LBRecommendationFeedbackBatch.self,
            from: Data(#"""
            {"feedback":[
              {"created":1700000121,"recording_mbid":"2fb127aa-3181-4f36-8a7d-d59f66e85360","rating":"love"},
              {"created":1700000120,"recording_mbid":"77172070-739c-4e05-9602-816b0e5d3006","rating":"dislike"},
              {"created":1700000119,"recording_mbid":"0f58c1b6-9501-4f80-8a11-d2b7be3d6ba0","rating":"hate"}
            ],"user_name":"listener"}
            """#.utf8)
        )

        #expect(page.feedback.map(\.rating) == [.like, .badRecommendation])
        #expect(page.feedback.first?.created.timeIntervalSince1970 == 1_700_000_123)
        #expect(page.count == 2)
        #expect(page.totalCount == 7)
        #expect(page.offset == 3)
        #expect(page.userName == "listener")
        #expect(batch.feedback.map(\.rating) == [.love, .dislike, .hate])
        #expect(batch.userName == "listener")
        #expect(LBRecommendationFeedbackRating.allCases == [
            .like, .love, .dislike, .hate, .badRecommendation,
        ])
    }

    private func recommendationFeedbackPage() -> LBRecommendationFeedbackPage {
        LBRecommendationFeedbackPage(
            feedback: [
                LBRecommendationFeedback(
                    created: Date(timeIntervalSince1970: 1_700_000_123),
                    recordingMBID: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!,
                    rating: .love
                ),
            ],
            count: 1,
            totalCount: 7,
            offset: 0,
            userName: "listener"
        )
    }

    private func jsonObject<Body: Encodable>(_ body: Body?) throws -> Any? {
        guard let body else { return nil }
        return try JSONSerialization.jsonObject(with: JSONEncoder.ListenBrainz.encode(body))
    }
}
