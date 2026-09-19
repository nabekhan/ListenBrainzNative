// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct CurrentPinRequest: APIRequest {
    typealias Result = CurrentPinResponse
    let data: APIRequestData<NoBody>
    init(user: String) {
        data = .init(path: "/1/\(user)/pins/current", method: .get, statusErrors: [404: .notFound])
    }
}

struct PinHistoryRequest: APIRequest {
    typealias Result = LBPinnedRecordingPage
    let data: APIRequestData<NoBody>
    init(user: String, count: Int, offset: Int) {
        data = .init(
            path: "/1/\(user)/pins",
            method: .get,
            queryItems: ["count": [String(min(max(count, 0), 100))], "offset": [String(max(offset, 0))]],
            statusErrors: [404: .notFound]
        )
    }
}

struct FollowingPinsRequest: APIRequest {
    typealias Result = LBFollowingPinsPage
    let data: APIRequestData<NoBody>

    init(user: String, count: Int, offset: Int) {
        data = .init(
            path: "/1/\(user)/pins/following",
            method: .get,
            queryItems: ["count": [String(min(max(count, 0), 1_000))], "offset": [String(max(offset, 0))]],
            statusErrors: [400: .badRequest, 404: .notFound]
        )
    }
}

struct CreatePinRequest: APIRequest {
    typealias Result = CreatePinResponse
    let data: APIRequestData<Body>
    init(recordingMBID: UUID?, recordingMSID: UUID?, blurb: String?, pinnedUntil: Date?) {
        data = .init(
            path: "/1/pin", method: .post, headers: ["Content-Type": "application/json"],
            body: .init(recordingMBID: recordingMBID, recordingMSID: recordingMSID, blurbContent: blurb, pinnedUntil: pinnedUntil),
            statusErrors: [400: .invalidJSON, 401: .invalidAuth]
        )
    }
    struct Body: Encodable {
        let recordingMBID: UUID?
        let recordingMSID: UUID?
        let blurbContent: String?
        let pinnedUntil: Date?
    }
}

struct UnpinRequest: APIRequest {
    typealias Result = PinStatusResponse
    let data = APIRequestData<NoBody>(path: "/1/pin/unpin", method: .post, statusErrors: [401: .invalidAuth, 404: .notFound])
}

struct DeletePinRequest: APIRequest {
    typealias Result = PinStatusResponse
    let data: APIRequestData<NoBody>
    init(rowID: Int) {
        data = .init(path: "/1/pin/delete/\(rowID)", method: .post, statusErrors: [401: .invalidAuth, 404: .notFound])
    }
}

struct UpdatePinBlurbRequest: APIRequest {
    typealias Result = UpdatePinStatusResponse
    let data: APIRequestData<Body>
    init(rowID: Int, blurb: String) {
        data = .init(path: "/1/pin/update/\(rowID)", method: .post, headers: ["Content-Type": "application/json"], body: .init(blurbContent: blurb), statusErrors: [400: .invalidJSON, 401: .invalidAuth, 403: .forbidden, 404: .notFound])
    }
    struct Body: Encodable { let blurbContent: String }
}

struct PinStatusResponse: Decodable { let status: String }
struct UpdatePinStatusResponse: Decodable { let status: Bool }
