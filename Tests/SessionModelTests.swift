import Foundation
import XCTest
@testable import Brainz

@MainActor
final class SessionModelTests: XCTestCase {
    func testSameUsernameReplacementInvalidatesSnapshotBeforeCredentialSave() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore(snapshotCache: environment.cache, snapshotsExpectedAbsentAtSave: ["listener"])
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in "listener" }
        )
        try await saveSnapshot(username: "listener", cache: environment.cache)

        await session.signIn(token: "replacement-token")

        XCTAssertEqual(session.state, .active(.init(username: "listener", token: "replacement-token")))
        let savedCredential = await store.savedCredential
        let snapshotsWereAbsent = await store.expectedSnapshotsWereAbsentAtSave
        XCTAssertEqual(savedCredential, .init(username: "listener", token: "replacement-token"))
        XCTAssertTrue(snapshotsWereAbsent)
        XCTAssertNil(environment.defaults.string(forKey: "listenbrainz.username"))
    }

    func testDifferentUsernameReplacementInvalidatesBothCandidatesBeforeCredentialSave() async throws {
        let environment = try makeEnvironment()
        environment.defaults.set("previous", forKey: "listenbrainz.username")
        let store = FixtureCredentialStore(snapshotCache: environment.cache, snapshotsExpectedAbsentAtSave: ["previous", "canonical"])
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in "canonical" }
        )
        await session.restore()
        try await saveSnapshot(username: "previous", cache: environment.cache)
        try await saveSnapshot(username: "canonical", cache: environment.cache)

        await session.signIn(token: "new-token")

        XCTAssertEqual(session.state, .active(.init(username: "canonical", token: "new-token")))
        let snapshotsWereAbsent = await store.expectedSnapshotsWereAbsentAtSave
        XCTAssertTrue(snapshotsWereAbsent)
    }

    func testAtomicRestoreIgnoresStalePublicUsernameWithoutValidation() async throws {
        let environment = try makeEnvironment()
        environment.defaults.set("stale-public", forKey: "listenbrainz.username")
        let store = FixtureCredentialStore(loaded: .account(.init(username: "canonical", token: "stored-token")))
        let validator = ValidationCounter(username: "unused")
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { token in try await validator.validate(token) }
        )

        await session.restore()

        XCTAssertEqual(session.state, .active(.init(username: "canonical", token: "stored-token")))
        XCTAssertNil(environment.defaults.string(forKey: "listenbrainz.username"))
        let validationCalls = await validator.calls
        XCTAssertEqual(validationCalls, 0)
    }

    func testLegacyTokenMigratesThroughValidationBeforeActivation() async throws {
        let environment = try makeEnvironment()
        environment.defaults.set("legacy-default", forKey: "listenbrainz.username")
        try await saveSnapshot(username: "legacy-default", cache: environment.cache)
        try await saveSnapshot(username: "canonical", cache: environment.cache)
        let store = FixtureCredentialStore(
            loaded: .legacyToken("legacy-token"),
            snapshotCache: environment.cache,
            snapshotsExpectedAbsentAtSave: ["legacy-default", "canonical"]
        )
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in " canonical " }
        )

        await session.restore()

        XCTAssertEqual(session.state, .active(.init(username: "canonical", token: "legacy-token")))
        let savedCredential = await store.savedCredential
        let snapshotsWereAbsent = await store.expectedSnapshotsWereAbsentAtSave
        XCTAssertEqual(savedCredential, .init(username: "canonical", token: "legacy-token"))
        XCTAssertTrue(snapshotsWereAbsent)
        XCTAssertNil(environment.defaults.string(forKey: "listenbrainz.username"))
    }

    func testBrowsePublicProfileInvalidatesPreviousAndRequestedSnapshotBeforePublication() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore(
            loaded: .account(.init(username: "listener", token: "stored-token")),
            snapshotCache: environment.cache
        )
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in "unused" }
        )
        await session.restore()
        try await saveSnapshot(username: "listener", cache: environment.cache)
        try await saveSnapshot(username: "public-target", cache: environment.cache)

        await session.browsePublicProfile(username: "public-target")

        XCTAssertEqual(session.state, .active(.init(username: "public-target", token: "")))
        XCTAssertEqual(environment.defaults.string(forKey: "listenbrainz.username"), "public-target")
        let listenerAbsent = await snapshotIsAbsent(username: "listener", cache: environment.cache)
        let targetAbsent = await snapshotIsAbsent(username: "public-target", cache: environment.cache)
        let deleteCount = await store.deleteCount
        XCTAssertTrue(listenerAbsent)
        XCTAssertTrue(targetAbsent)
        XCTAssertEqual(deleteCount, 1)
    }

    func testSignOutInvalidatesSnapshotBeforeCredentialDeletion() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore(
            loaded: .account(.init(username: "listener", token: "stored-token")),
            snapshotCache: environment.cache,
            snapshotsExpectedAbsentAtDelete: ["listener"]
        )
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in "unused" }
        )
        await session.restore()
        try await saveSnapshot(username: "listener", cache: environment.cache)

        await session.signOut()

        XCTAssertEqual(session.state, .signedOut)
        let snapshotsWereAbsent = await store.expectedSnapshotsWereAbsentAtDelete
        let snapshotAbsent = await snapshotIsAbsent(username: "listener", cache: environment.cache)
        XCTAssertTrue(snapshotsWereAbsent)
        XCTAssertTrue(snapshotAbsent)
    }

    private func makeEnvironment() throws -> (cache: SnapshotCache, defaults: UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suiteName = "SessionModelTests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw FixtureError.unavailableDefaults
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try FileManager.default.removeItem(at: root)
        }
        return (SnapshotCache(rootDirectory: root), defaults)
    }

    private func saveSnapshot(username: String, cache: SnapshotCache) async throws {
        let lease = await cache.beginSession(username: username)
        await cache.save(.empty, username: username, lease: lease)
    }

    private func snapshotIsAbsent(username: String, cache: SnapshotCache) async -> Bool {
        let lease = await cache.beginSession(username: username)
        return await cache.load(username: username, lease: lease) == nil
    }
}

