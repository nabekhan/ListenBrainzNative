import Foundation
import ListenBrainzKit
import XCTest
@testable import Brainz

@MainActor
final class DoNotRecommendModelTests: XCTestCase {
    func testSavingPreferenceUsesRecordingMBIDAndShowsConfirmation() async {
        let provider = DoNotRecommendFixtureProvider()
        let model = makeModel(provider: provider)

        let succeeded = await model.savePreference()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.isExcluded, true)
        XCTAssertEqual(model.notice?.kind, .confirmation)
        XCTAssertEqual(model.notice?.message, "Preference saved to ListenBrainz.")
        let operations = await provider.operations
        XCTAssertEqual(operations, [.add(.recording, recordingMBID, nil)])
    }

    func testFailureRollsBackOptimisticPreference() async {
        let provider = DoNotRecommendFixtureProvider(mutationError: DoNotRecommendFixtureError.failed)
        let model = makeModel(provider: provider)

        let succeeded = await model.savePreference()

        XCTAssertFalse(succeeded)
        XCTAssertNil(model.isExcluded)
        XCTAssertEqual(model.notice?.kind, .error)
        XCTAssertEqual(model.notice?.message, "ListenBrainz couldn’t update this preference. Try again.")
        let operations = await provider.operations
        XCTAssertEqual(operations, [.add(.recording, recordingMBID, nil)])
    }

    func testCancelledMutationStillPublishesPotentialListChange() async throws {
        let provider = DoNotRecommendFixtureProvider(mutationError: CancellationError())
        let changes = RecommendationPreferenceChanges()
        let model = DoNotRecommendModel(
            account: Account(username: "listener", token: "token"),
            recordingMBID: recordingMBID,
            provider: provider,
            preferenceCache: EntityDetailCache(),
            changes: changes
        )

        let succeeded = await model.savePreference()

        XCTAssertFalse(succeeded)
        XCTAssertNil(model.isExcluded)
        XCTAssertNil(model.notice)
        XCTAssertNotNil(changes.event(for: "listener"))
    }

    func testRemovingPreferenceShowsInverseActionState() async {
        let provider = DoNotRecommendFixtureProvider()
        let model = makeModel(provider: provider)

        _ = await model.savePreference()
        let succeeded = await model.removePreference()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.isExcluded, false)
        XCTAssertEqual(model.notice?.message, "Saved preference removed.")
        let operations = await provider.operations
        XCTAssertEqual(operations, [.add(.recording, recordingMBID, nil), .remove(.recording, recordingMBID)])
    }

    func testMissingMusicBrainzIDDoesNotCallProvider() async {
        let provider = DoNotRecommendFixtureProvider()
        let model = DoNotRecommendModel(
            account: Account(username: "listener", token: "token"),
            recordingMBID: nil,
            provider: provider,
            preferenceCache: EntityDetailCache(),
            changes: RecommendationPreferenceChanges()
        )

        let succeeded = await model.savePreference()

        XCTAssertFalse(succeeded)
        let operations = await provider.operations
        XCTAssertEqual(operations, [])
        XCTAssertEqual(model.notice?.message, "This recording needs a MusicBrainz ID before you can save this preference.")
    }

    func testProviderUsesPacedTransportAndRejectsNonOKStatus() async throws {
        let transport = DoNotRecommendTransportSpy(status: "ok")
        let provider = ListenBrainzDoNotRecommendProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        try await provider.addRecording(recordingMBID: recordingMBID)
        try await provider.removeRecording(recordingMBID: recordingMBID)

        let addCall = await transport.addCall
        let removeCall = await transport.removeCall
        XCTAssertEqual(addCall?.entity, .recording)
        XCTAssertEqual(addCall?.entityMBID, recordingMBID)
        XCTAssertEqual(removeCall?.entity, .recording)
        XCTAssertEqual(removeCall?.entityMBID, recordingMBID)

        let rejected = ListenBrainzDoNotRecommendProvider(
            transport: DoNotRecommendTransportSpy(status: "not-ok"),
            gate: RequestGate(minimumInterval: .zero)
        )
        do {
            try await rejected.addRecording(recordingMBID: recordingMBID)
            XCTFail("A non-ok response should be rejected")
        } catch {
            XCTAssertEqual(error as? DoNotRecommendProviderError, .invalidMutationResponse)
        }

        let cancelled = ListenBrainzDoNotRecommendProvider(
            transport: DoNotRecommendTransportSpy(status: "ok", cancelsMutation: true),
            gate: RequestGate(minimumInterval: .zero)
        )
        do {
            try await cancelled.addRecording(recordingMBID: recordingMBID)
            XCTFail("A cancelled transport should remain cancellation")
        } catch is CancellationError {
            // Expected: cancellation should not become a user-facing failure.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testProviderBoundsPublicPageRequestBeforeTransport() async throws {
        let transport = DoNotRecommendTransportSpy(status: "ok")
        let provider = ListenBrainzDoNotRecommendProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )

        let page = try await provider.entries(username: "listener", offset: -4, count: 1_000)

        XCTAssertEqual(page.offset, 0)
        XCTAssertEqual(page.serverCount, 0)
        let entriesCall = await transport.entriesCall
        XCTAssertEqual(entriesCall, .init(username: "listener", offset: 0, count: 25))
    }

    private func makeModel(provider: DoNotRecommendFixtureProvider) -> DoNotRecommendModel {
        DoNotRecommendModel(
            account: Account(username: "listener", token: "token"),
            recordingMBID: recordingMBID,
            provider: provider,
            preferenceCache: EntityDetailCache(),
            changes: RecommendationPreferenceChanges()
        )
    }
}

