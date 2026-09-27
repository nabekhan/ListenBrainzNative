// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBRecordingsTests {
    @Test("submitFeedback with mbid")
    func submitFeedbackMbid() async throws {
        let mbid = UUID(uuidString: "abababab-abab-abab-abab-abababababab")!

        let client = LBRecordingsClient(MockAPIClient(result: .success(NoResult())))
        _ = try await client.submitFeedback(mbid: mbid, score: .love)
        let request = try #require(((client.apiClient as? MockAPIClient)?.request as? RecordingFeedbackRequest)?.data)

        #expect(request.body?.recordingMbid == mbid)
        #expect(request.body?.recordingMsid == nil)
        #expect(request.body?.score == 1)
    }

    @Test("submitFeedback with msid")
    func submitFeedbackMsid() async throws {
        let msid = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!

        let client = LBRecordingsClient(MockAPIClient(result: .success(NoResult())))
        _ = try await client.submitFeedback(msid: msid, score: .hate)
        let request = try #require(((client.apiClient as? MockAPIClient)?.request as? RecordingFeedbackRequest)?.data)

        #expect(request.body?.recordingMbid == nil)
        #expect(request.body?.recordingMsid == msid)
        #expect(request.body?.score == -1)
    }

    @Test("LBFeedback deserialization")
    func decodeFeedback() async throws {
        let raw = """
        {"created": 1736100000,
           "recording_mbid": "9d763275-0b67-4edf-8aee-3d9511068716",
           "recording_msid": null,
           "score": 1,
           "track_metadata": {"artist_name": "Kylie Minogue",
                              "mbid_mapping": {"artist_mbids": ["2fddb92d-24b2-46a5-bf28-3aed46f4684c"],
                                               "artists": [{"artist_credit_name": "Kylie Minogue",
                                                            "artist_mbid": "2fddb92d-24b2-46a5-bf28-3aed46f4684c",
                                                            "join_phrase": ""}],
                                               "caa_id": 13226700705,
                                               "caa_release_mbid": "8d3e2f07-e3f4-4c41-942a-54b59a812b1b",
                                               "recording_mbid": "9d763275-0b67-4edf-8aee-3d9511068716",
                                               "release_mbid": "7421153c-1740-471e-ad2d-e3741b9a3b96"},
                              "release_name": "Fever",
                              "track_name": "Can’t Get You Out of My Head"},
           "user_id": "a_user"}
        """

        let feedback = try JSONDecoder.ListenBrainz.decode(LBFeedback.self, from: raw.data(using: .utf8)!)
        #expect(feedback.score == .love)
        #expect(feedback.trackMetadata?.mbidMapping?.releaseMbid == UUID(uuidString: "7421153c-1740-471e-ad2d-e3741b9a3b96")!)
    }

    @Test("MSID-only feedback deserializes without a recording MBID")
    func decodeMSIDOnlyFeedback() throws {
        let raw = """
        {"created": 1736100000,
         "recording_msid": "12121212-1212-1212-1212-121212121212",
         "score": -1,
         "user_id": "a_user"}
        """

        let feedback = try JSONDecoder.ListenBrainz.decode(LBFeedback.self, from: Data(raw.utf8))

        #expect(feedback.recordingMbid == nil)
        #expect(feedback.recordingMsid == UUID(uuidString: "12121212-1212-1212-1212-121212121212"))
        #expect(feedback.score == .hate)
    }

    @Test("User feedback page preserves pagination metadata and legacy list API")
    func userFeedbackPage() async throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            LBFeedbackPage.self,
            from: Data("""
            {"count": 1,
             "feedback": [{"created": 1736100000,
                            "recording_mbid": "9d763275-0b67-4edf-8aee-3d9511068716",
                            "score": 1,
                            "user_id": "a_user"}],
             "offset": 25,
             "total_count": 37}
            """.utf8)
        )
        let mock = MockAPIClient(result: .success(response))
        let page = try await LBRecordingsClient(mock).feedbackPage(
            user: "listener", score: .love, count: 10, offset: 25, metadata: true
        )

        #expect(page.count == 1)
        #expect(page.offset == 25)
        #expect(page.totalCount == 37)
        #expect(page.feedback.count == 1)
        let request = try #require(mock.request as? RecordingUserFeedbackRequest)
        #expect(request.data.path == "/1/feedback/user/listener/get-feedback")
        #expect(request.data.queryItems["score"] == ["1"])
        #expect(request.data.queryItems["count"] == ["10"])
        #expect(request.data.queryItems["offset"] == ["25"])
        #expect(request.data.queryItems["metadata"] == ["true"])

        let legacyMock = MockAPIClient(result: .success(response))
        let legacy = try await LBRecordingsClient(legacyMock).getFeedback(
            user: "listener", score: .love, count: 10, offset: 25, metadata: true
        )
        #expect(legacy == page.feedback)
    }

    @Test("Feedback lookup omits MSID-only rows from its MBID map")
    func feedbackForRecordingsOmitsMSIDOnlyRows() async throws {
        let mbid = UUID(uuidString: "9d763275-0b67-4edf-8aee-3d9511068716")!
        let response = try JSONDecoder.ListenBrainz.decode(
            RecordingFeedbackForRequest.Result.self,
            from: Data("""
            {"feedback": [
                {"recording_mbid": "9d763275-0b67-4edf-8aee-3d9511068716",
                 "score": 1, "user_id": "a_user"},
                {"recording_msid": "12121212-1212-1212-1212-121212121212",
                 "score": -1, "user_id": "a_user"}
            ]}
            """.utf8)
        )

        let feedback = try await LBRecordingsClient(MockAPIClient(result: .success(response)))
            .getFeedbackFor(mbids: [mbid], by: "a_user")

        #expect(feedback.count == 1)
        #expect(feedback[mbid]?.score == .love)
    }

    @Test("MBID mapping decodes URL relationships without failing a listen")
    func decodeURLRelationships() throws {
        let raw = """
        {"artist_name":"Artist","track_name":"Track","mbid_mapping":{"url_rels":[
          {"type":"free streaming","url":"https://www.deezer.com/track/3135556"},
          42,
          {"type":42,"url":false}
        ]}}
        """

        let metadata = try JSONDecoder.ListenBrainz.decode(LBTrackMetadata.self, from: raw.data(using: .utf8)!)

        #expect(metadata.mbidMapping?.urlRels.count == 2)
        #expect(metadata.mbidMapping?.urlRels.first?.type == "free streaming")
        #expect(metadata.mbidMapping?.urlRels.first?.url == "https://www.deezer.com/track/3135556")
        #expect(metadata.mbidMapping?.urlRels.last?.type == nil)
        #expect(metadata.mbidMapping?.urlRels.last?.url == nil)
    }

    @Test("MBID mapping bounds URL relationship decoding")
    func boundsURLRelationships() throws {
        let relationships = (1 ... 40)
            .map { #"{"type":"streaming","url":"https://www.deezer.com/track/\#($0)"}"# }
            .joined(separator: ",")
        let raw = #"{"artist_name":"Artist","track_name":"Track","mbid_mapping":{"url_rels":[\#(relationships)]}}"#

        let metadata = try JSONDecoder.ListenBrainz.decode(LBTrackMetadata.self, from: Data(raw.utf8))

        #expect(metadata.mbidMapping?.urlRels.count == 32)
        #expect(metadata.mbidMapping?.urlRels.last?.url == "https://www.deezer.com/track/32")
    }
}
