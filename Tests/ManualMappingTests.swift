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
