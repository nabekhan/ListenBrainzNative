import Foundation
import XCTest
@testable import Brainz

@MainActor
final class PinsModelTests: XCTestCase {
    func testLoadKeepsCurrentSeparateFromHistoryAndMarksMatchingRow() async {
        let provider = PinsFixtureProvider()
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)

        await model.load()
        await model.loadHistory()

        XCTAssertEqual(model.currentPin?.rowID, 2)
        XCTAssertEqual(model.history.count, 2)
        XCTAssertEqual(model.history.first(where: { $0.rowID == 2 })?.isCurrent, true)
        XCTAssertEqual(model.history.first(where: { $0.rowID == 1 })?.isCurrent, false)
        XCTAssertEqual(model.totalCount, 3)
    }

    func testLoadDoesNotEagerlyRequestHistory() async {
        let provider = PinsFixtureProvider()
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)

        await model.load()

        let currentRequests = await provider.currentRequestCount
        let initialHistoryRequests = await provider.historyRequestCount
        XCTAssertEqual(currentRequests, 1)
        XCTAssertEqual(initialHistoryRequests, 0)
        XCTAssertTrue(model.history.isEmpty)

        await model.loadHistory()

        let loadedHistoryRequests = await provider.historyRequestCount
        XCTAssertEqual(loadedHistoryRequests, 1)
        XCTAssertEqual(model.history.count, 2)
    }

    func testRepeatedCurrentLoadMakesOneRequest() async {
        let provider = PinsFixtureProvider()
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)

        await model.load()
        await model.load()

        let currentRequests = await provider.currentRequestCount
        let historyRequests = await provider.historyRequestCount
        XCTAssertEqual(currentRequests, 1)
        XCTAssertEqual(historyRequests, 0)
    }

    func testCurrentOnlyRefreshDoesNotRequestHistory() async {
        let provider = PinsFixtureProvider()
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)

        await model.load()
        await model.loadHistory()
        await model.refreshCurrent()

        let currentRequests = await provider.currentRequestCount
        let historyRequests = await provider.historyRequestCount
        XCTAssertEqual(currentRequests, 2)
        XCTAssertEqual(historyRequests, 1)
    }

    func testInitialCurrentFailureUsesInlineStateWithoutGlobalAlert() async {
        let provider = PinsFixtureProvider(failCurrent: true)
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)

        await model.load()

        XCTAssertEqual(model.phase, .failed("Fixture failure"))
        XCTAssertNil(model.actionError)
        let historyRequests = await provider.historyRequestCount
        XCTAssertEqual(historyRequests, 0)
    }

    func testUnpinOptimisticallyClearsThenRestoresOnFailure() async {
        let provider = PinsFixtureProvider(failUnpin: true)
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)
        await model.load()
        await model.loadHistory()

        await model.unpin()

        XCTAssertEqual(model.currentPin?.rowID, 2)
        XCTAssertEqual(model.history.first(where: { $0.rowID == 2 })?.isCurrent, true)
        XCTAssertNotNil(model.actionError)
    }

    func testUpdateAndDeleteRollBackWhenServerRejects() async {
        let provider = PinsFixtureProvider(failUpdate: true, failDelete: true)
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)
        await model.load()
        await model.loadHistory()
        let pin = try! XCTUnwrap(model.history.first)

        await model.updateBlurb(for: pin, to: "Changed")
        XCTAssertEqual(model.history.first?.blurb, pin.blurb)

        await model.delete(pin)
        XCTAssertTrue(model.history.contains(where: { $0.rowID == pin.rowID }))
    }

    func testMutationDoesNotStartDuringAnInFlightRefresh() async {
        let provider = PinsFixtureProvider(delayRefreshCurrent: true)
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)
        await model.load()

        let refresh = Task { await model.refresh() }
        while await provider.currentRequestCount < 2 { await Task.yield() }

        await model.unpin()

        let unpinRequests = await provider.unpinRequestCount
        XCTAssertEqual(unpinRequests, 0)
        XCTAssertEqual(model.currentPin?.rowID, 2)
        await refresh.value
    }

    func testMutationDoesNotStartDuringInFlightHistoryPagination() async {
        let provider = PinsFixtureProvider(delayLoadMore: true)
        let model = PinsModel(account: .init(username: "fixture-pins", token: "token"), provider: provider)
        await model.load()
        await model.loadHistory()
        let pin = try! XCTUnwrap(model.history.first)

        let pagination = Task { await model.loadMore() }
        while await provider.historyRequestCount < 2 { await Task.yield() }

        await model.delete(pin)

        let deleteRequests = await provider.deleteRequestCount
        XCTAssertEqual(deleteRequests, 0)
        XCTAssertTrue(model.history.contains(where: { $0.rowID == pin.rowID }))
        await pagination.value
    }
}