private enum FixtureError: Error {
    case unavailableDefaults
}

private actor FixtureCredentialStore: CredentialStoring {
    private var loaded: LoadedCredential?
    private var saved: StoredCredential?
    private var deletes = 0
    private let snapshotCache: SnapshotCache?
    private let snapshotsExpectedAbsentAtSave: [String]
    private let snapshotsExpectedAbsentAtDelete: [String]
    private var snapshotsWereAbsentAtSave: Bool?
    private var snapshotsWereAbsentAtDelete: Bool?

    init(
        loaded: LoadedCredential? = nil,
        snapshotCache: SnapshotCache? = nil,
        snapshotsExpectedAbsentAtSave: [String] = [],
        snapshotsExpectedAbsentAtDelete: [String] = []
    ) {
        self.loaded = loaded
        self.snapshotCache = snapshotCache
        self.snapshotsExpectedAbsentAtSave = snapshotsExpectedAbsentAtSave
        self.snapshotsExpectedAbsentAtDelete = snapshotsExpectedAbsentAtDelete
    }

    func load() async throws -> LoadedCredential? { loaded }

    func save(_ credential: StoredCredential) async throws {
        if let snapshotCache {
            var absent = true
            for username in snapshotsExpectedAbsentAtSave {
                let lease = await snapshotCache.beginSession(username: username)
                let snapshot = await snapshotCache.load(username: username, lease: lease)
                absent = absent && snapshot == nil
            }
            snapshotsWereAbsentAtSave = absent
        }
        saved = credential
        loaded = .account(credential)
    }

    func delete() async throws {
        if let snapshotCache {
            var absent = true
            for username in snapshotsExpectedAbsentAtDelete {
                let lease = await snapshotCache.beginSession(username: username)
                let snapshot = await snapshotCache.load(username: username, lease: lease)
                absent = absent && snapshot == nil
            }
            snapshotsWereAbsentAtDelete = absent
        }
        deletes += 1
        loaded = nil
    }

    var savedCredential: StoredCredential? { saved }
    var expectedSnapshotsWereAbsentAtSave: Bool { snapshotsWereAbsentAtSave ?? false }
    var expectedSnapshotsWereAbsentAtDelete: Bool { snapshotsWereAbsentAtDelete ?? false }
    var deleteCount: Int { deletes }
}

private actor ValidationCounter {
    private(set) var calls = 0
    private let username: String

    init(username: String) {
        self.username = username
    }

    func validate(_: String) throws -> String {
        calls += 1
        return username
    }
}
