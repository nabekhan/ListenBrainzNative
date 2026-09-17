// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Access to ListenBrainz's follower relationships.
public struct LBSocialClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) { self.apiClient = client }

    /// All users following `username`. ListenBrainz does not paginate this endpoint.
    public func followers(username: String) async throws -> [String] {
        try await apiClient.execute(UserFollowersRequest(username: username)).followers ?? []
    }

    /// All users followed by `username`. ListenBrainz does not paginate this endpoint.
    public func following(username: String) async throws -> [String] {
        try await apiClient.execute(UserFollowingRequest(username: username)).following ?? []
    }

    /// Follows `username` as the authenticated user.
    @discardableResult
    public func follow(username: String) async throws -> LBSocialStatusResponse {
        try await apiClient.execute(FollowUserRequest(username: username))
    }

    /// Unfollows `username` as the authenticated user. The server treats an absent
    /// relationship as success, so this operation is safe to repeat.
    @discardableResult
    public func unfollow(username: String) async throws -> LBSocialStatusResponse {
        try await apiClient.execute(UnfollowUserRequest(username: username))
    }
}
