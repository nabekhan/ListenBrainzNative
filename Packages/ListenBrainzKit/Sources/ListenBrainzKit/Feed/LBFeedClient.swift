// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Read-only access to an authenticated user's ListenBrainz social feed.
public struct LBFeedClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) { self.apiClient = client }

    /// Activity from the authenticated user's network, including recommendations,
    /// pins, follows, reviews, thanks, and notifications where available.
    public func events(
        username: String,
        count: Int = 25,
        maxTimestamp: Date? = nil,
        minTimestamp: Date? = nil
    ) async throws -> LBFeedPage {
        try await apiClient.execute(FeedEventsRequest(
            username: username,
            kind: .events,
            count: count,
            maxTimestamp: maxTimestamp,
            minTimestamp: minTimestamp
        )).payload
    }

    /// Recent listens from users followed by the authenticated user.
    public func followingListens(
        username: String,
        count: Int = 25,
        maxTimestamp: Date? = nil,
        minTimestamp: Date? = nil
    ) async throws -> LBFeedPage {
        try await page(
            username: username,
            kind: .following,
            count: count,
            maxTimestamp: maxTimestamp,
            minTimestamp: minTimestamp
        )
    }

    /// Recent listens from users ListenBrainz considers similar to the authenticated user.
    public func similarListens(
        username: String,
        count: Int = 25,
        maxTimestamp: Date? = nil,
        minTimestamp: Date? = nil
    ) async throws -> LBFeedPage {
        try await page(
            username: username,
            kind: .similar,
            count: count,
            maxTimestamp: maxTimestamp,
            minTimestamp: minTimestamp
        )
    }

    private func page(
        username: String,
        kind: FeedEventsRequest.Kind,
        count: Int,
        maxTimestamp: Date?,
        minTimestamp: Date?
    ) async throws -> LBFeedPage {
        try await apiClient.execute(FeedEventsRequest(
            username: username,
            kind: kind,
            count: count,
            maxTimestamp: maxTimestamp,
            minTimestamp: minTimestamp
        )).payload
    }
}
