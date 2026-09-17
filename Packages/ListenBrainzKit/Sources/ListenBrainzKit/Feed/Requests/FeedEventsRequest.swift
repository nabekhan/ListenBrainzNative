// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct FeedEventsRequest: APIRequest {
    typealias Result = LBFeedPageResponse

    enum Kind {
        case events
        case following
        case similar

        var suffix: String {
            switch self {
            case .events: ""
            case .following: "/listens/following"
            case .similar: "/listens/similar"
            }
        }
    }

    let data: APIRequestData<NoBody>

    init(
        username: String,
        kind: Kind,
        count: Int,
        maxTimestamp: Date?,
        minTimestamp: Date?
    ) {
        var queryItems = ["count": [String(min(max(count, 1), 1_000))]]
        if let maxTimestamp {
            queryItems["max_ts"] = [String(Int(maxTimestamp.timeIntervalSince1970))]
        }
        if let minTimestamp {
            queryItems["min_ts"] = [String(Int(minTimestamp.timeIntervalSince1970))]
        }

        data = .init(
            path: "/1/user/\(username)/feed/events\(kind.suffix)",
            method: .get,
            queryItems: queryItems,
            statusErrors: [
                400: .badRequest,
                401: .invalidAuth,
                403: .forbidden,
                404: .notFound,
            ]
        )
    }
}
