import Foundation
import ListenBrainzKit
import XCTest
@testable import Brainz

@MainActor
final class RecordingShareModelTests: XCTestCase {
    func testFreshFollowerCacheAvoidsAnotherRequest() async {
        let cache = UserSocialCache()
        await cache.saveFollowers(
            [SearchUser(username: "Zoe"), SearchUser(username: "maya")],
            for: "Listener"
        )
        let provider = RecordingShareFixtureProvider()
        let model = makeModel(provider: provider, socialCache: cache)

        await model.loadFollowers()

        XCTAssertEqual(model.followers.map(\.username), ["maya", "Zoe"])
        XCTAssertEqual(model.followersPhase, .ready)
        let calls = await provider.followerCalls
        XCTAssertEqual(calls, 0)
    }

    func testStaleFollowersRemainVisibleWhileTheyRefresh() async throws {
        let cache = UserSocialCache(timeToLive: -1)
        await cache.saveFollowers([SearchUser(username: "cached")], for: "listener")
        let provider = RecordingShareFixtureProvider(
            followers: [SearchUser(username: "fresh")],
            delay: .milliseconds(60)
        )
        let model = makeModel(provider: provider, socialCache: cache)

        let load = Task { await model.loadFollowers() }
        try await ContinuousClock().sleep(for: .milliseconds(10))
        XCTAssertEqual(model.followers.map(\.username), ["cached"])
        XCTAssertEqual(model.followersPhase, .ready)
        await load.value

        XCTAssertEqual(model.followers.map(\.username), ["fresh"])
    }

    func testPersonalRecommendationUsesSelectionTrimsNoteAndInvalidatesFeedCache() async {
        let provider = RecordingShareFixtureProvider(
            followers: [SearchUser(username: "Zoe"), SearchUser(username: "maya")]
        )
        let feedCache = EntityDetailCache<FeedPageKey, FeedPage>()
        let key = FeedPageKey(username: "listener", scope: .authenticated(token: "token"), mode: .activity, beforeTimestamp: nil, count: 25)
        await feedCache.save(FeedPage(username: "listener", serverCount: 0, events: []), for: key)
        let model = makeModel(provider: provider, feedCache: feedCache)
        await model.loadFollowers()
        model.toggle(SearchUser(username: "maya"))
        model.blurb = "  This belongs in your headphones.  "

        let succeeded = await model.recommendPersonally()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.notice?.kind, .confirmation)
        let cachedFeed = await feedCache.value(for: key)
        XCTAssertNil(cachedFeed)
        let operations = await provider.operations
        XCTAssertEqual(operations, [.personal(["maya"], "This belongs in your headphones.")])
    }

    func testPersonalFailureKeepsSelectionAndExposesInlineError() async {
        let provider = RecordingShareFixtureProvider(
            followers: [SearchUser(username: "maya")],
            mutationFailure: FixtureError.failed
        )
        let model = makeModel(provider: provider)
        await model.loadFollowers()
        model.toggle(SearchUser(username: "maya"))
        model.blurb = "Try this"

        let succeeded = await model.recommendPersonally()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.selectedFollowers.map(\.username), ["maya"])
        XCTAssertEqual(model.blurb, "Try this")
        XCTAssertEqual(model.notice?.kind, .error)
    }

    func testPersonalValidationRejectsEmptySelectionAndLongBlurbLocally() async {
        let provider = RecordingShareFixtureProvider(followers: [SearchUser(username: "maya")])
        let model = makeModel(provider: provider)
        await model.loadFollowers()

        let emptySelectionSucceeded = await model.recommendPersonally()
        XCTAssertFalse(emptySelectionSucceeded)
        XCTAssertEqual(model.notice?.message, "Choose at least one follower.")

        model.toggle(SearchUser(username: "maya"))
        model.blurb = String(repeating: "x", count: 281)
        let longBlurbSucceeded = await model.recommendPersonally()
        XCTAssertFalse(longBlurbSucceeded)
        XCTAssertEqual(model.notice?.message, "A personal recommendation note can be up to 280 characters.")
        let operations = await provider.operations
        XCTAssertTrue(operations.isEmpty)
    }

    func testPublicRecommendationSerializesDuplicateTaps() async {
        let provider = RecordingShareFixtureProvider(delay: .milliseconds(60))
        let model = makeModel(provider: provider)

        async let first: Bool = model.recommendToFollowers()
        async let second: Bool = model.recommendToFollowers()
        let results = await (first, second)

        XCTAssertEqual([results.0, results.1].filter { $0 }.count, 1)
        let operations = await provider.operations
        XCTAssertEqual(operations, [.publicRecommendation])
    }

    func testProviderNormalizesRecipientsAndUsesStableIdentifiers() async throws {
        let transport = RecordingShareTransportSpy()
        let provider = ListenBrainzRecordingShareProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let recording = fixtureRecording()

        try await provider.recommendPersonally(
            username: "listener",
            recording: recording,
            recipients: [" Alice ", "alice", "BOB"],
            blurb: "  Excellent pick.  "
        )

        let call = await transport.personalCall
        XCTAssertEqual(call?.username, "listener")
        XCTAssertEqual(call?.recordingMBID, recording.identity.mbid)
        XCTAssertEqual(call?.recordingMSID, recording.identity.msid)
        XCTAssertEqual(call?.recipients, ["Alice", "BOB"])
        XCTAssertEqual(call?.blurb, "Excellent pick.")
    }

    func testProviderRejectsUnmappedRecordingBeforeTransport() async {
        let transport = RecordingShareTransportSpy()
        let provider = ListenBrainzRecordingShareProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let recording = Recording(
            identity: .init(mbid: nil, msid: nil),
            title: "Unmapped",
            artistName: "Unknown",
            artistMBIDs: [],
            releaseTitle: nil,
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: nil,
            source: nil
        )

        do {
            try await provider.recommendToFollowers(username: "listener", recording: recording)
            XCTFail("An unmapped recording should not reach the transport")
        } catch RecordingShareProviderError.missingRecordingIdentifier {}
        catch { XCTFail("Unexpected error: \(error)") }

        let publicCalls = await transport.publicCalls
        XCTAssertEqual(publicCalls, 0)
    }

    private func makeModel(
        provider: RecordingShareFixtureProvider,
        socialCache: UserSocialCache = UserSocialCache(),
        feedCache: EntityDetailCache<FeedPageKey, FeedPage> = EntityDetailCache()
    ) -> RecordingShareModel {
        RecordingShareModel(
            account: Account(username: "listener", token: "token"),
            recording: fixtureRecording(),
            provider: provider,
            socialCache: socialCache,
            feedCache: feedCache
        )
    }

    private func fixtureRecording() -> Recording {
        Recording(
            identity: .init(
                mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab"),
                msid: UUID(uuidString: "a6081bc1-2a76-4984-b21f-38bc3dcca3a5")
            ),
            title: "Dreams Tonite",
            artistName: "Alvvays",
            artistMBIDs: [],
            releaseTitle: "Antisocialites",
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: 196_000,
            source: "Fixture"
        )
    }
}

