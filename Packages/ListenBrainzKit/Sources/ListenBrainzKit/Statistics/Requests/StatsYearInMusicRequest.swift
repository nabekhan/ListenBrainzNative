// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct StatsYearInMusicRequest: APIRequest {
    let data: APIRequestData<NoBody>

    init(user: String, year: Int?) {
        let yearPath = year.map { "/\($0)" } ?? ""
        self.data = .init(
            path: "/1/stats/user/\(user)/year-in-music\(yearPath)",
            method: .get,
            queryItems: [:],
            headers: [:],
            body: nil,
            statusErrors: [
                400: .badRequest,
                404: .notFound,
                204: .noContent,
            ]
        )
    }

    struct Result: Decodable {
        let payload: LBYearInMusic
    }
}
