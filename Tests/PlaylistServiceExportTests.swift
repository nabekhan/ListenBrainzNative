import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class PlaylistServiceExportModelTests: XCTestCase {
    private let playlistMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    func testConnectedServicesMapOnlySupportedPlaylistDestinations() {
        let services = ConnectedServices(identifiers: [
            "spotify", "apple", "soundcloud", "lastfm", "critiquebrainz",
        ])

        XCTAssertEqual(
            services.playlistExportDestinations,
            [.spotify, .appleMusic, .soundCloud]
        )
        XCTAssertEqual(
            ConnectedServices(identifiers: ["apple_music"]).playlistExportDestinations,
            [.appleMusic]
        )
        XCTAssertEqual(
            PlaylistExternalService.appleMusic.serviceHomeURL.absoluteString,
            "https://music.apple.com/"
        )
    }

    func testConfirmedExportKeepsBarrierUntilUserAcknowledgesResult() async throws {
        let provider = PlaylistServiceExportFixtureProvider(mode: .success)
        let journal = PlaylistServiceExportJournal()
        let model = PlaylistServiceExportModel(
            account: .init(username: " Listener ", token: "secret-token"),
            playlistMBID: playlistMBID,
            provider: provider,
            journal: journal,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        await model.export(to: .spotify, isPublic: false)

        XCTAssertTrue(model.requiresReview(for: .spotify))
        guard case let .confirmed(service, url) = model.notice else {
            return XCTFail("Expected a confirmed export")
        }
        XCTAssertEqual(service, .spotify)
        XCTAssertEqual(url.absoluteString, "https://open.spotify.com/playlist/fixture")
        let calls = await provider.calls()
        XCTAssertEqual(calls, [
            .init(playlistMBID: playlistMBID, service: .spotify, isPublic: false),
        ])

        model.acknowledgeConfirmedExport()
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.requiresReview(for: .spotify))
    }

    func testStorageFailurePreventsDispatch() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileInsteadOfDirectory = root.appending(path: "not-a-directory")
        try Data("occupied".utf8).write(to: fileInsteadOfDirectory)
        let provider = PlaylistServiceExportFixtureProvider(mode: .success)
        let journal = PlaylistServiceExportJournal(directoryURL: fileInsteadOfDirectory)
        let model = PlaylistServiceExportModel(
            account: .init(username: "listener", token: "token"),
            playlistMBID: playlistMBID,
            provider: provider,
            journal: journal
        )

        await model.export(to: .appleMusic, isPublic: true)

        XCTAssertTrue(model.requiresReview(for: .appleMusic))
        guard case let .failed(_, message) = model.notice else {
            return XCTFail("Expected a storage failure")
        }
        XCTAssertTrue(message.contains("no playlist was sent"))
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testIndeterminateExportPersistsBarrierAndBlocksReplay() async {
        let provider = PlaylistServiceExportFixtureProvider(mode: .indeterminate)
        let journal = PlaylistServiceExportJournal()
        let model = PlaylistServiceExportModel(
            account: .init(username: "listener", token: "token"),
            playlistMBID: playlistMBID,
            provider: provider,
            journal: journal
        )

        await model.export(to: .soundCloud, isPublic: true)
        await model.export(to: .soundCloud, isPublic: true)

        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(model.requiresReview(for: .soundCloud))
        guard case let .verificationNeeded(_, service, message) = model.notice else {
            return XCTFail("Expected verification guidance")
        }
        XCTAssertEqual(service, .soundCloud)
        XCTAssertTrue(message.contains("SoundCloud"))

        model.acknowledgeVerificationNotice()
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.requiresReview(for: .soundCloud))
        model.clearAfterUserReview(.soundCloud)
        XCTAssertFalse(model.requiresReview(for: .soundCloud))
    }

    func testPreTransportCancellationClearsBarrier() async {
        let provider = PlaylistServiceExportFixtureProvider(mode: .cancelledBeforeTransport)
        let model = PlaylistServiceExportModel(
            account: .init(username: "listener", token: "token"),
            playlistMBID: playlistMBID,
            provider: provider,
            journal: PlaylistServiceExportJournal()
        )

        await model.export(to: .spotify, isPublic: true)

        XCTAssertFalse(model.requiresReview(for: .spotify))
        XCTAssertNil(model.notice)
    }

    func testGenericCancellationAfterProviderAdmissionRemainsBlocked() async {
        let model = PlaylistServiceExportModel(
            account: .init(username: "listener", token: "token"),
            playlistMBID: playlistMBID,
            provider: PlaylistServiceExportFixtureProvider(mode: .genericCancellation),
            journal: PlaylistServiceExportJournal()
        )

        await model.export(to: .spotify, isPublic: true)

        XCTAssertTrue(model.requiresReview(for: .spotify))
        guard case .verificationNeeded = model.notice else {
            return XCTFail("Expected generic cancellation to remain ambiguous")
        }
    }

    func testSecondModelCannotClearOrQueueWhileFirstExportIsActive() async {
        let journal = PlaylistServiceExportJournal()
        let firstProvider = SuspendingPlaylistServiceExportProvider()
        let secondProvider = PlaylistServiceExportFixtureProvider(mode: .success)
        let account = Account(username: "listener", token: "token")
        let first = PlaylistServiceExportModel(
            account: account,
            playlistMBID: playlistMBID,
            provider: firstProvider,
            journal: journal
        )
        let second = PlaylistServiceExportModel(
            account: account,
            playlistMBID: playlistMBID,
            provider: secondProvider,
            journal: journal
        )
        let task = Task { await first.export(to: .spotify, isPublic: true) }
        while !(await firstProvider.started()) { await Task.yield() }

        XCTAssertTrue(second.requiresReview(for: .spotify))
        second.clearAfterUserReview(.spotify)
        XCTAssertTrue(second.requiresReview(for: .spotify))
        await second.export(to: .spotify, isPublic: true)
        let secondCallCount = await secondProvider.callCount()
        XCTAssertEqual(secondCallCount, 0)

        await firstProvider.finish()
        await task.value
        XCTAssertTrue(first.requiresReview(for: .spotify))
    }

    func testJournalPersistsOnlyOpaqueTokenFreeBarrier() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = PlaylistServiceExportJournal(directoryURL: directory)

        XCTAssertTrue(journal.beginAttempt(
            username: " Listener ",
            playlistMBID: playlistMBID,
            service: .spotify,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let reopened = PlaylistServiceExportJournal(directoryURL: directory)
        let record = try XCTUnwrap(reopened.record(
            username: "listener",
            playlistMBID: playlistMBID,
            service: .spotify
        ))
        XCTAssertEqual(record.attemptedAt, Date(timeIntervalSince1970: 1_700_000_000))
        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        let persisted = try Data(contentsOf: file)
        let text = String(decoding: persisted, as: UTF8.self)
        XCTAssertFalse(text.contains("secret-token"))
        XCTAssertFalse(text.contains("listener"))
        XCTAssertFalse(text.contains(playlistMBID.uuidString.lowercased()))
        XCTAssertFalse(text.contains("spotify"))
    }

    func testCorruptJournalFailsClosedUntilExplicitReview() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = PlaylistServiceExportJournal(directoryURL: directory)
        XCTAssertTrue(original.beginAttempt(
            username: "listener",
            playlistMBID: playlistMBID,
            service: .soundCloud,
            at: .now
        ))
        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        try Data("not-json".utf8).write(to: file)

        let reopened = PlaylistServiceExportJournal(directoryURL: directory)
        XCTAssertTrue(reopened.requiresRecovery(
            username: "listener",
            playlistMBID: playlistMBID,
            service: .soundCloud
        ))
        XCTAssertFalse(reopened.beginAttempt(
            username: "listener",
            playlistMBID: playlistMBID,
            service: .soundCloud,
            at: .now
        ))
        XCTAssertTrue(reopened.resolveAfterReview(
            username: "listener",
            playlistMBID: playlistMBID,
            service: .soundCloud
        ))
        XCTAssertFalse(reopened.requiresReview(
            username: "listener",
            playlistMBID: playlistMBID,
            service: .soundCloud
        ))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PlaylistServiceExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class PlaylistServiceExportProviderTests: XCTestCase {
    private let playlistMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    func testProviderSerializesOneSuccessfulExport() async throws {
        let transport = PlaylistServiceExportTransportFixture(mode: .success)
        let provider = ListenBrainzPlaylistServiceExportProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let url = try await provider.export(
            playlistMBID: playlistMBID,
            to: .spotify,
            isPublic: false
        )

        XCTAssertEqual(url.absoluteString, "https://open.spotify.com/playlist/fixture")
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testEveryPostDispatchServerErrorIsIndeterminate() async {
        for mode in PlaylistServiceExportTransportFixture.Mode.failureCases {
            await assertProviderError(mode: mode, equals: .indeterminateExport)
        }
    }

    func testCancellationAfterDispatchIsIndeterminate() async {
        let playlistMBID = playlistMBID
        let transport = PlaylistServiceExportTransportFixture(mode: .suspends)
        let provider = ListenBrainzPlaylistServiceExportProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let task = Task {
            try await provider.export(
                playlistMBID: playlistMBID,
                to: .spotify,
                isPublic: true
            )
        }
        while await transport.callCount() == 0 { await Task.yield() }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected an indeterminate export")
        } catch let error as PlaylistServiceExportProviderError {
            XCTAssertEqual(error, .indeterminateExport)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQueuedCancellationNeverStartsTransport() async throws {
        let playlistMBID = playlistMBID
        let gate = RequestGate(minimumInterval: .zero)
        let blocker = GateBlocker()
        let blockingTask = Task {
            try await gate.perform {
                await blocker.markStarted()
                try await Task.sleep(for: .seconds(30))
            }
        }
        while !(await blocker.started()) { await Task.yield() }

        let transport = PlaylistServiceExportTransportFixture(mode: .success)
        let provider = ListenBrainzPlaylistServiceExportProvider(
            transport: transport,
            gate: gate
        )
        let queued = Task {
            try await provider.export(
                playlistMBID: playlistMBID,
                to: .spotify,
                isPublic: true
            )
        }
        while await gate.queuedRequestCountForTesting() == 0 { await Task.yield() }

        queued.cancel()

        do {
            _ = try await queued.value
            XCTFail("Expected cancellation before dispatch")
        } catch let error as PlaylistServiceExportProviderError {
            XCTAssertEqual(error, .cancelledBeforeTransport)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 0)
        blockingTask.cancel()
        _ = try? await blockingTask.value
    }

    private func assertProviderError(
        mode: PlaylistServiceExportTransportFixture.Mode,
        equals expected: PlaylistServiceExportProviderError
    ) async {
        let provider = ListenBrainzPlaylistServiceExportProvider(
            transport: PlaylistServiceExportTransportFixture(mode: mode),
            gate: RequestGate(minimumInterval: .zero)
        )
        do {
            _ = try await provider.export(
                playlistMBID: playlistMBID,
                to: .spotify,
                isPublic: true
            )
            XCTFail("Expected provider error")
        } catch let error as PlaylistServiceExportProviderError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor SuspendingPlaylistServiceExportProvider: PlaylistServiceExportProviding {
    private var continuation: CheckedContinuation<URL, any Error>?

    func export(
        playlistMBID: UUID,
        to service: PlaylistExternalService,
        isPublic: Bool
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func started() -> Bool { continuation != nil }

    func finish() {
        continuation?.resume(
            returning: URL(string: "https://open.spotify.com/playlist/fixture")!
        )
        continuation = nil
    }
}

private actor PlaylistServiceExportFixtureProvider: PlaylistServiceExportProviding {
    enum Mode: Sendable {
        case success
        case indeterminate
        case cancelledBeforeTransport
        case genericCancellation
    }

    struct Call: Equatable, Sendable {
        let playlistMBID: UUID
        let service: PlaylistExternalService
        let isPublic: Bool
    }

    private let mode: Mode
    private var recordedCalls: [Call] = []

    init(mode: Mode) { self.mode = mode }

    func export(
        playlistMBID: UUID,
        to service: PlaylistExternalService,
        isPublic: Bool
    ) async throws -> URL {
        recordedCalls.append(.init(
            playlistMBID: playlistMBID,
            service: service,
            isPublic: isPublic
        ))
        switch mode {
        case .success:
            return URL(string: "https://open.spotify.com/playlist/fixture")!
        case .indeterminate:
            throw PlaylistServiceExportProviderError.indeterminateExport
        case .cancelledBeforeTransport:
            throw PlaylistServiceExportProviderError.cancelledBeforeTransport
        case .genericCancellation:
            throw CancellationError()
        }
    }

    func calls() -> [Call] { recordedCalls }
    func callCount() -> Int { recordedCalls.count }
}

private actor PlaylistServiceExportTransportFixture: PlaylistServiceExportTransport {
    enum Mode: Sendable {
        case success
        case invalidAuth
        case badRequest
        case notFound
        case forbidden
        case rateLimited
        case invalidJSON
        case suspends

        static let failureCases: [Mode] = [
            .invalidAuth,
            .badRequest,
            .notFound,
            .forbidden,
            .rateLimited,
            .invalidJSON,
        ]
    }

    private let mode: Mode
    private var calls = 0

    init(mode: Mode) { self.mode = mode }

    func export(
        playlistMBID: UUID,
        to service: PlaylistExternalService,
        isPublic: Bool
    ) async throws -> URL {
        calls += 1
        switch mode {
        case .success:
            return URL(string: "https://open.spotify.com/playlist/fixture")!
        case .invalidAuth:
            throw LBError.invalidAuth
        case .badRequest:
            throw LBError.badRequest
        case .notFound:
            throw LBError.notFound
        case .forbidden:
            throw LBError.forbidden
        case .rateLimited:
            throw LBError.rateLimited(resetIn: 3)
        case .invalidJSON:
            throw LBError.invalidJSON
        case .suspends:
            try await Task.sleep(for: .seconds(30))
            return URL(string: "https://open.spotify.com/playlist/fixture")!
        }
    }

    func callCount() -> Int { calls }
}

private actor GateBlocker {
    private var value = false
    func markStarted() { value = true }
    func started() -> Bool { value }
}
