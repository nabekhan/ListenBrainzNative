// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

struct UserPlayingNowRequest: APIRequest {
    static let maximumPayloadSize = 1 * 1_024 * 1_024
    let data: APIRequestData<NoBody>

    init(username: String) {
        self.data = .init(path: "/1/user/\(username)/playing-now",
                          method: .get,
                          statusErrors: [404: .notFound],
                          maximumResponseBytes: Self.maximumPayloadSize)
    }

    struct Result: Decodable {
        var payload: Payload
    }

    struct Payload: Decodable {
        var count: Int
        var playingNow: Bool
        var userId: String
        var listens: [Listen]
    }

    struct Listen: Decodable {
        var playingNow: Bool?
        var trackMetadata: LBTrackMetadata?
    }
}
