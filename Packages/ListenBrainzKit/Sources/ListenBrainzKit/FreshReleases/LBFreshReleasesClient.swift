// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Fresh releases selected by ListenBrainz, either for a user or sitewide.
public struct LBFreshReleasesClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) {
        self.apiClient = client
    }

    /// Releases tailored to a user's listening history. `nil` means the server
    /// has no releases to return (HTTP 204), not that sitewide releases were fetched.
    public func personalized(
        user: String,
        days: Int = 14,
        includePast: Bool = true,
        includeFuture: Bool = true,
        sort: LBFreshReleaseSort = .releaseDate
    ) async throws -> LBFreshReleases? {
        try await execute(PersonalFreshReleasesRequest(
            user: user,
            days: days,
            includePast: includePast,
            includeFuture: includeFuture,
            sort: sort
        ))
    }

    /// Releases currently being explored across ListenBrainz. This is deliberately
    /// separate from personalized releases so callers can choose when to request it.
    public func sitewide(
        days: Int = 14,
        includePast: Bool = true,
        includeFuture: Bool = true,
        sort: LBSitewideFreshReleaseSort = .releaseDate
    ) async throws -> LBFreshReleases? {
        try await execute(SitewideFreshReleasesRequest(
            days: days,
            includePast: includePast,
            includeFuture: includeFuture,
            sort: sort
        ))
    }

    private func execute<Request: APIRequest>(_ request: Request) async throws -> LBFreshReleases? where Request.Result == FreshReleasesResponse {
        do {
            return try await apiClient.execute(request).payload
        } catch LBError.noContent {
            return nil
        }
    }
}
