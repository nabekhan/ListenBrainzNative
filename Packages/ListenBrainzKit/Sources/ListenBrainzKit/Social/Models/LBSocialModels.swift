// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// The complete follower or following collection returned for a user.
public struct LBUserRelationships: Decodable, Equatable, Sendable {
    public let user: String
    public let followers: [String]?
    public let following: [String]?
}

/// The status object returned by follow and unfollow mutations.
public struct LBSocialStatusResponse: Decodable, Equatable, Sendable {
    public let status: String
}
