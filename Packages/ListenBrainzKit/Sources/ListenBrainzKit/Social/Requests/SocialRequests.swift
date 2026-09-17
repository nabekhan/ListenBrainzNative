// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct UserFollowersRequest: APIRequest {
    typealias Result = LBUserRelationships
    let data: APIRequestData<NoBody>

    init(username: String) {
        data = .init(
            path: "/1/user/\(username)/followers",
            method: .get,
            statusErrors: [404: .notFound]
        )
    }
}

struct UserFollowingRequest: APIRequest {
    typealias Result = LBUserRelationships
    let data: APIRequestData<NoBody>

    init(username: String) {
        data = .init(
            path: "/1/user/\(username)/following",
            method: .get,
            statusErrors: [404: .notFound]
        )
    }
}

struct FollowUserRequest: APIRequest {
    typealias Result = LBSocialStatusResponse
    let data: APIRequestData<NoBody>

    init(username: String) {
        data = .init(
            path: "/1/user/\(username)/follow",
            method: .post,
            headers: ["Content-Type": "application/json"],
            statusErrors: [400: .badRequest, 401: .invalidAuth, 404: .notFound]
        )
    }
}

struct UnfollowUserRequest: APIRequest {
    typealias Result = LBSocialStatusResponse
    let data: APIRequestData<NoBody>

    init(username: String) {
        data = .init(
            path: "/1/user/\(username)/unfollow",
            method: .post,
            headers: ["Content-Type": "application/json"],
            statusErrors: [401: .invalidAuth, 404: .notFound]
        )
    }
}
