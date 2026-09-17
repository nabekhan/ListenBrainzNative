// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

struct SearchPlaylistsRequest: APIRequest {
    typealias Result = RawPlaylistResponse

    let data: APIRequestData<NoBody>

    init(query: String, count: Int, offset: Int) {
        self.data = .init(
            path: "/1/playlist/search",
            method: .get,
            queryItems: [
                "query": [query],
                "count": [String(count)],
                "offset": [String(offset)],
            ]
        )
    }
}
