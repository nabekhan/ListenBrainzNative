// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct PlaylistRequest: APIRequest {
    typealias Result = RawSinglePlaylistResponse

    let data: APIRequestData<NoBody>

    init(mbid: UUID, fetchMetadata: Bool) {
        self.data = .init(
            path: "/1/playlist/\(mbid.uuidString)",
            method: .get,
            queryItems: ["fetch_metadata": [fetchMetadata ? "true" : "false"]],
            statusErrors: [
                401: .invalidAuth,
                404: .notFound,
            ]
        )
    }
}
