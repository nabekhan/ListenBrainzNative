import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class ManualMappingTests: XCTestCase {
    func testEligibilityRequiresAuthenticatedPermanentListenWithoutSubmittedRecordingMBID() {
        let eligible = makeListen()
        guard case let .available(msid, currentMBID) = ManualMappingModel.availability(
            account: account,
            listen: eligible
        ) else {
            return XCTFail("Expected mapping to be available")
        }
        XCTAssertEqual(msid, eligible.inspection?.recordingMSID)
        XCTAssertNil(currentMBID)

        XCTAssertUnavailable(account: Account(username: "listener", token: ""), listen: eligible)
        XCTAssertUnavailable(
            account: account,
            listen: Listen(
                recording: eligible.recording,
                listenedAt: .now,
                insertedAt: nil,
                isPlayingNow: true,
                inspection: eligible.inspection
            )
        )
        XCTAssertUnavailable(account: account, listen: makeListen(includesInspection: false))
        XCTAssertUnavailable(account: account, listen: makeListen(recordingMSID: nil))
        XCTAssertUnavailable(account: account, listen: makeListen(submittedMBID: UUID()))
    }

    func testNoRequestBeforeExplicitSaveAndSuccessUsesExactIdentityPairOnce() async {
        let spy = MappingProviderSpy()
        let listen = makeListen()
        let model = ManualMappingModel(account: account, listen: listen, provider: spy)
        let callsBeforeSave = await spy.callCount()
        XCTAssertEqual(callsBeforeSave, 0)

        let selectedMBID = UUID()
        await model.save(mbid: selectedMBID)

        let callsAfterSave = await spy.callCount()
        XCTAssertEqual(callsAfterSave, 1)
        let pair = await spy.lastPair()
        XCTAssertEqual(pair?.msid, listen.inspection?.recordingMSID)
        XCTAssertEqual(pair?.mbid, selectedMBID)
        XCTAssertEqual(model.savedMBID, selectedMBID)
    }

    func testConcurrentSaveTapsDispatchOnlyOneMutation() async {
        let spy = MappingProviderSpy(outcomes: [.waitForResume])
        let model = ManualMappingModel(account: account, listen: makeListen(), provider: spy)
        let selectedMBID = UUID()

        let first = Task { await model.save(mbid: selectedMBID) }
        while await spy.callCount() == 0 { await Task.yield() }
        let second = Task { await model.save(mbid: selectedMBID) }
        await second.value
        await spy.resumeWaitingSubmission()
        await first.value

        let calls = await spy.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.savedMBID, selectedMBID)
    }

    func testDefiniteFailureCanRetryOnlyAfterAnotherExplicitSave() async {
        let spy = MappingProviderSpy(outcomes: [.rejected, .success])
        let model = ManualMappingModel(account: account, listen: makeListen(), provider: spy)
        let selectedMBID = UUID()

        await model.save(mbid: selectedMBID)
        guard case .failed = model.state else { return XCTFail("Expected a definite failure") }
        let callsAfterFailure = await spy.callCount()
        XCTAssertEqual(callsAfterFailure, 1)

        await model.save(mbid: selectedMBID)
        let callsAfterRetry = await spy.callCount()
        XCTAssertEqual(callsAfterRetry, 2)
        XCTAssertEqual(model.savedMBID, selectedMBID)
    }

    func testUnknownOutcomeBlocksOrdinaryRetryUntilUserExplicitlySendsAgain() async {
        let spy = MappingProviderSpy(outcomes: [.unknown, .success])
        let model = ManualMappingModel(account: account, listen: makeListen(), provider: spy)
        let selectedMBID = UUID()

        await model.save(mbid: selectedMBID)
        XCTAssertEqual(model.state, .outcomeUnknown)
        await model.save(mbid: selectedMBID)
        let callsBeforeExplicitRetry = await spy.callCount()
        XCTAssertEqual(callsBeforeExplicitRetry, 1)

        await model.save(mbid: selectedMBID, sendAgainAfterUnknown: true)
        let callsAfterExplicitRetry = await spy.callCount()
        XCTAssertEqual(callsAfterExplicitRetry, 2)
        XCTAssertEqual(model.savedMBID, selectedMBID)
    }

    func testUnknownOutcomeSurvivesCandidateNavigationAndStillRequiresConfirmation() async {
        let spy = MappingProviderSpy(outcomes: [.unknown, .success])
        let model = ManualMappingModel(account: account, listen: makeListen(), provider: spy)

        await model.save(mbid: UUID())
        XCTAssertEqual(model.state, .outcomeUnknown)

        model.resetForNewSelection()
        XCTAssertEqual(model.state, .outcomeUnknown)
        await model.save(mbid: UUID())

        let calls = await spy.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testCurrentMatchNeverDispatchesRedundantMutation() async {
        let currentMBID = UUID()
        let spy = MappingProviderSpy()
        let model = ManualMappingModel(
            account: account,
            listen: makeListen(resolvedMBID: currentMBID),
            provider: spy
        )

        await model.save(mbid: currentMBID)

        let calls = await spy.callCount()
        XCTAssertEqual(calls, 0)
        guard case .failed = model.state else { return XCTFail("Expected an explanatory local state") }
    }

    func testSubmittedRecordingMBIDRemainsIneligibleWhenSaveIsCalledDirectly() async {
        let spy = MappingProviderSpy()
        let model = ManualMappingModel(
            account: account,
            listen: makeListen(submittedMBID: UUID()),
            provider: spy
        )

        await model.save(mbid: UUID())

        let calls = await spy.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.state, .idle)
    }

    nonisolated func testProviderMapsDefiniteServerFailuresWithoutReplay() async {
        let rejectedTransport = ManualMappingTransportSpy(error: LBError.invalidJSON)
        let rejected = ManualMappingProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: rejectedTransport
        )
        do {
            try await rejected.submit(msid: UUID(), mbid: UUID())
            XCTFail("Expected a definite rejection")
        } catch ProviderError.manualMappingRejected {
            // A response-backed validation error is safe to present as retryable.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let rejectedCalls = await rejectedTransport.callCount
        XCTAssertEqual(rejectedCalls, 1)

        let authTransport = ManualMappingTransportSpy(error: LBError.invalidAuth)
        let auth = ManualMappingProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: authTransport
        )
        do {
            try await auth.submit(msid: UUID(), mbid: UUID())
            XCTFail("Expected an invalid token")
        } catch ProviderError.invalidToken {
            // Authentication failed before a mapping could be accepted.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let authCalls = await authTransport.callCount
        XCTAssertEqual(authCalls, 1)
    }

    nonisolated func testProviderMapsRateLimitAsDefiniteAndUnknownTransportAsIndeterminate() async {
        let rateLimitedTransport = ManualMappingTransportSpy(error: LBError.rateLimited(resetIn: 7))
        let rateLimited = ManualMappingProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: rateLimitedTransport
        )
        do {
            try await rateLimited.submit(msid: UUID(), mbid: UUID())
            XCTFail("Expected rate limiting")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 7)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let rateLimitedCalls = await rateLimitedTransport.callCount
        XCTAssertEqual(rateLimitedCalls, 1)

        let unknownTransport = ManualMappingTransportSpy(error: LBError.unknownError)
        let unknown = ManualMappingProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: unknownTransport
        )
        do {
            try await unknown.submit(msid: UUID(), mbid: UUID())
            XCTFail("Expected an indeterminate outcome")
        } catch ProviderError.manualMappingOutcomeUnknown {
            // A failed or lost response cannot prove that the upsert did not commit.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let unknownCalls = await unknownTransport.callCount
        XCTAssertEqual(unknownCalls, 1)

        let networkTransport = ManualMappingTransportSpy(error: URLError(.networkConnectionLost))
        let network = ManualMappingProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: networkTransport
        )
        do {
            try await network.submit(msid: UUID(), mbid: UUID())
            XCTFail("Expected a network failure to remain indeterminate")
        } catch ProviderError.manualMappingOutcomeUnknown {
            // The transport began, so a lost response must not be replayed.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let networkCalls = await networkTransport.callCount
        XCTAssertEqual(networkCalls, 1)
    }

    nonisolated func testProviderCancellationBeforeGateAdmissionSendsNothing() async throws {
        let gate = RequestGate(minimumInterval: .seconds(5))
        _ = try await gate.perform { true }
        let transport = ManualMappingTransportSpy()
        let provider = ManualMappingProvider(gate: gate, transport: transport)
        let task = Task { try await provider.submit(msid: UUID(), mbid: UUID()) }
        await Task.yield()
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected pre-dispatch cancellation")
        } catch is CancellationError {
            // RequestGate did not admit the POST.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 0)
    }

    nonisolated func testProviderCancellationAfterDispatchIsIndeterminate() async {
        let transport = ManualMappingTransportSpy(waitsForCancellation: true)
        let provider = ManualMappingProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )
        let task = Task { try await provider.submit(msid: UUID(), mbid: UUID()) }
        while !(await transport.hasStarted) { await Task.yield() }
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected an indeterminate post-dispatch cancellation")
        } catch ProviderError.manualMappingOutcomeUnknown {
            // The transport started, so cancellation cannot prove rejection.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let calls = await transport.callCount
        XCTAssertEqual(calls, 1)
    }

    func testStatusEligibilityRequiresAnAuthenticatedPermanentListenWithAnMSID() {
        let eligible = makeListen()
        guard case let .available(msid) = ManualMappingStatusModel.availability(
            account: account,
            listen: eligible
        ) else {
            return XCTFail("Expected status lookup to be available")
        }
        XCTAssertEqual(msid, eligible.inspection?.recordingMSID)

        XCTAssertStatusUnavailable(account: nil, listen: eligible)
        XCTAssertStatusUnavailable(account: Account(username: "listener", token: ""), listen: eligible)
        XCTAssertStatusUnavailable(
            account: account,
            listen: Listen(
                recording: eligible.recording,
                listenedAt: .now,
                insertedAt: nil,
                isPlayingNow: true,
                inspection: eligible.inspection
            )
        )
        XCTAssertStatusUnavailable(account: account, listen: makeListen(includesInspection: false))
        XCTAssertStatusUnavailable(account: account, listen: makeListen(recordingMSID: nil))
        guard case .available = ManualMappingStatusModel.availability(
            account: account,
            listen: makeListen(submittedMBID: UUID())
        ) else {
            return XCTFail("Submitted metadata should not hide an existing saved manual match")
        }
    }

    func testStatusRefreshGuidanceHonorsSubmittedRecordingMBIDPrecedence() {
        let savedMBID = UUID()

        let unmapped = makeListen()
        let submitted = makeListen(submittedMBID: UUID())
        let alreadyResolved = makeListen(resolvedMBID: savedMBID)
        guard let unmappedDetails = unmapped.inspection,
              let submittedDetails = submitted.inspection,
              let resolvedDetails = alreadyResolved.inspection
        else {
            return XCTFail("Expected inspection fixtures")
        }

        XCTAssertTrue(ManualMappingStatusModel.shouldSuggestHistoryRefresh(
            details: unmappedDetails,
            savedMBID: savedMBID
        ))
        XCTAssertFalse(ManualMappingStatusModel.shouldSuggestHistoryRefresh(
            details: submittedDetails,
            savedMBID: savedMBID
        ))
        XCTAssertFalse(ManualMappingStatusModel.shouldSuggestHistoryRefresh(
            details: resolvedDetails,
            savedMBID: savedMBID
        ))
    }

    func testStatusModelMakesNoRequestUntilExplicitCheckAndKeepsTerminalResult() async {
        let mbid = UUID()
        let spy = MappingStatusProviderSpy(outcomes: [.found(mbid)])
        let listen = makeListen()
        let model = ManualMappingStatusModel(account: account, listen: listen, provider: spy)

        let callsBeforeCheck = await spy.callCount()
        XCTAssertEqual(callsBeforeCheck, 0)
        XCTAssertEqual(model.state, .idle)

        await model.check()

        let callsAfterCheck = await spy.callCount()
        let checkedMSID = await spy.lastMSID()
        XCTAssertEqual(callsAfterCheck, 1)
        XCTAssertEqual(checkedMSID, listen.inspection?.recordingMSID)
        XCTAssertEqual(model.state, .found(mbid))

        await model.check()
        let callsAfterTerminalCheck = await spy.callCount()
        XCTAssertEqual(callsAfterTerminalCheck, 1)
    }

    func testStatusModelDistinguishesNoSavedMatchFromFailureAndAllowsExplicitRetry() async {
        let missing = MappingStatusProviderSpy(outcomes: [.missing])
        let missingModel = ManualMappingStatusModel(account: account, listen: makeListen(), provider: missing)

        await missingModel.check()

        XCTAssertEqual(missingModel.state, .notFound)
        await missingModel.check()
        let missingCalls = await missing.callCount()
        XCTAssertEqual(missingCalls, 1)

        let mbid = UUID()
        let retry = MappingStatusProviderSpy(outcomes: [.failure, .found(mbid)])
        let retryModel = ManualMappingStatusModel(account: account, listen: makeListen(), provider: retry)

        await retryModel.check()
        guard case .failed = retryModel.state else { return XCTFail("Expected a visible lookup failure") }
        await retryModel.check()

        let retryCalls = await retry.callCount()
        XCTAssertEqual(retryCalls, 2)
        XCTAssertEqual(retryModel.state, .found(mbid))
    }

    func testStatusModelCoalescesRapidExplicitChecksLocally() async {
        let mbid = UUID()
        let spy = MappingStatusProviderSpy(outcomes: [.waitForResume(mbid)])
        let model = ManualMappingStatusModel(account: account, listen: makeListen(), provider: spy)

        let first = Task { await model.check() }
        while await spy.callCount() == 0 { await Task.yield() }
        let second = Task { await model.check() }
        await second.value

        let callsWhileWaiting = await spy.callCount()
        XCTAssertEqual(callsWhileWaiting, 1)
        await spy.resumeWaitingLookup()
        await first.value
        XCTAssertEqual(model.state, .found(mbid))
    }

    func testStatusModelReturnsToIdleWhenItsStructuredReadIsCancelled() async {
        let spy = MappingStatusProviderSpy(outcomes: [.waitForCancellation])
        let model = ManualMappingStatusModel(account: account, listen: makeListen(), provider: spy)
        let task = Task { await model.check() }
        while await spy.callCount() == 0 { await Task.yield() }

        task.cancel()
        await task.value

        XCTAssertEqual(model.state, .idle)
        let cancellationCalls = await spy.callCount()
        XCTAssertEqual(cancellationCalls, 1)
    }

    func testConfirmedSaveUpdatesStatusWithoutARead() async {
        let spy = MappingStatusProviderSpy(outcomes: [.failure])
        let model = ManualMappingStatusModel(account: account, listen: makeListen(), provider: spy)
        let mbid = UUID()

        model.confirmSaved(mbid: mbid)
        await model.check()

        XCTAssertEqual(model.state, .found(mbid))
        let confirmedCalls = await spy.callCount()
        XCTAssertEqual(confirmedCalls, 0)
    }

    func testConfirmedSaveCannotBeOverwrittenByAnOlderLookup() async {
        let oldMBID = UUID()
        let savedMBID = UUID()
        let spy = MappingStatusProviderSpy(outcomes: [.waitForResume(oldMBID)])
        let model = ManualMappingStatusModel(account: account, listen: makeListen(), provider: spy)
        let lookup = Task { await model.check() }
        while await spy.callCount() == 0 { await Task.yield() }

        model.confirmSaved(mbid: savedMBID)
        await spy.resumeWaitingLookup()
        await lookup.value

        XCTAssertEqual(model.state, .found(savedMBID))
        let calls = await spy.callCount()
        XCTAssertEqual(calls, 1)
    }

    nonisolated func testStatusProviderReturnsExactMappingAndCoalescesConcurrentReads() async throws {
        let msid = UUID()
        let mbid = UUID()
        let transport = ManualMappingStatusTransportSpy(
            returnedMBID: mbid,
            waitsForResume: true
        )
        let provider = ManualMappingStatusProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )

        let first = Task { try await provider.savedMapping(msid: msid) }
        while await transport.callCount == 0 { await Task.yield() }
        let second = Task { try await provider.savedMapping(msid: msid) }
        for _ in 0 ..< 20 { await Task.yield() }

        let callsBeforeResume = await transport.callCount
        XCTAssertEqual(callsBeforeResume, 1)
        await transport.resume()
        let firstResult = try await first.value
        let secondResult = try await second.value

        XCTAssertEqual(firstResult, ManualMappingIdentity(msid: msid, mbid: mbid))
        XCTAssertEqual(secondResult, firstResult)
        let callsAfterCoalescing = await transport.callCount
        XCTAssertEqual(callsAfterCoalescing, 1)
    }

    nonisolated func testStatusProviderTreatsNotFoundAsAValidEmptyResultWithoutRetry() async throws {
        let transport = ManualMappingStatusTransportSpy(error: LBError.notFound)
        let provider = ManualMappingStatusProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )

        let result = try await provider.savedMapping(msid: UUID())

        XCTAssertNil(result)
        let notFoundCalls = await transport.callCount
        XCTAssertEqual(notFoundCalls, 1)
    }

    nonisolated func testStatusProviderFailsClosedForMismatchedIdentityAndTransportFailures() async {
        let requestedMSID = UUID()
        let mismatchTransport = ManualMappingStatusTransportSpy(returnedMSID: UUID())
        let mismatch = ManualMappingStatusProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: mismatchTransport
        )
        do {
            _ = try await mismatch.savedMapping(msid: requestedMSID)
            XCTFail("Expected a mismatched response to fail closed")
        } catch ProviderError.manualMappingCheckUnavailable {
            // A response for another MSID must never be shown as this listen's mapping.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let mismatchCalls = await mismatchTransport.callCount
        XCTAssertEqual(mismatchCalls, 1)

        let authTransport = ManualMappingStatusTransportSpy(error: LBError.invalidAuth)
        let auth = ManualMappingStatusProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: authTransport
        )
        do {
            _ = try await auth.savedMapping(msid: requestedMSID)
            XCTFail("Expected invalid authentication")
        } catch ProviderError.invalidToken {
            // The account boundary is preserved.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let authCalls = await authTransport.callCount
        XCTAssertEqual(authCalls, 1)

        let unavailableTransport = ManualMappingStatusTransportSpy(error: URLError(.networkConnectionLost))
        let unavailable = ManualMappingStatusProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: unavailableTransport
        )
        do {
            _ = try await unavailable.savedMapping(msid: requestedMSID)
            XCTFail("Expected an unavailable lookup")
        } catch ProviderError.manualMappingCheckUnavailable {
            // Reads are never retried automatically.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let unavailableCalls = await unavailableTransport.callCount
        XCTAssertEqual(unavailableCalls, 1)
    }

    nonisolated func testStatusProviderMapsRateLimitWithoutRetry() async {
        let transport = ManualMappingStatusTransportSpy(error: LBError.rateLimited(resetIn: 9))
        let provider = ManualMappingStatusProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: transport
        )

        do {
            _ = try await provider.savedMapping(msid: UUID())
            XCTFail("Expected rate limiting")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 9)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let rateLimitedCalls = await transport.callCount
        XCTAssertEqual(rateLimitedCalls, 1)
    }

    private let account = Account(username: "listener", token: "token")

    private func XCTAssertUnavailable(
        account: Account,
        listen: Listen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unavailable = ManualMappingModel.availability(account: account, listen: listen) else {
            return XCTFail("Expected mapping to be unavailable", file: file, line: line)
        }
    }

    private func XCTAssertStatusUnavailable(
        account: Account?,
        listen: Listen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unavailable = ManualMappingStatusModel.availability(account: account, listen: listen) else {
            return XCTFail("Expected status lookup to be unavailable", file: file, line: line)
        }
    }

    private func makeListen(
        includesInspection: Bool = true,
        recordingMSID: UUID? = UUID(),
        submittedMBID: UUID? = nil,
        resolvedMBID: UUID? = nil
    ) -> Listen {
        let details = ListenInspection(
            submittedArtist: "Artist",
            submittedTrack: "Track",
            submittedRelease: "Release",
            recordingMSID: recordingMSID,
            submittedRecordingMSID: nil,
            submittedArtistMBIDs: [],
            submittedRecordingMBID: submittedMBID,
            submittedReleaseMBID: nil,
            submittedReleaseGroupMBID: nil,
            submittedTrackMBID: nil,
            submittedWorkMBIDs: [],
            resolvedArtistMBIDs: [],
            resolvedRecordingMBID: resolvedMBID,
            resolvedReleaseMBID: nil,
            resolvedReleaseGroupMBID: nil,
            resolvedRecordingName: nil,
            trackNumber: nil,
            isrc: nil,
            spotifyID: nil,
            tags: [],
            mediaPlayer: nil,
            mediaPlayerVersion: nil,
            submissionClient: nil,
            submissionClientVersion: nil,
            musicService: nil,
            musicServiceName: nil,
            originURL: nil,
            durationMilliseconds: nil
        )
        return Listen(
            recording: Recording(
                identity: .init(mbid: nil, msid: recordingMSID),
                title: "Track",
                artistName: "Artist",
                artistMBIDs: [],
                releaseTitle: "Release",
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: .now,
            insertedAt: nil,
            isPlayingNow: false,
            inspection: includesInspection ? details : nil
        )
    }
}

