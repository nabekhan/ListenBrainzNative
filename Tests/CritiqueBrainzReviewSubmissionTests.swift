import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class CritiqueBrainzReviewSubmissionTests: XCTestCase {
    func testProviderMapsDefiniteResponsesAndNeverRetries() async {
        let cases: [(any Error & Sendable, CritiqueBrainzReviewSubmissionError)] = [
            (LBError.invalidAuth, .accountOrServiceUnavailable),
            (LBError.noToken, .accountOrServiceUnavailable),
            (LBError.forbidden, .accountOrServiceUnavailable),
            (LBError.invalidJSON, .duplicateOrRejected),
            (LBError.badRequest, .duplicateOrRejected),
            (LBError.invalidParam, .duplicateOrRejected),
            (LBError.notFound, .duplicateOrRejected),
            (LBError.rateLimited(resetIn: 7), .rateLimited(7)),
        ]

        for (source, expected) in cases {
            let transport = ReviewTransportSpy(error: source)
            let provider = ListenBrainzCritiqueBrainzReviewSubmissionProvider(
                gate: RequestGate(minimumInterval: .zero),
                transport: { try await transport.submit($0) }
            )

            await assertSubmissionError(expected) {
                try await provider.submit(self.fixtureDraft())
            }
            let callCount = await transport.callCount()
            XCTAssertEqual(callCount, 1)
        }
    }

    func testProviderTreatsUnknownAndMalformedSuccessFailuresAsIndeterminate() async {
        for source in [LBError.invalidResponse, LBError.unknownError, LBError.noContent] {
            let transport = ReviewTransportSpy(error: source)
            let provider = ListenBrainzCritiqueBrainzReviewSubmissionProvider(
                gate: RequestGate(minimumInterval: .zero),
                transport: { try await transport.submit($0) }
            )

            await assertSubmissionError(.outcomeUnknown) {
                try await provider.submit(self.fixtureDraft())
            }
            let callCount = await transport.callCount()
            XCTAssertEqual(callCount, 1)
        }
    }

    func testProviderCancellationBeforeTransportDoesNotDispatch() async throws {
        let blocker = ReviewGateBlocker()
        let gate = RequestGate(minimumInterval: .zero)
        let blockingTask = Task { try await gate.perform { await blocker.run() } }
        while !(await blocker.hasStarted()) { await Task.yield() }

        let transport = ReviewTransportSpy()
        let provider = ListenBrainzCritiqueBrainzReviewSubmissionProvider(
            gate: gate,
            transport: { try await transport.submit($0) }
        )
        let task = Task { try await provider.submit(self.fixtureDraft()) }
        while await gate.queuedRequestCountForTesting() == 0 { await Task.yield() }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // The request never entered transport.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await blocker.release()
        _ = try await blockingTask.value
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testProviderCancellationAfterTransportIsIndeterminate() async {
        let transport = ReviewCancellationTransport()
        let provider = ListenBrainzCritiqueBrainzReviewSubmissionProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: { try await transport.submit($0) }
        )
        let task = Task { try await provider.submit(self.fixtureDraft()) }
        while !(await transport.hasStarted()) { await Task.yield() }

        task.cancel()
        await assertSubmissionError(.outcomeUnknown) { try await task.value }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testCurrentSessionExplicitRetryUsesFrozenDraft() async {
        let provider = ReviewProviderSpy(outcomes: [
            .failure(.outcomeUnknown),
            .success(UUID()),
        ])
        let model = configuredModel(provider: provider)

        await model.publish()
        XCTAssertEqual(model.state, .outcomeUnknown)
        let originalText = model.text
        model.text = "This edit must not replace the exact frozen review payload."
        await model.publish(retryingIndeterminate: true)

        guard case .published = model.state else {
            return XCTFail("Expected the explicitly retried review to publish")
        }
        let drafts = await provider.submittedDrafts()
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.last?.text, originalText)
    }

    func testDurableScopeBarrierSurvivesRelaunchAndChangedDraftCannotBypassIt() async {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }

        let firstProvider = ReviewProviderSpy(outcomes: [.failure(.outcomeUnknown)])
        let first = configuredModel(
            provider: firstProvider,
            journal: .init(fileURL: location.file)
        )
        await first.publish()
        XCTAssertEqual(first.state, .outcomeUnknown)

        let secondProvider = ReviewProviderSpy(outcomes: [.success(UUID())])
        let second = configuredModel(
            provider: secondProvider,
            journal: .init(fileURL: location.file)
        )
        XCTAssertEqual(second.state, .priorAttemptNeedsReview)
        second.text = "A different valid review must not bypass the entity barrier."
        await second.publish()
        XCTAssertEqual(second.state, .priorAttemptNeedsReview)
        let callsBeforeRetry = await secondProvider.callCount()
        XCTAssertEqual(callsBeforeRetry, 0)

        await second.publish(retryingIndeterminate: true)
        let callsAfterBlockedRetry = await secondProvider.callCount()
        XCTAssertEqual(callsAfterBlockedRetry, 0)

        second.clearPriorAttemptAfterChecking()
        XCTAssertEqual(second.state, .editing)
        await second.publish()

        guard case .published = second.state else {
            return XCTFail("Expected a new review after the scoped barrier was explicitly cleared")
        }
        let callsAfterClear = await secondProvider.callCount()
        XCTAssertEqual(callsAfterClear, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path()))
    }

    func testScopeBarrierBlocksAChangedDraftEvenWithoutRelaunch() async {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let draft = fixtureDraft()
        let journal = CritiqueBrainzReviewJournal(fileURL: location.file)
        let scope = CritiqueBrainzReviewJournal.scopeFingerprint(
            account: draft.account,
            entity: draft.entity
        )
        XCTAssertEqual(
            journal.reserve(
                scopeFingerprint: scope,
                payloadFingerprint: CritiqueBrainzReviewJournal.payloadFingerprint(draft),
                retryingIndeterminate: false
            ),
            .reserved
        )
        journal.release(scopeFingerprint: scope)

        var changed = draft
        changed = .init(
            account: changed.account,
            entity: changed.entity,
            entityName: changed.entityName,
            text: "A materially changed review that is still valid for publishing.",
            language: changed.language,
            rating: changed.rating
        )
        XCTAssertEqual(
            journal.reserve(
                scopeFingerprint: scope,
                payloadFingerprint: CritiqueBrainzReviewJournal.payloadFingerprint(changed),
                retryingIndeterminate: false
            ),
            .indeterminate
        )
        XCTAssertEqual(
            journal.reserve(
                scopeFingerprint: scope,
                payloadFingerprint: CritiqueBrainzReviewJournal.payloadFingerprint(changed),
                retryingIndeterminate: true
            ),
            .indeterminate
        )
    }

    func testDuplicatePublishTapsDispatchOnlyOnce() async {
        let provider = ReviewProviderSpy(
            outcomes: [.success(UUID())],
            delay: .milliseconds(40)
        )
        let model = configuredModel(provider: provider)

        async let first: Void = model.publish()
        await Task.yield()
        async let second: Void = model.publish()
        _ = await (first, second)

        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
        guard case .published = model.state else {
            return XCTFail("Expected one confirmed publication")
        }
    }

    func testPublishedReviewCannotBeSentAgain() async {
        let provider = ReviewProviderSpy(outcomes: [.success(UUID()), .success(UUID())])
        let model = configuredModel(provider: provider)

        await model.publish()
        await model.publish()
        await model.publish(retryingIndeterminate: true)

        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(model.showsPublishAction)
    }

    func testDefiniteFailureClearsBarrierAndAllowsRetry() async {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let provider = ReviewProviderSpy(outcomes: [
            .failure(.duplicateOrRejected),
            .success(UUID()),
        ])
        let model = configuredModel(
            provider: provider,
            journal: .init(fileURL: location.file)
        )

        await model.publish()
        guard case .failed = model.state else {
            return XCTFail("Expected a definite failure")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path()))

        await model.publish()
        guard case .published = model.state else {
            return XCTFail("Expected retry after a definite failure")
        }
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testCancellationBeforeDispatchReturnsToEditingAndClearsBarrier() async {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let provider = ReviewProviderSpy(outcomes: [.cancellation])
        let model = configuredModel(
            provider: provider,
            journal: .init(fileURL: location.file)
        )

        await model.publish()

        XCTAssertEqual(model.state, .editing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path()))
    }

    func testJournalPersistsOnlyOpaqueDataAndRejectsCorruption() throws {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let draft = fixtureDraft()
        let scopeFingerprint = CritiqueBrainzReviewJournal.scopeFingerprint(
            account: draft.account,
            entity: draft.entity
        )
        let payloadFingerprint = CritiqueBrainzReviewJournal.payloadFingerprint(draft)
        let journal = CritiqueBrainzReviewJournal(fileURL: location.file)

        XCTAssertEqual(
            journal.reserve(
                scopeFingerprint: scopeFingerprint,
                payloadFingerprint: payloadFingerprint,
                retryingIndeterminate: false
            ),
            .reserved
        )
        journal.release(scopeFingerprint: scopeFingerprint)
        let persisted = try String(contentsOf: location.file, encoding: .utf8)
        XCTAssertFalse(persisted.contains(draft.account.username))
        XCTAssertFalse(persisted.contains(draft.account.token))
        XCTAssertFalse(persisted.contains(draft.entityName))
        XCTAssertFalse(persisted.contains(draft.text))
        XCTAssertTrue(
            CritiqueBrainzReviewJournal(fileURL: location.file)
                .requiresReview(scopeFingerprint: scopeFingerprint)
        )

        try Data("not json".utf8).write(to: location.file)
        XCTAssertTrue(CritiqueBrainzReviewJournal(fileURL: location.file).requiresRecovery)
    }

    func testDuplicateJournalRecordsFailClosed() throws {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        let draft = fixtureDraft()
        let scopeFingerprint = CritiqueBrainzReviewJournal.scopeFingerprint(
            account: draft.account,
            entity: draft.entity
        )
        let record = CritiqueBrainzReviewJournalRecord(
            scopeFingerprint: scopeFingerprint,
            payloadFingerprint: CritiqueBrainzReviewJournal.payloadFingerprint(draft),
            attemptedAt: .now
        )
        try JSONEncoder().encode([record, record]).write(to: location.file)

        XCTAssertTrue(CritiqueBrainzReviewJournal(fileURL: location.file).requiresRecovery)
    }

    func testUnwritableJournalPreventsTransportAndCannotPretendToReset() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CritiqueBrainzReviewTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journal = CritiqueBrainzReviewJournal(fileURL: root)
        let provider = ReviewProviderSpy(outcomes: [.success(UUID())])
        let model = configuredModel(provider: provider, journal: journal)

        await model.publish()

        XCTAssertEqual(model.state, .safetyRecovery)
        XCTAssertTrue(journal.requiresRecovery)
        XCTAssertFalse(journal.resetRecovery())
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testCorruptJournalStartsPausedUntilExplicitReset() throws {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: location.file)
        let journal = CritiqueBrainzReviewJournal(fileURL: location.file)
        let model = configuredModel(provider: ReviewProviderSpy(), journal: journal)

        XCTAssertEqual(model.state, .safetyRecovery)
        XCTAssertTrue(model.isLocked)
        model.resetAllSafetyRecordsAfterChecking()
        XCTAssertEqual(model.state, .editing)
        XCTAssertFalse(journal.requiresRecovery)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path()))
    }

    func testClearingCheckedEntityKeepsOtherReplayBarriers() throws {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let first = fixtureDraft()
        let second = CritiqueBrainzReviewDraft(
            account: first.account,
            entity: .init(kind: .recording, mbid: UUID()),
            entityName: "Another item",
            text: "Another thoughtful review with enough detail to publish.",
            language: "en",
            rating: nil
        )
        let journal = CritiqueBrainzReviewJournal(fileURL: location.file)
        let firstScope = CritiqueBrainzReviewJournal.scopeFingerprint(
            account: first.account,
            entity: first.entity
        )
        let secondScope = CritiqueBrainzReviewJournal.scopeFingerprint(
            account: second.account,
            entity: second.entity
        )

        for (scope, draft) in [(firstScope, first), (secondScope, second)] {
            XCTAssertEqual(
                journal.reserve(
                    scopeFingerprint: scope,
                    payloadFingerprint: CritiqueBrainzReviewJournal.payloadFingerprint(draft),
                    retryingIndeterminate: false
                ),
                .reserved
            )
            journal.release(scopeFingerprint: scope)
        }

        XCTAssertTrue(journal.clearAfterReview(scopeFingerprint: firstScope))
        let relaunched = CritiqueBrainzReviewJournal(fileURL: location.file)
        XCTAssertFalse(relaunched.requiresReview(scopeFingerprint: firstScope))
        XCTAssertTrue(relaunched.requiresReview(scopeFingerprint: secondScope))
    }

    func testOversizedJournalFailsClosedWithoutReadingRecords() throws {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x78, count: 256 * 1_024 + 1).write(to: location.file)

        XCTAssertTrue(CritiqueBrainzReviewJournal(fileURL: location.file).requiresRecovery)
    }

    func testGlobalRecoveryCannotResetWhileAnotherAttemptIsClaimed() {
        let location = temporaryJournalLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let first = fixtureDraft()
        let second = CritiqueBrainzReviewDraft(
            account: first.account,
            entity: .init(kind: .recording, mbid: UUID()),
            entityName: "Another item",
            text: "Another thoughtful review with enough detail to publish.",
            language: "en",
            rating: nil
        )
        let journal = CritiqueBrainzReviewJournal(
            fileURL: location.file,
            recordLimit: 1
        )
        let firstScope = CritiqueBrainzReviewJournal.scopeFingerprint(
            account: first.account,
            entity: first.entity
        )
        let secondScope = CritiqueBrainzReviewJournal.scopeFingerprint(
            account: second.account,
            entity: second.entity
        )

        XCTAssertEqual(
            journal.reserve(
                scopeFingerprint: firstScope,
                payloadFingerprint: CritiqueBrainzReviewJournal.payloadFingerprint(first),
                retryingIndeterminate: false
            ),
            .reserved
        )
        XCTAssertEqual(
            journal.reserve(
                scopeFingerprint: secondScope,
                payloadFingerprint: CritiqueBrainzReviewJournal.payloadFingerprint(second),
                retryingIndeterminate: false
            ),
            .unavailable
        )
        XCTAssertTrue(journal.requiresRecovery)
        XCTAssertFalse(journal.resetRecovery())
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.file.path()))

        journal.release(scopeFingerprint: firstScope)
        XCTAssertTrue(journal.resetRecovery())
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path()))
    }

    func testLanguageValidationUsesOnlyISOAlpha2Codes() {
        let model = configuredModel(provider: ReviewProviderSpy())
        XCTAssertTrue(CritiqueBrainzReviewComposerModel.supportedLanguageCodes.contains("en"))

        model.language = "zz"
        XCTAssertFalse(model.isValid)
        model.language = "en-CA"
        XCTAssertFalse(model.isValid)
        model.language = "fr"
        XCTAssertTrue(model.isValid)
    }

    func testComposerRejectsPathologicalCombiningMarkPayloads() {
        let model = configuredModel(provider: ReviewProviderSpy())
        model.text = "a" + String(repeating: "\u{0301}", count: 100_000)

        XCTAssertLessThan(model.trimmedText.count, model.trimmedText.unicodeScalars.count)
        XCTAssertFalse(model.isValid)
    }

    func testComposerCountAndRatingCopyUsesEnglishPlurals() {
        let locale = Locale(identifier: "en")
        XCTAssertEqual(String(localized: "\(1) characters", locale: locale), "1 character")
        XCTAssertEqual(String(localized: "\(2) characters", locale: locale), "2 characters")
        XCTAssertEqual(
            String(localized: "\(1) more characters needed", locale: locale),
            "1 more character needed"
        )
        XCTAssertEqual(String(localized: "\(1) stars", locale: locale), "1 star")
        XCTAssertEqual(String(localized: "\(5) stars", locale: locale), "5 stars")
    }

    private func configuredModel(
        provider: some CritiqueBrainzReviewSubmitting,
        journal: CritiqueBrainzReviewJournal = .init()
    ) -> CritiqueBrainzReviewComposerModel {
        let model = CritiqueBrainzReviewComposerModel(
            account: .init(username: "listener", token: "fixture-token"),
            entity: .init(
                kind: .artist,
                mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
            ),
            entityName: "Example Artist",
            provider: provider,
            journal: journal
        )
        model.text = "A thoughtful review with enough detail to publish safely."
        model.language = "en"
        model.rating = 4
        model.acknowledgedLicense = true
        return model
    }

    private func fixtureDraft() -> CritiqueBrainzReviewDraft {
        .init(
            account: .init(username: "listener", token: "fixture-token"),
            entity: .init(
                kind: .artist,
                mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
            ),
            entityName: "Example Artist",
            text: "A thoughtful review with enough detail to publish safely.",
            language: "en",
            rating: 4
        )
    }

    private func temporaryJournalLocation() -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CritiqueBrainzReviewTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        return (root, root.appending(path: "journal.json"))
    }

    private func assertSubmissionError(
        _ expected: CritiqueBrainzReviewSubmissionError,
        operation: () async throws -> UUID
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as CritiqueBrainzReviewSubmissionError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor ReviewTransportSpy {
    private let error: (any Error & Sendable)?
    private var drafts: [CritiqueBrainzReviewDraft] = []

    init(error: (any Error & Sendable)? = nil) {
        self.error = error
    }

    func submit(_ draft: CritiqueBrainzReviewDraft) async throws -> UUID {
        drafts.append(draft)
        if let error { throw error }
        return UUID()
    }

    func callCount() -> Int { drafts.count }
}

private actor ReviewCancellationTransport {
    private var started = false
    private var calls = 0

    func submit(_ draft: CritiqueBrainzReviewDraft) async throws -> UUID {
        _ = draft
        started = true
        calls += 1
        try await Task.sleep(for: .seconds(60))
        return UUID()
    }

    func hasStarted() -> Bool { started }
    func callCount() -> Int { calls }
}

private actor ReviewGateBlocker {
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

private enum ReviewProviderOutcome: Sendable {
    case success(UUID)
    case failure(CritiqueBrainzReviewSubmissionError)
    case cancellation
}

private actor ReviewProviderSpy: CritiqueBrainzReviewSubmitting {
    private var outcomes: [ReviewProviderOutcome]
    private let delay: Duration
    private var drafts: [CritiqueBrainzReviewDraft] = []

    init(
        outcomes: [ReviewProviderOutcome] = [],
        delay: Duration = .zero
    ) {
        self.outcomes = outcomes
        self.delay = delay
    }

    func submit(_ payload: CritiqueBrainzReviewDraft) async throws -> UUID {
        drafts.append(payload)
        if delay > .zero { try await Task.sleep(for: delay) }
        guard !outcomes.isEmpty else { return UUID() }
        switch outcomes.removeFirst() {
        case let .success(id): return id
        case let .failure(error): throw error
        case .cancellation: throw CancellationError()
        }
    }

    func callCount() -> Int { drafts.count }
    func submittedDrafts() -> [CritiqueBrainzReviewDraft] { drafts }
}
