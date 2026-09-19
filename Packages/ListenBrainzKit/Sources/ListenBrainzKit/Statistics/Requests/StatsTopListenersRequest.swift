// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct StatsTopListenersRequest: APIRequest {
    enum Entity: String, Sendable {
        case artist
        case releaseGroup = "release-group"
    }

    let data: APIRequestData<NoBody>

    init(entity: Entity, mbid: UUID, range: LBStatRange?) {
        var query = [String: [String]]()
        query.setQueryItem("range", value: range?.rawValue)
        data = .init(
            path: "/1/stats/\(entity.rawValue)/\(mbid.uuidString)/listeners",
            method: .get,
            queryItems: query,
            headers: [:],
            body: nil,
            statusErrors: [400: .badRequest, 404: .notFound, 204: .noContent]
        )
    }

    struct Result: Decodable { let payload: LBTopListeners }
}
