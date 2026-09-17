// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

struct RecordingRecommendationsRequest: APIRequest {
    typealias Result = RecordingRecommendationsResponse

    let data: APIRequestData<NoBody>

    init(username: String, count: Int, offset: Int) {
        data = .init(
            path: "/1/cf/recommendation/user/\(username)/recording",
            method: .get,
            queryItems: [
                "count": [String(min(max(count, 1), 1_000))],
                "offset": [String(max(offset, 0))],
            ],
            statusErrors: [204: .noContent, 404: .notFound]
        )
    }
}