private actor MappingProviderSpy: ManualMappingProviding {
    enum Outcome: Sendable {
        case success
        case rejected
        case unknown
        case waitForResume
    }

    private var outcomes: [Outcome]
    private var pairs: [(msid: UUID, mbid: UUID)] = []
    private var waitingContinuation: CheckedContinuation<Void, Never>?

    init(outcomes: [Outcome] = [.success]) {
        self.outcomes = outcomes
    }

    func submit(msid: UUID, mbid: UUID) async throws {
        pairs.append((msid, mbid))
        let outcome = outcomes.isEmpty ? .success : outcomes.removeFirst()
        switch outcome {
        case .success:
            return
        case .rejected:
            throw ProviderError.manualMappingRejected
        case .unknown:
            throw ProviderError.manualMappingOutcomeUnknown
        case .waitForResume:
            await withCheckedContinuation { continuation in
                waitingContinuation = continuation
            }
        }
    }

    func callCount() -> Int { pairs.count }
    func lastPair() -> (msid: UUID, mbid: UUID)? { pairs.last }

    func resumeWaitingSubmission() {
        waitingContinuation?.resume()
        waitingContinuation = nil
    }
}

private actor ManualMappingTransportSpy: ManualMappingTransport {
    private let error: (any Error & Sendable)?
    private let waitsForCancellation: Bool
    private(set) var callCount = 0
    private(set) var hasStarted = false

    init(error: (any Error & Sendable)? = nil, waitsForCancellation: Bool = false) {
        self.error = error
        self.waitsForCancellation = waitsForCancellation
    }

    func submitManualMapping(msid: UUID, mbid: UUID) async throws {
        callCount += 1
        hasStarted = true
        if waitsForCancellation {
            try await ContinuousClock().sleep(for: .seconds(30))
        }
        if let error { throw error }
    }
}