private let recordingMBID = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!

private actor DoNotRecommendFixtureProvider: DoNotRecommendProviding {
    enum Operation: Equatable, Sendable {
        case add(RecommendationPreferenceEntity, UUID, Date?)
        case remove(RecommendationPreferenceEntity, UUID)
    }

    let mutationError: Error?
    private(set) var operations: [Operation] = []

    init(mutationError: Error? = nil) { self.mutationError = mutationError }

    func entries(username: String, offset: Int, count: Int) async throws -> RecommendationPreferencePage {
        .init(username: username, items: [], serverCount: 0, offset: offset, totalCount: 0)
    }

    func add(entity: RecommendationPreferenceEntity, entityMBID: UUID, until: Date?) async throws {
        operations.append(.add(entity, entityMBID, until))
        if let mutationError { throw mutationError }
    }

    func remove(entity: RecommendationPreferenceEntity, entityMBID: UUID) async throws {
        operations.append(.remove(entity, entityMBID))
        if let mutationError { throw mutationError }
    }
}

private actor DoNotRecommendTransportSpy: DoNotRecommendTransport {
    struct EntriesCall: Equatable, Sendable {
        let username: String
        let offset: Int
        let count: Int
    }

    struct Call: Equatable, Sendable {
        let entity: LBDoNotRecommendEntity
        let entityMBID: UUID
    }

    let status: String
    let cancelsMutation: Bool
    private(set) var addCall: Call?
    private(set) var removeCall: Call?
    private(set) var entriesCall: EntriesCall?

    init(status: String, cancelsMutation: Bool = false) {
        self.status = status
        self.cancelsMutation = cancelsMutation
    }

    func entries(username: String, offset: Int, count: Int) async throws -> LBDoNotRecommendPage {
        entriesCall = .init(username: username, offset: offset, count: count)
        return .init(entries: [], totalCount: 0, count: 0, offset: offset, userID: username)
    }

    func add(entity: LBDoNotRecommendEntity, entityMBID: UUID, until: Date?) async throws -> LBDoNotRecommendStatus {
        addCall = .init(entity: entity, entityMBID: entityMBID)
        if cancelsMutation { throw URLError(.cancelled) }
        return .init(status: status)
    }

    func remove(entity: LBDoNotRecommendEntity, entityMBID: UUID) async throws -> LBDoNotRecommendStatus {
        removeCall = .init(entity: entity, entityMBID: entityMBID)
        return .init(status: status)
    }
}

private enum DoNotRecommendFixtureError: Error { case failed }
