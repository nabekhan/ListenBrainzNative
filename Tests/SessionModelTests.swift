import Foundation
import XCTest
@testable import Brainz

@MainActor
final class SessionModelTests: XCTestCase {
    func testSameUsernameReplacementInvalidatesSnapshotBeforeCredentialSave() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore()
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in "listener" }
        )
        try await saveSnapshot(username: "listener", cache: environment.cache)

        await session.signIn(token: "replacement-token")

        XCTAssertEqual(session.state, .active(.init(username: "listener", token: "replacement-token")))
        let savedCredential = store.savedCredential
        let snapshotAbsent = await snapshotIsAbsent(username: "listener", cache: environment.cache)
        XCTAssertEqual(savedCredential, .init(username: "listener", token: "replacement-token"))
        XCTAssertTrue(snapshotAbsent)
        XCTAssertNil(environment.defaults.string(forKey: "listenbrainz.username"))
    }

    func testDifferentUsernameReplacementInvalidatesBothCandidatesBeforeCredentialSave() async throws {
        let environment = try makeEnvironment()
        environment.defaults.set("previous", forKey: "listenbrainz.username")
        let store = FixtureCredentialStore()
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
        let previousAbsent = await snapshotIsAbsent(username: "previous", cache: environment.cache)
        let canonicalAbsent = await snapshotIsAbsent(username: "canonical", cache: environment.cache)
        XCTAssertTrue(previousAbsent)
        XCTAssertTrue(canonicalAbsent)
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
        let store = FixtureCredentialStore(loaded: .legacyToken("legacy-token"))
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in " canonical " }
        )

        await session.restore()

        XCTAssertEqual(session.state, .active(.init(username: "canonical", token: "legacy-token")))
        let savedCredential = store.savedCredential
        let legacyAbsent = await snapshotIsAbsent(username: "legacy-default", cache: environment.cache)
        let canonicalAbsent = await snapshotIsAbsent(username: "canonical", cache: environment.cache)
        XCTAssertEqual(savedCredential, .init(username: "canonical", token: "legacy-token"))
        XCTAssertTrue(legacyAbsent)
        XCTAssertTrue(canonicalAbsent)
        XCTAssertNil(environment.defaults.string(forKey: "listenbrainz.username"))
    }

    func testBrowsePublicProfileInvalidatesPreviousAndRequestedSnapshotBeforePublication() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore(loaded: .account(.init(username: "listener", token: "stored-token")))
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
        let deleteCount = store.deleteCount
        XCTAssertTrue(listenerAbsent)
        XCTAssertTrue(targetAbsent)
        XCTAssertEqual(deleteCount, 1)
    }

    func testSignOutInvalidatesSnapshotBeforeCredentialDeletion() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore(loaded: .account(.init(username: "listener", token: "stored-token")))
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
        let snapshotAbsent = await snapshotIsAbsent(username: "listener", cache: environment.cache)
        XCTAssertTrue(snapshotAbsent)
    }

    func testCancelledSignInCannotPersistLateValidationResult() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore()
        let validator = DelayedValidation()
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in await validator.validate() }
        )

        let task = Task { await session.signIn(token: "replacement-token") }
        await validator.waitUntilStarted()
        session.cancelPendingSignIn()
        await validator.resume(username: "listener")
        await task.value

        XCTAssertEqual(session.state, .restoring)
        let savedCredential = store.savedCredential
        XCTAssertNil(savedCredential)
        XCTAssertFalse(session.isWorking)
    }

    func testCancelledReservedSignInDoesNotStartValidation() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore()
        let validator = ValidationCounter(username: "listener")
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { token in try await validator.validate(token) }
        )

        let attempt = session.beginSignInAttempt()
        session.cancelPendingSignIn()
        await session.signIn(token: "replacement-token", attempt: attempt)

        let validationCalls = await validator.calls
        let savedCredential = store.savedCredential
        XCTAssertEqual(validationCalls, 0)
        XCTAssertNil(savedCredential)
        XCTAssertEqual(session.state, .restoring)
    }

    func testCancellationDuringDelayedPreSaveCannotPersistCredential() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore()
        let gate = DelayedFirstCommit()
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { _ in "listener" },
            beforeCredentialSave: { await gate.waitForRelease() }
        )

        let task = Task { await session.signIn(token: "cancelled-token") }
        await gate.waitUntilStarted()
        session.cancelPendingSignIn()
        await gate.releaseFirst()
        await task.value

        XCTAssertNil(store.savedCredential)
        XCTAssertEqual(session.state, .restoring)
    }

    func testCancelledDelayedAttemptCannotOverwriteNewerCredential() async throws {
        let environment = try makeEnvironment()
        let store = FixtureCredentialStore()
        let gate = DelayedFirstCommit()
        let session = SessionModel(
            snapshotCache: environment.cache,
            credentialStore: store,
            defaults: environment.defaults,
            validateToken: { token in token == "first-token" ? "first" : "second" },
            beforeCredentialSave: { await gate.waitForRelease() }
        )

        let first = Task { await session.signIn(token: "first-token") }
        await gate.waitUntilStarted()
        session.cancelPendingSignIn()
        await session.signIn(token: "second-token")
        await gate.releaseFirst()
        await first.value

        XCTAssertEqual(store.savedCredential, .init(username: "second", token: "second-token"))
        XCTAssertEqual(session.state, SessionModel.State.active(.init(username: "second", token: "second-token")))
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

private final class FixtureCredentialStore: @unchecked Sendable, CredentialStoring {
    private var loaded: LoadedCredential?
    private var saved: StoredCredential?
    private var deletes = 0
    private let lock = NSLock()

    init(loaded: LoadedCredential? = nil) {
        self.loaded = loaded
    }

    func load() async throws -> LoadedCredential? { lock.withLock { loaded } }

    func save(_ credential: StoredCredential) throws {
        lock.withLock {
            saved = credential
            loaded = .account(credential)
        }
    }

    func delete() async throws {
        lock.withLock {
            deletes += 1
            loaded = nil
        }
    }

    var savedCredential: StoredCredential? { lock.withLock { saved } }
    var deleteCount: Int { lock.withLock { deletes } }
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

private actor DelayedValidation {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var resultWaiter: CheckedContinuation<String, Never>?

    func validate() async -> String {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { resultWaiter = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resume(username: String) {
        resultWaiter?.resume(returning: username)
        resultWaiter = nil
    }
}

private actor DelayedFirstCommit {
    private var calls = 0
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        calls += 1
        guard calls == 1 else { return }
        startedWaiter?.resume()
        startedWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilStarted() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func releaseFirst() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