private actor MappingStatusProviderSpy: ManualMappingStatusProviding {
    enum Outcome: Sendable {
        case found(UUID)
        case missing
        case failure
        case waitForResume(UUID)
        case waitForCancellation
    }

    private var outcomes: [Outcome]
    private var requestedMSIDs: [UUID] = []
    private var waitingContinuation: CheckedContinuation<Void, Never>?

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func savedMapping(msid: UUID) async throws -> ManualMappingIdentity? {
        requestedMSIDs.append(msid)
        let outcome = outcomes.isEmpty ? .missing : outcomes.removeFirst()
        switch outcome {
        case let .found(mbid):
            return ManualMappingIdentity(msid: msid, mbid: mbid)
        case .missing:
            return nil
        case .failure:
            throw ProviderError.manualMappingCheckUnavailable
        case let .waitForResume(mbid):
            await withCheckedContinuation { continuation in
                waitingContinuation = continuation
            }
            return ManualMappingIdentity(msid: msid, mbid: mbid)
        case .waitForCancellation:
            try await ContinuousClock().sleep(for: .seconds(30))
            return nil
        }
    }

    func callCount() -> Int { requestedMSIDs.count }
    func lastMSID() -> UUID? { requestedMSIDs.last }

    func resumeWaitingLookup() {
        waitingContinuation?.resume()
        waitingContinuation = nil
    }
}

private actor ManualMappingStatusTransportSpy: ManualMappingStatusTransport {
    private let returnedMSID: UUID?
    private let returnedMBID: UUID
    private let error: (any Error & Sendable)?
    private let waitsForResume: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    init(
        returnedMSID: UUID? = nil,
        returnedMBID: UUID = UUID(),
        error: (any Error & Sendable)? = nil,
        waitsForResume: Bool = false
    ) {
        self.returnedMSID = returnedMSID
        self.returnedMBID = returnedMBID
        self.error = error
        self.waitsForResume = waitsForResume
    }

    func getManualMapping(msid: UUID) async throws -> ManualMappingIdentity {
        callCount += 1
        if waitsForResume {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        if let error { throw error }
        return ManualMappingIdentity(msid: returnedMSID ?? msid, mbid: returnedMBID)
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