private actor RecordingShareFixtureProvider: RecordingShareProviding {
    enum Operation: Equatable, Sendable {
        case publicRecommendation
        case personal([String], String?)
    }

    let followersValue: [SearchUser]
    let mutationFailure: Error?
    let delay: Duration
    private(set) var followerCalls = 0
    private(set) var operations: [Operation] = []

    init(
        followers: [SearchUser] = [],
        mutationFailure: Error? = nil,
        delay: Duration = .zero
    ) {
        followersValue = followers
        self.mutationFailure = mutationFailure
        self.delay = delay
    }

    func followers(of username: String) async throws -> [SearchUser] {
        followerCalls += 1
        if delay > .zero { try await ContinuousClock().sleep(for: delay) }
        return followersValue
    }

    func recommendToFollowers(username: String, recording: Recording) async throws {
        operations.append(.publicRecommendation)
        if delay > .zero { try await ContinuousClock().sleep(for: delay) }
        if let mutationFailure { throw mutationFailure }
    }

    func recommendPersonally(
        username: String,
        recording: Recording,
        recipients: [String],
        blurb: String?
    ) async throws {
        operations.append(.personal(recipients, blurb))
        if delay > .zero { try await ContinuousClock().sleep(for: delay) }
        if let mutationFailure { throw mutationFailure }
    }
}

private actor RecordingShareTransportSpy: RecordingShareTransport {
    struct PersonalCall: Sendable {
        let username: String
        let recordingMBID: UUID?
        let recordingMSID: UUID?
        let recipients: [String]
        let blurb: String?
    }

    private(set) var publicCalls = 0
    private(set) var personalCall: PersonalCall?

    func followers(username: String) async throws -> [String] { [] }

    func recommendToFollowers(
        username: String,
        recordingMBID: UUID?,
        recordingMSID: UUID?
    ) async throws {
        publicCalls += 1
    }

    func recommendPersonally(
        username: String,
        recordingMBID: UUID?,
        recordingMSID: UUID?,
        recipients: [String],
        blurb: String?
    ) async throws {
        personalCall = PersonalCall(
            username: username,
            recordingMBID: recordingMBID,
            recordingMSID: recordingMSID,
            recipients: recipients,
            blurb: blurb
        )
    }
}

private enum FixtureError: LocalizedError {
    case failed
    var errorDescription: String? { "Fixture failure" }
}
