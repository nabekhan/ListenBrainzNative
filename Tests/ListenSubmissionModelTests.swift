import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class ListenSubmissionModelTests: XCTestCase {
    func testDraftTrimsBoundsUsesVisibleMinuteAndPreservesCanonicalMetadata() throws {
        let recording = fixtureRecording()
        var draft = ListenSubmissionDraft(recording: recording)
        draft.track = " \(recording.title) "
        draft.artist = " \(recording.artistName) "
        draft.release = " \(recording.releaseTitle!) "
        draft.playbackStartedAt = Date(timeIntervalSince1970: 1_700_000_039)

        let payload = try draft.payload(
            appVersion: "1",
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )

        XCTAssertEqual(payload.track, recording.title)
        XCTAssertEqual(payload.artist, recording.artistName)
        XCTAssertEqual(payload.release, recording.releaseTitle)
        XCTAssertEqual(payload.listenedAt?.timeIntervalSince1970, 1_699_999_980)
        XCTAssertEqual(payload.recordingMBID, recording.identity.mbid)
        XCTAssertEqual(payload.artistMBIDs, recording.artistMBIDs)
        XCTAssertEqual(payload.releaseMBID, recording.releaseMBID)
        XCTAssertEqual(payload.releaseGroupMBID, recording.releaseGroupMBID)
        XCTAssertEqual(payload.durationMilliseconds, 123_456)
    }

    func testEditingAnyPrefilledIdentityFieldRemovesAllInheritedIdentity() throws {
        let recording = fixtureRecording()
        var drafts = [
            ListenSubmissionDraft(recording: recording),
            ListenSubmissionDraft(recording: recording),
            ListenSubmissionDraft(recording: recording),
        ]
        drafts[0].track += " changed"
        drafts[1].artist += " changed"
        drafts[2].release += " changed"

        for draft in drafts {
            let payload = try draft.payload(appVersion: "1", now: .distantFuture)
            XCTAssertTrue(payload.artistMBIDs.isEmpty)
            XCTAssertNil(payload.recordingMBID)
            XCTAssertNil(payload.releaseMBID)
            XCTAssertNil(payload.releaseGroupMBID)
            XCTAssertNil(payload.durationMilliseconds)
        }
    }

    func testTextChangeInvalidatesIdentityPermanentlyAndBoundsFields() throws {
        var draft = ListenSubmissionDraft(recording: fixtureRecording())
        draft.track = String(repeating: "x", count: 600)
        draft.clampTextAndInvalidateIdentity()
        XCTAssertEqual(draft.track.count, ListenSubmissionDraft.maximumFieldLength)
        draft.track = fixtureRecording().title
        let payload = try draft.payload(appVersion: "1", now: .distantFuture)

        XCTAssertNil(payload.recordingMBID)
        XCTAssertTrue(payload.artistMBIDs.isEmpty)
    }

    func testInvalidDurationsAreOmitted() throws {
        var tooLong = ListenSubmissionDraft(recording: fixtureRecording())
        tooLong.durationMilliseconds = ListenSubmissionDraft.maximumDurationMilliseconds + 1
        XCTAssertNil(try tooLong.payload(appVersion: "1", now: .distantFuture).durationMilliseconds)

        var zero = ListenSubmissionDraft(recording: fixtureRecording())
        zero.durationMilliseconds = 0
        XCTAssertNil(try zero.payload(appVersion: "1", now: .distantFuture).durationMilliseconds)
    }

    func testPlayingNowOmitsTimestampAndValidationRequiresArtistAndTrack() throws {
        var draft = ListenSubmissionDraft()
        draft.mode = .playingNow
        draft.track = "  Song "
        draft.artist = " Artist "
        XCTAssertNil(try draft.payload(appVersion: "1").listenedAt)

        draft.artist = " "
        XCTAssertThrowsError(try draft.payload(appVersion: "1")) {
            XCTAssertEqual($0 as? ListenSubmissionValidationError, .artistRequired)
        }
        draft.artist = "Artist"
        draft.track = " "
        XCTAssertThrowsError(try draft.payload(appVersion: "1")) {
            XCTAssertEqual($0 as? ListenSubmissionValidationError, .trackRequired)
        }
    }

    func testTimestampAcceptsExactMinimumAndStrictlyRejectsFutureMinute() throws {
        var draft = validDraft(at: ListenSubmissionDraft.minimumDate)
        XCTAssertEqual(
            try draft.payload(appVersion: "1", now: ListenSubmissionDraft.minimumDate).listenedAt,
            ListenSubmissionDraft.minimumDate
        )

        draft.playbackStartedAt = ListenSubmissionDraft.minimumDate.addingTimeInterval(-1)
        XCTAssertThrowsError(try draft.payload(appVersion: "1", now: .distantFuture)) {
            XCTAssertEqual($0 as? ListenSubmissionValidationError, .timestampTooEarly)
        }

        let now = Date(timeIntervalSince1970: 1_700_000_005)
        draft.playbackStartedAt = Date(timeIntervalSince1970: 1_700_000_040)
        XCTAssertThrowsError(try draft.payload(appVersion: "1", now: now)) {
            XCTAssertEqual($0 as? ListenSubmissionValidationError, .timestampInFuture)
        }
    }

    func testReplayFingerprintIgnoresAppVersionAndHiddenSeconds() throws {
        var first = validDraft(at: Date(timeIntervalSince1970: 1_699_999_981))
        var second = validDraft(at: Date(timeIntervalSince1970: 1_700_000_039))
        first.release = "Album"
        second.release = "Album"

        let firstPayload = try first.payload(appVersion: "1", now: .distantFuture)
        let secondPayload = try second.payload(appVersion: "2", now: .distantFuture)

        XCTAssertEqual(firstPayload.listenedAt, secondPayload.listenedAt)
        XCTAssertEqual(firstPayload.fingerprint, secondPayload.fingerprint)
        XCTAssertEqual(
            ListenSubmissionJournal.fingerprint(account: " Listener ", payload: firstPayload),
            ListenSubmissionJournal.fingerprint(account: "listener", payload: secondPayload)
        )
    }

    func testOneExplicitListenSubmissionAndDoubleTapClaim() async {
        let provider = SubmissionFixtureProvider(delay: .milliseconds(30))
        let model = model(provider: provider)

        async let first: Void = model.send()
        async let second: Void = model.send()
        _ = await (first, second)

        let submissionCount = await provider.count()
        XCTAssertEqual(submissionCount, 1)
        XCTAssertEqual(model.phase, .sent)
        XCTAssertFalse(model.canSend)
        XCTAssertTrue(model.isFormLocked)
    }

    func testTwoModelsShareClaimAndExplicitReplayUsesFrozenPayload() async {
        let provider = SubmissionFixtureProvider(outcomes: [.failure(.indeterminate), .success])
        let journal = ListenSubmissionJournal()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_005)
        let first = model(provider: provider, journal: journal, timestamp: timestamp)
        let second = model(provider: provider, journal: journal, timestamp: timestamp)

        await first.send()
        await second.send()
        let initialCount = await provider.count()
        XCTAssertEqual(initialCount, 1)
        XCTAssertEqual(first.phase, .indeterminate)
        XCTAssertEqual(second.phase, .indeterminate)

        first.draft.track = "Edited after ambiguity"
        await first.send(retryIndeterminate: true)
        let payloads = await provider.payloads()
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0], payloads[1])
        XCTAssertEqual(first.phase, .sent)
    }

    func testConcurrentScenesMakeOneRequestAndLeaveSecondBehindWarning() async {
        let provider = SubmissionFixtureProvider(delay: .milliseconds(30))
        let journal = ListenSubmissionJournal()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_005)
        let first = model(provider: provider, journal: journal, timestamp: timestamp)
        let second = model(provider: provider, journal: journal, timestamp: timestamp)

        async let firstSend: Void = first.send()
        await Task.yield()
        async let secondSend: Void = second.send()
        _ = await (firstSend, secondSend)

        let count = await provider.count()
        XCTAssertEqual(count, 1)
        XCTAssertTrue(
            (first.phase == .sent && second.phase == .indeterminate)
                || (first.phase == .indeterminate && second.phase == .sent)
        )
        let warningModel = first.phase == .indeterminate ? first : second
        XCTAssertFalse(warningModel.canSend)
    }

    func testIndeterminateBarrierSurvivesNewJournalInstance() async {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let timestamp = Date(timeIntervalSince1970: 1_700_000_005)
        let firstProvider = SubmissionFixtureProvider(outcomes: [.failure(.indeterminate)])
        let first = model(
            provider: firstProvider,
            journal: ListenSubmissionJournal(fileURL: location.file),
            timestamp: timestamp
        )
        await first.send()

        let secondProvider = SubmissionFixtureProvider()
        let second = model(
            provider: secondProvider,
            journal: ListenSubmissionJournal(fileURL: location.file),
            timestamp: timestamp
        )
        await second.send()

        XCTAssertEqual(second.phase, .indeterminate)
        let secondCount = await secondProvider.count()
        XCTAssertEqual(secondCount, 0)
    }

    func testSuccessAndDefiniteFailureClearDurableBarrier() async {
        for outcome in [SubmissionFixtureOutcome.success, .failure(.rejected)] {
            let location = temporaryJournalLocation()
            defer { try? FileManager.default.removeItem(at: location.root) }
            let timestamp = Date(timeIntervalSince1970: 1_700_000_005)
            let firstProvider = SubmissionFixtureProvider(outcomes: [outcome])
            let first = model(
                provider: firstProvider,
                journal: ListenSubmissionJournal(fileURL: location.file),
                timestamp: timestamp
            )
            await first.send()

            XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path()))
            let secondProvider = SubmissionFixtureProvider()
            let second = model(
                provider: secondProvider,
                journal: ListenSubmissionJournal(fileURL: location.file),
                timestamp: timestamp
            )
            await second.send()
            let secondCount = await secondProvider.count()
            XCTAssertEqual(secondCount, 1)
        }
    }

    func testJournalPersistsOnlyOpaqueDataAndRejectsMalformedOrDuplicateRecords() throws {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let journal = ListenSubmissionJournal(fileURL: location.file)
        let payload = try fixturePayload()
        let fingerprint = ListenSubmissionJournal.fingerprint(account: "person", payload: payload)
        XCTAssertEqual(journal.reserve(fingerprint: fingerprint, retryingIndeterminate: false), .reserved)

        let text = try String(contentsOf: location.file, encoding: .utf8)
        XCTAssertFalse(text.contains("person"))
        XCTAssertFalse(text.contains("Song"))
        XCTAssertFalse(text.contains("Artist"))
        XCTAssertFalse(text.contains("token"))

        let duplicate = ListenSubmissionJournalRecord(fingerprint: fingerprint, attemptedAt: .now)
        try JSONEncoder().encode([duplicate, duplicate]).write(to: location.file)
        XCTAssertTrue(ListenSubmissionJournal(fileURL: location.file).requiresRecovery)

        try Data("not json".utf8).write(to: location.file)
        XCTAssertTrue(ListenSubmissionJournal(fileURL: location.file).requiresRecovery)
    }

    func testExplicitRecoveryResetRemovesCorruptBarrier() throws {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: location.file)
        let journal = ListenSubmissionJournal(fileURL: location.file)
        let provider = SubmissionFixtureProvider()
        let model = self.model(provider: provider, journal: journal)

        XCTAssertTrue(model.requiresSafetyRecovery)
        XCTAssertFalse(model.canSend)
        model.resetSafetyRecord()
        XCTAssertFalse(model.requiresSafetyRecovery)
        XCTAssertTrue(model.canSend)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path()))
    }

    func testUnwritableJournalFailsClosedAndCannotPretendToReset() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "ListenSubmissionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let journal = ListenSubmissionJournal(fileURL: folder)
        let fingerprint = ListenSubmissionJournal.fingerprint(account: "person", payload: try fixturePayload())

        XCTAssertEqual(journal.reserve(fingerprint: fingerprint, retryingIndeterminate: false), .unavailable)
        XCTAssertTrue(journal.requiresRecovery)
        XCTAssertFalse(journal.resetRecovery())
    }

    func testUnauthenticatedModelNeverCallsProvider() async {
        let provider = SubmissionFixtureProvider()
        let model = ListenSubmissionModel(
            account: .init(username: "me", token: ""),
            provider: provider,
            journal: .init()
        )
        model.draft.track = "Song"
        model.draft.artist = "Artist"

        await model.send()

        let callCount = await provider.count()
        XCTAssertEqual(callCount, 0)
    }

    func testPlayingNowClaimsAreAccountScoped() async {
        let provider = SubmissionFixtureProvider()
        let claims = PlayingNowSubmissionClaims()
        let first = playingNowModel(username: "first", provider: provider, claims: claims)
        let sameAccount = playingNowModel(username: "FIRST", provider: provider, claims: claims)
        let otherAccount = playingNowModel(username: "second", provider: provider, claims: claims)

        await first.send()
        await sameAccount.send()
        await otherAccount.send()

        let callCount = await provider.count()
        XCTAssertEqual(callCount, 2)
        guard case .failed = sameAccount.phase else { return XCTFail("Expected duplicate suppression") }
        XCTAssertEqual(otherAccount.phase, .sent)
    }

    func testPlayingNowDefiniteFailureCanBeRetriedImmediately() async {
        let provider = SubmissionFixtureProvider(outcomes: [.failure(.rejected), .success])
        let model = playingNowModel(username: "listener", provider: provider, claims: .init())

        await model.send()
        guard case .failed = model.phase else { return XCTFail("Expected definite failure") }
        await model.send()

        let callCount = await provider.count()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(model.phase, .sent)
    }

    func testProviderSendsExactSingleAndPlayingNowMetadataOnce() async throws {
        let artistID = UUID()
        let recordingID = UUID()
        let releaseID = UUID()
        let groupID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = SubmissionTransportSpy()
        let provider = ListenBrainzSubmissionProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let listen = ListenSubmissionPayload(
            mode: .listen,
            artist: "Artist",
            track: "Song",
            release: "Album",
            listenedAt: timestamp,
            artistMBIDs: [artistID],
            recordingMBID: recordingID,
            releaseMBID: releaseID,
            releaseGroupMBID: groupID,
            durationMilliseconds: 234_000,
            appVersion: "7"
        )
        let playingNow = ListenSubmissionPayload(
            mode: .playingNow,
            artist: listen.artist,
            track: listen.track,
            release: listen.release,
            listenedAt: nil,
            artistMBIDs: listen.artistMBIDs,
            recordingMBID: listen.recordingMBID,
            releaseMBID: listen.releaseMBID,
            releaseGroupMBID: listen.releaseGroupMBID,
            durationMilliseconds: listen.durationMilliseconds,
            appVersion: listen.appVersion
        )

        try await provider.submit(listen)
        try await provider.submit(playingNow)

        let calls = await transport.calls()
        XCTAssertEqual(calls.count, 2)
        guard case let .listen(metadata, date) = calls[0] else { return XCTFail("Expected a single listen") }
        XCTAssertEqual(date, timestamp)
        assertMetadata(metadata, artistID: artistID, recordingID: recordingID, releaseID: releaseID, groupID: groupID)
        guard case let .playingNow(metadata) = calls[1] else { return XCTFail("Expected Playing Now") }
        assertMetadata(metadata, artistID: artistID, recordingID: recordingID, releaseID: releaseID, groupID: groupID)
    }

    func testProviderRejectsMissingSingleTimestampBeforeTransport() async {
        let transport = SubmissionTransportSpy()
        let provider = ListenBrainzSubmissionProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let invalid = ListenSubmissionPayload(
            mode: .listen,
            artist: "Artist",
            track: "Song",
            release: nil,
            listenedAt: nil,
            artistMBIDs: [],
            recordingMBID: nil,
            releaseMBID: nil,
            releaseGroupMBID: nil,
            durationMilliseconds: nil,
            appVersion: "1"
        )

        await assertSubmissionError(.rejected) { try await provider.submit(invalid) }
        let calls = await transport.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testProviderMapsDefiniteFailuresAndUnknownResultsWithoutRetry() async throws {
        let cases: [(any Error & Sendable, ListenSubmissionError)] = [
            (LBError.invalidJSON, .rejected),
            (LBError.badRequest, .rejected),
            (LBError.invalidParam, .rejected),
            (LBError.invalidAuth, .authentication),
            (LBError.noToken, .authentication),
            (LBError.forbidden, .forbidden),
            (LBError.invalidResponse, .indeterminate),
            (LBError.noContent, .indeterminate),
            (LBError.unknownError, .indeterminate),
        ]
        for (source, expected) in cases {
            let transport = SubmissionTransportSpy(error: source)
            let provider = ListenBrainzSubmissionProvider(
                transport: transport,
                gate: RequestGate(minimumInterval: .zero)
            )
            await assertSubmissionError(expected) { try await provider.submit(try self.fixturePayload()) }
            let calls = await transport.calls()
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testProviderMapsRateLimitAndDoesNotRetry() async throws {
        let transport = SubmissionTransportSpy(error: LBError.rateLimited(resetIn: 7))
        let provider = ListenBrainzSubmissionProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        await assertSubmissionError(.rateLimited(7)) { try await provider.submit(try self.fixturePayload()) }
        let calls = await transport.calls()
        XCTAssertEqual(calls.count, 1)
    }

    func testProviderCancellationBeforeTransportDoesNotDispatch() async throws {
        let blocker = SubmissionGateBlocker()
        let gate = RequestGate(minimumInterval: .zero)
        let blockingTask = Task { try await gate.perform { await blocker.run() } }
        while !(await blocker.hasStarted()) { await Task.yield() }
        let transport = SubmissionTransportSpy()
        let provider = ListenBrainzSubmissionProvider(transport: transport, gate: gate)
        let payload = try fixturePayload()
        let task = Task { try await provider.submit(payload) }
        while await gate.queuedRequestCountForTesting() == 0 { await Task.yield() }

        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // The request never entered transport.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await blocker.release()
        _ = try await blockingTask.value
        let calls = await transport.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testProviderCancellationAfterTransportIsIndeterminate() async throws {
        let transport = CancellationSubmissionTransport()
        let provider = ListenBrainzSubmissionProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let payload = try fixturePayload()
        let task = Task { try await provider.submit(payload) }
        while !(await transport.hasStarted()) { await Task.yield() }

        task.cancel()
        await assertSubmissionError(.indeterminate) { try await task.value }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    private func model(
        provider: some ListenSubmitting,
        journal: ListenSubmissionJournal = .init(),
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_005)
    ) -> ListenSubmissionModel {
        let model = ListenSubmissionModel(
            account: .init(username: "listener", token: "token"),
            provider: provider,
            journal: journal,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        model.draft = validDraft(at: timestamp)
        return model
    }

    private func playingNowModel(
        username: String,
        provider: some ListenSubmitting,
        claims: PlayingNowSubmissionClaims
    ) -> ListenSubmissionModel {
        let model = ListenSubmissionModel(
            account: .init(username: username, token: "token"),
            mode: .playingNow,
            provider: provider,
            journal: .init(),
            playingNowClaims: claims
        )
        model.draft.track = "Song"
        model.draft.artist = "Artist"
        return model
    }

    private func validDraft(at timestamp: Date) -> ListenSubmissionDraft {
        var draft = ListenSubmissionDraft()
        draft.track = "Song"
        draft.artist = "Artist"
        draft.playbackStartedAt = timestamp
        return draft
    }

    private func fixturePayload() throws -> ListenSubmissionPayload {
        try validDraft(at: Date(timeIntervalSince1970: 1_700_000_005))
            .payload(appVersion: "1", now: .distantFuture)
    }

    private func fixtureRecording() -> Recording {
        Recording(
            identity: .init(mbid: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"), msid: nil),
            title: "Track",
            artistName: "Artist",
            artistMBIDs: [UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!],
            releaseTitle: "Release",
            releaseMBID: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
            releaseGroupMBID: UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd"),
            artworkReleaseMBID: nil,
            durationMilliseconds: 123_456,
            source: nil
        )
    }

    private func temporaryJournalLocation() -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ListenSubmissionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        return (root, root.appending(path: "journal.json"))
    }

    private func assertMetadata(
        _ metadata: LBTrackMetadata,
        artistID: UUID,
        recordingID: UUID,
        releaseID: UUID,
        groupID: UUID
    ) {
        XCTAssertEqual(metadata.artist, "Artist")
        XCTAssertEqual(metadata.track, "Song")
        XCTAssertEqual(metadata.release, "Album")
        XCTAssertEqual(metadata.additionalInfo?.artistMbids, [artistID])
        XCTAssertEqual(metadata.additionalInfo?.recordingMbid, recordingID)
        XCTAssertEqual(metadata.additionalInfo?.releaseMbid, releaseID)
        XCTAssertEqual(metadata.additionalInfo?.releaseGroupMbid, groupID)
        XCTAssertEqual(metadata.additionalInfo?.durationMs, 234_000)
        XCTAssertEqual(metadata.additionalInfo?.submissionClient, "Brainz")
        XCTAssertEqual(metadata.additionalInfo?.submissionClientVersion, "7")
    }

    private func assertSubmissionError(
        _ expected: ListenSubmissionError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as ListenSubmissionError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private enum SubmissionFixtureOutcome: Sendable {
    case success
    case failure(ListenSubmissionError)
}

private actor SubmissionFixtureProvider: ListenSubmitting {
    private var values: [ListenSubmissionPayload] = []
    private var outcomes: [SubmissionFixtureOutcome]
    private let delay: Duration

    init(
        outcomes: [SubmissionFixtureOutcome] = [.success],
        delay: Duration = .zero
    ) {
        self.outcomes = outcomes
        self.delay = delay
    }

    func submit(_ payload: ListenSubmissionPayload) async throws {
        values.append(payload)
        if delay > .zero { try await Task.sleep(for: delay) }
        let outcome = outcomes.isEmpty ? .success : outcomes.removeFirst()
        if case let .failure(error) = outcome { throw error }
    }

    func count() -> Int { values.count }
    func payloads() -> [ListenSubmissionPayload] { values }
}

private actor SubmissionTransportSpy: ListenSubmissionTransport {
    enum Call: Equatable, Sendable {
        case listen(LBTrackMetadata, Date)
        case playingNow(LBTrackMetadata)
    }

    private let error: (any Error & Sendable)?
    private var values: [Call] = []

    init(error: (any Error & Sendable)? = nil) {
        self.error = error
    }

    func submitListen(metadata: LBTrackMetadata, at listenedAt: Date) async throws {
        values.append(.listen(metadata, listenedAt))
        if let error { throw error }
    }

    func submitPlayingNow(metadata: LBTrackMetadata) async throws {
        values.append(.playingNow(metadata))
        if let error { throw error }
    }

    func calls() -> [Call] { values }
}

private actor CancellationSubmissionTransport: ListenSubmissionTransport {
    private var started = false
    private var count = 0

    func submitListen(metadata: LBTrackMetadata, at listenedAt: Date) async throws {
        started = true
        count += 1
        try await Task.sleep(for: .seconds(60))
    }

    func submitPlayingNow(metadata: LBTrackMetadata) async throws {
        started = true
        count += 1
        try await Task.sleep(for: .seconds(60))
    }

    func hasStarted() -> Bool { started }
    func callCount() -> Int { count }
}

private actor SubmissionGateBlocker {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func run() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }

    func hasStarted() -> Bool { started }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
