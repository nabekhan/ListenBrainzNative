import Foundation
import XCTest
@testable import Brainz

@MainActor
final class UserSocialModelTests: XCTestCase {
    func testPublicViewerLoadsOnlyPublicGraphInOrder() async {
        let provider = SocialFixtureProvider()
        let model = UserSocialModel(
            target: SearchUser(username: "target"),
            viewer: Account(username: "guest", token: ""),
            provider: provider,
            cache: UserSocialCache()
        )

        await model.load()

        XCTAssertEqual(model.followers.count, 2)
        XCTAssertEqual(model.following.count, 1)
        XCTAssertEqual(model.similarUsers.count, 1)
        XCTAssertNil(model.isFollowing)
        XCTAssertEqual(model.compatibilityPhase, .idle)
        let calls = await provider.calls
        XCTAssertEqual(calls, ["followers:target", "following:target", "similar:target"])
    }

    func testAuthenticatedViewerGetsRelationshipAndCompatibilityWithoutRowHydration() async {
        let names = (0 ..< 100).map { SearchUser(username: "listener-\($0)") }
            + [SearchUser(username: "Viewer")]
        let provider = SocialFixtureProvider(followers: names, compatibility: 0.73)
        let model = UserSocialModel(
            target: SearchUser(username: "target"),
            viewer: Account(username: "viewer", token: "token"),
            provider: provider,
            cache: UserSocialCache()
        )

        await model.load()
        _ = model.followers.map(\.username)

        XCTAssertEqual(model.isFollowing, true)
        XCTAssertEqual(model.compatibility, 0.73)
        let calls = await provider.calls
        XCTAssertEqual(
            calls,
            ["followers:target", "following:target", "similar:target", "compatibility:viewer:target"]
        )
    }

    func testFreshCacheIsNormalizedAndKeepsViewerSpecificStateIsolated() async {
        let cache = UserSocialCache()
        let firstProvider = SocialFixtureProvider(
            followers: [SearchUser(username: "FirstViewer")],
            compatibility: 0.8
        )
        let first = UserSocialModel(
            target: SearchUser(username: " Target "),
            viewer: Account(username: " FirstViewer ", token: "token"),
            provider: firstProvider,
            cache: cache
        )
        await first.load()

        let cachedProvider = SocialFixtureProvider()
        let cached = UserSocialModel(
            target: SearchUser(username: "target"),
            viewer: Account(username: "firstviewer", token: "token"),
            provider: cachedProvider,
            cache: cache
        )
        await cached.load()
        XCTAssertEqual(cached.isFollowing, true)
        XCTAssertEqual(cached.compatibility, 0.8)
        let cachedCalls = await cachedProvider.calls
        XCTAssertTrue(cachedCalls.isEmpty)

        let secondProvider = SocialFixtureProvider(compatibility: nil)
        let second = UserSocialModel(
            target: SearchUser(username: "TARGET"),
            viewer: Account(username: "secondviewer", token: "token"),
            provider: secondProvider,
            cache: cache
        )
        await second.load()
        XCTAssertEqual(second.isFollowing, false)
        XCTAssertNil(second.compatibility)
        let secondCalls = await secondProvider.calls
        XCTAssertEqual(secondCalls, ["compatibility:secondviewer:TARGET"])
    }

    func testFollowIsOptimisticSerializedAndRollsBackOnFailure() async throws {
        let provider = SocialFixtureProvider(
            mutationDelay: .milliseconds(80),
            failMutation: true
        )
        let model = UserSocialModel(
            target: SearchUser(username: "target"),
            viewer: Account(username: "viewer", token: "token"),
            provider: provider,
            cache: UserSocialCache()
        )
        await model.load()

        let mutation = Task { await model.toggleFollow() }
        try await ContinuousClock().sleep(for: .milliseconds(15))
        XCTAssertEqual(model.isFollowing, true)
        XCTAssertTrue(model.followers.contains { $0.username == "viewer" })
        await model.toggleFollow()
        await mutation.value

        XCTAssertEqual(model.isFollowing, false)
        XCTAssertFalse(model.followers.contains { $0.username == "viewer" })
        XCTAssertNotNil(model.actionError)
        let calls = await provider.calls
        XCTAssertEqual(calls.filter { $0 == "follow:target" }.count, 1)
    }

