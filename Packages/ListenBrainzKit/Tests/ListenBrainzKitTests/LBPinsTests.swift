// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ListenBrainzKit

@Suite struct LBPinsTests {
    @Test("Pins decode embedded metadata and nullable current pins")
    func decodePins() throws {
        let current = try JSONDecoder.ListenBrainz.decode(CurrentPinResponse.self, from: Data("""
        {"pinned_recording":{"row_id":17,"created":1700000000,"pinned_until":1700600000,"recording_mbid":"40ef0ae1-5626-43eb-838f-1b34187519bf","recording_msid":null,"blurb_content":"A note","user_name":"listener","track_metadata":{"artist_name":"Artist","track_name":"Track","release_name":"Album"}}}
        """.utf8))
        let pin = try #require(current.pinnedRecording)
        #expect(pin.rowID == 17)
        #expect(pin.trackMetadata?.track == "Track")
        #expect(pin.recordingMSID == nil)

        let empty = try JSONDecoder.ListenBrainz.decode(CurrentPinResponse.self, from: Data("{\"pinned_recording\":null}".utf8))
        #expect(empty.pinnedRecording == nil)
    }

    @Test("Pin paths, bounds, and server-default expiry semantics")
    func requestSemantics() throws {
        let history = PinHistoryRequest(user: "test user", count: 101, offset: -2)
        #expect(history.data.path == "/1/test user/pins")
        #expect(history.data.queryItems["count"] == ["100"])
        #expect(history.data.queryItems["offset"] == ["0"])
        #expect(UnpinRequest().data.path == "/1/pin/unpin")
        #expect(DeletePinRequest(rowID: 4).data.path == "/1/pin/delete/4")
        #expect(UpdatePinBlurbRequest(rowID: 4, blurb: "Note").data.path == "/1/pin/update/4")

        let request = CreatePinRequest(recordingMBID: UUID(), recordingMSID: nil, blurb: nil, pinnedUntil: nil)
        let data = try JSONEncoder.ListenBrainz.encode(request.data.body!)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["pinned_until"] == nil)
        #expect(object?["blurb_content"] == nil)
    }

    @Test("Pins client rejects an identifierless create")
    func invalidCreate() async {
        let client = LBPinsClient(MockAPIClient(result: .failure(.unknownError)))
        await #expect(throws: LBError.invalidParam) {
            try await client.create()
        }
    }

    @Test("Pins reject blurbs over the documented limit before transport")
    func overlongBlurb() async {
        let client = LBPinsClient(MockAPIClient(result: .failure(.unknownError)))
        await #expect(throws: LBError.invalidParam) {
            try await client.create(recordingMBID: UUID(), blurb: String(repeating: "x", count: 281))
        }
        await #expect(throws: LBError.invalidParam) {
            try await client.updateBlurb(rowID: 1, blurb: String(repeating: "x", count: 281))
        }
    }

    @Test("Pin blurb updates decode the server's Boolean status")
    func updateBlurbStatus() async throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            UpdatePinStatusResponse.self,
            from: Data(#"{"status":true}"#.utf8)
        )
        #expect(response.status)

        let mock = MockAPIClient(result: .success(response))
        try await LBPinsClient(mock).updateBlurb(rowID: 17, blurb: "Updated note")
        #expect((mock.request as? UpdatePinBlurbRequest)?.data.path == "/1/pin/update/17")
    }

    @Test("A false pin-update status is not reported as success")
    func failedUpdateBlurbStatus() async {
        let response = UpdatePinStatusResponse(status: false)
        let client = LBPinsClient(MockAPIClient(result: .success(response)))

        await #expect(throws: LBError.notFound) {
            try await client.updateBlurb(rowID: 17, blurb: "Too late")
        }
    }
}
