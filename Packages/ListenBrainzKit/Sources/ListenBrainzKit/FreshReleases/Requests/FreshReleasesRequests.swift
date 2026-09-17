// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

private func freshReleaseQuery(
    days: Int,
    includePast: Bool,
    includeFuture: Bool,
    sort: String
) -> [String: [String]] {
    [
        "days": [String(min(max(days, 1), 90))],
        "past": [String(includePast)],
        "future": [String(includeFuture)],
        "sort": [sort]
    ]
}

struct PersonalFreshReleasesRequest: APIRequest {
    let data: APIRequestData<NoBody>

    init(user: String, days: Int, includePast: Bool, includeFuture: Bool, sort: LBFreshReleaseSort) {
        data = .init(
            path: "/1/user/\(user)/fresh_releases",
            method: .get,
            queryItems: freshReleaseQuery(
                days: days,
                includePast: includePast,
                includeFuture: includeFuture,
                sort: sort.rawValue
            ),
            statusErrors: [400: .badRequest, 404: .notFound, 204: .noContent]
        )
    }

    typealias Result = FreshReleasesResponse
}

struct SitewideFreshReleasesRequest: APIRequest {
    let data: APIRequestData<NoBody>

    init(days: Int, includePast: Bool, includeFuture: Bool, sort: LBSitewideFreshReleaseSort) {
        // The production endpoint redirects when this terminal slash is absent.
        // Preserve it to avoid a needless hop (and an authenticated redirect).
        data = .init(
            path: "/1/explore/fresh-releases/",
            method: .get,
            queryItems: freshReleaseQuery(
                days: days,
                includePast: includePast,
                includeFuture: includeFuture,
                sort: sort.rawValue
            ),
            statusErrors: [400: .badRequest, 204: .noContent],
            preservesTrailingSlash: true
        )
    }

    typealias Result = FreshReleasesResponse
}
