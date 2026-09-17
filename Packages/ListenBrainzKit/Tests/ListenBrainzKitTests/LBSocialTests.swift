// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ListenBrainzKit

@Suite struct LBSocialTests {
    @Test("Follower collections decode and use the documented paths")
    func followerCollections() async throws {
        let followers = try JSONDecoder.ListenBrainz.decode(
            LBUserRelationships.self,
            from: Data(#"{"followers":["alice","bob"],"user":"target"}"#.utf8)
        )
        let followersMock = MockAPIClient(result: .success(followers))
        let followerNames = try await LBSocialClient(followersMock).followers(username: "target")
        #expect(followerNames == ["alice", "bob"])
        let followersRequest = try #require(followersMock.request as? UserFollowersRequest)
        #expect(followersRequest.data.path == "/1/user/target/followers")
        #expect(followersRequest.data.method == .get)
        #expect(followersRequest.data.statusErrors[404] == .notFound)

        let following = try JSONDecoder.ListenBrainz.decode(
            LBUserRelationships.self,
            from: Data(#"{"following":["carol"],"user":"target"}"#.utf8)
        )
        let followingMock = MockAPIClient(result: .success(following))
        let followingNames = try await LBSocialClient(followingMock).following(username: "target")
        #expect(followingNames == ["carol"])
        let followingRequest = try #require(followingMock.request as? UserFollowingRequest)
        #expect(followingRequest.data.path == "/1/user/target/following")
        #expect(followingRequest.data.method == .get)
        #expect(followingRequest.data.statusErrors[404] == .notFound)
    }

    @Test("Follow and unfollow decode status and preserve endpoint-specific errors")
    func mutations() async throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            LBSocialStatusResponse.self,
            from: Data(#"{"status":"ok"}"#.utf8)
        )

        let followMock = MockAPIClient(result: .success(response))
        #expect(try await LBSocialClient(followMock).follow(username: "target") == response)
        let followRequest = try #require(followMock.request as? FollowUserRequest)
        #expect(followRequest.data.path == "/1/user/target/follow")
        #expect(followRequest.data.method == .post)
        #expect(followRequest.data.headers["Content-Type"] == "application/json")
        #expect(followRequest.data.statusErrors[400] == .badRequest)
        #expect(followRequest.data.statusErrors[401] == .invalidAuth)
        #expect(followRequest.data.statusErrors[404] == .notFound)

        let unfollowMock = MockAPIClient(result: .success(response))
        #expect(try await LBSocialClient(unfollowMock).unfollow(username: "target") == response)
        let unfollowRequest = try #require(unfollowMock.request as? UnfollowUserRequest)
        #expect(unfollowRequest.data.path == "/1/user/target/unfollow")
        #expect(unfollowRequest.data.method == .post)
        #expect(unfollowRequest.data.headers["Content-Type"] == "application/json")
        #expect(unfollowRequest.data.statusErrors[400] == nil)
        #expect(unfollowRequest.data.statusErrors[401] == .invalidAuth)
        #expect(unfollowRequest.data.statusErrors[404] == .notFound)
    }

    @Test("Similar-user values are public app-facing data")
    func similarUserDecode() throws {
        let user = try JSONDecoder.ListenBrainz.decode(
            LBSimilarUser.self,
            from: Data(#"{"user_name":"alice","similarity":0.82}"#.utf8)
        )
        #expect(user.userName == "alice")
        #expect(user.similarity == 0.82)
    }
}