    func testSuccessfulFollowUpdatesCachedRelationshipAndFollowerList() async {
        let cache = UserSocialCache()
        let provider = SocialFixtureProvider()
        let model = UserSocialModel(
            target: SearchUser(username: "target"),
            viewer: Account(username: "viewer", token: "token"),
            provider: provider,
            cache: cache
        )
        await model.load()
        await model.toggleFollow()

        let cachedProvider = SocialFixtureProvider()
        let cached = UserSocialModel(
            target: SearchUser(username: "TARGET"),
            viewer: Account(username: "VIEWER", token: "token"),
            provider: cachedProvider,
            cache: cache
        )
        await cached.load()

        XCTAssertEqual(cached.isFollowing, true)
        XCTAssertTrue(cached.followers.contains { $0.username.caseInsensitiveCompare("viewer") == .orderedSame })
        let cachedCalls = await cachedProvider.calls
        XCTAssertTrue(cachedCalls.isEmpty)
    }

    func testSectionFailureDoesNotEraseOtherSocialResults() async {
        let provider = SocialFixtureProvider(failFollowing: true)
        let model = UserSocialModel(
            target: SearchUser(username: "target"),
            viewer: Account(username: "guest", token: ""),
            provider: provider,
            cache: UserSocialCache()
        )

        await model.load()

        XCTAssertEqual(model.followersPhase, .ready)
        if case .failed = model.followingPhase {} else {
            XCTFail("Following should report its independent failure")
        }
        XCTAssertEqual(model.similarUsersPhase, .ready)
        XCTAssertFalse(model.followers.isEmpty)
        XCTAssertFalse(model.similarUsers.isEmpty)
    }
}

private actor SocialFixtureProvider: SocialProviding {
    private(set) var calls: [String] = []
    private let followerValues: [SearchUser]
    private let followingValues: [SearchUser]
    private let similarValues: [SimilarListener]
    private let compatibilityValue: Double?
    private let mutationDelay: Duration?
    private let failMutation: Bool
    private let failFollowing: Bool

    init(
        followers: [SearchUser] = [SearchUser(username: "alice"), SearchUser(username: "bob")],
        following: [SearchUser] = [SearchUser(username: "carol")],
        similar: [SimilarListener] = [
            SimilarListener(user: SearchUser(username: "similar"), similarity: 0.85),
        ],
        compatibility: Double? = 0.64,
        mutationDelay: Duration? = nil,
        failMutation: Bool = false,
        failFollowing: Bool = false
    ) {
        followerValues = followers
        followingValues = following
        similarValues = similar
        compatibilityValue = compatibility
        self.mutationDelay = mutationDelay
        self.failMutation = failMutation
        self.failFollowing = failFollowing
    }

    func followers(of username: String) async throws -> [SearchUser] {
        calls.append("followers:\(username)")
        return followerValues
    }

    func following(of username: String) async throws -> [SearchUser] {
        calls.append("following:\(username)")
        if failFollowing { throw SocialFixtureError.failed }
        return followingValues
    }

    func similarUsers(to username: String) async throws -> [SimilarListener] {
        calls.append("similar:\(username)")
        return similarValues
    }

    func compatibility(between viewer: String, and username: String) async throws -> Double? {
        calls.append("compatibility:\(viewer):\(username)")
        return compatibilityValue
    }

    func follow(username: String) async throws {
        calls.append("follow:\(username)")
        try await finishMutation()
    }

    func unfollow(username: String) async throws {
        calls.append("unfollow:\(username)")
        try await finishMutation()
    }

    private func finishMutation() async throws {
        if let mutationDelay { try await ContinuousClock().sleep(for: mutationDelay) }
        if failMutation { throw SocialFixtureError.failed }
    }
}

private enum SocialFixtureError: Error { case failed }