private actor PinsFixtureProvider: PinProviding {
    private let failCurrent: Bool
    private let failUnpin: Bool
    private let failUpdate: Bool
    private let failDelete: Bool
    private let delayRefreshCurrent: Bool
    private let delayLoadMore: Bool
    private let current: PinnedRecording
    private let history: [PinnedRecording]
    private(set) var currentRequestCount = 0
    private(set) var historyRequestCount = 0
    private(set) var unpinRequestCount = 0
    private(set) var deleteRequestCount = 0

    init(
        failCurrent: Bool = false,
        failUnpin: Bool = false,
        failUpdate: Bool = false,
        failDelete: Bool = false,
        delayRefreshCurrent: Bool = false,
        delayLoadMore: Bool = false
    ) {
        self.failCurrent = failCurrent
        self.failUnpin = failUnpin
        self.failUpdate = failUpdate
        self.failDelete = failDelete
        self.delayRefreshCurrent = delayRefreshCurrent
        self.delayLoadMore = delayLoadMore
        let recording = Recording(identity: .init(mbid: UUID(), msid: UUID()), title: "Pinned track", artistName: "Pinned artist", artistMBIDs: [], releaseTitle: nil, releaseMBID: nil, releaseGroupMBID: nil, artworkReleaseMBID: nil, durationMilliseconds: nil, source: nil)
        self.current = PinnedRecording(rowID: 2, created: .now, pinnedUntil: .now.addingTimeInterval(60), blurb: "Current note", username: "fixture-pins", recording: recording, isCurrent: true)
        self.history = [
            PinnedRecording(rowID: 2, created: .now, pinnedUntil: .now.addingTimeInterval(60), blurb: "Current note", username: "fixture-pins", recording: recording, isCurrent: false),
            PinnedRecording(rowID: 1, created: .now.addingTimeInterval(-100), pinnedUntil: nil, blurb: nil, username: "fixture-pins", recording: recording, isCurrent: false)
        ]
    }

    func currentPin(username: String) async throws -> PinnedRecording? {
        currentRequestCount += 1
        if failCurrent { throw FixtureError.failed }
        if delayRefreshCurrent, currentRequestCount > 1 {
            try await ContinuousClock().sleep(for: .milliseconds(100))
        }
        return current
    }
    func pin(_ recording: Recording, blurb: String?) async throws -> PinnedRecording { current }
    func pinHistory(username: String, count: Int, offset: Int) async throws -> (pins: [PinnedRecording], totalCount: Int) {
        historyRequestCount += 1
        if delayLoadMore, historyRequestCount > 1 {
            try await ContinuousClock().sleep(for: .milliseconds(100))
        }
        return (Array(history.dropFirst(offset).prefix(count)), 3)
    }
    func unpin() async throws {
        unpinRequestCount += 1
        if failUnpin { throw FixtureError.failed }
    }
    func updatePinBlurb(rowID: Int, blurb: String) async throws { if failUpdate { throw FixtureError.failed } }
    func deletePin(rowID: Int) async throws {
        deleteRequestCount += 1
        if failDelete { throw FixtureError.failed }
    }
}

private enum FixtureError: LocalizedError { case failed; var errorDescription: String? { "Fixture failure" } }
