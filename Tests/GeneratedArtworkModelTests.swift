import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class GeneratedArtworkModelTests: XCTestCase {
    func testConstructionIsInertAndGenerateMakesOneCall() async {
        let provider = GeneratedArtworkModelFixture(
            results: [.success("<svg/>")]
        )
        let request = GeneratedArtworkRequest.statistics(
            username: "listener",
            range: .thisMonth
        )
        let model = GeneratedArtworkModel(
            request: request,
            provider: provider
        )

        XCTAssertEqual(model.phase, .idle)
        let callsBeforeGeneration = await provider.callCount()
        XCTAssertEqual(callsBeforeGeneration, 0)

        await model.generate()
        await model.generate()

        XCTAssertEqual(
            model.phase,
            .ready(.init(request: request, svg: "<svg/>"))
        )
        let callsAfterGeneration = await provider.callCount()
        XCTAssertEqual(callsAfterGeneration, 1)
    }

    func testUnavailableCanRetryAndDuplicateGenerationDoesNotFanOut() async {
        let provider = GeneratedArtworkModelFixture(
            results: [.unavailable, .success("<svg id=\"ready\"/>")],
            delay: .milliseconds(30)
        )
        let model = GeneratedArtworkModel(
            request: .artist(mbid: UUID()),
            provider: provider
        )

        async let first: Void = model.generate()
        async let duplicate: Void = model.generate()
        _ = await (first, duplicate)
        XCTAssertEqual(model.phase, .unavailable)
        let callsAfterUnavailable = await provider.callCount()
        XCTAssertEqual(callsAfterUnavailable, 1)

        await model.retry()
        guard case let .ready(document) = model.phase else {
            return XCTFail("Retry should recover from an unavailable response")
        }
        XCTAssertEqual(document.svg, "<svg id=\"ready\"/>")
        let callsAfterRetry = await provider.callCount()
        XCTAssertEqual(callsAfterRetry, 2)
    }

    func testCancelStopsTheActiveProviderTask() async throws {
        let provider = CancellableGeneratedArtworkProvider()
        let model = GeneratedArtworkModel(
            request: .artist(mbid: UUID()),
            provider: provider
        )
        let generation = Task { @MainActor in await model.generate() }
        try await waitForCondition { await provider.callCount() == 1 }

        model.cancel()

        try await waitForCondition {
            await provider.cancellationCount() == 1
        }
        await generation.value
        XCTAssertEqual(model.phase, .idle)
    }

    func testLateCompletionAfterCancelCannotReplaceIdleState() async throws {
        let provider = LateGeneratedArtworkProvider()
        let model = GeneratedArtworkModel(
            request: .artist(mbid: UUID()),
            provider: provider
        )
        let generation = Task { @MainActor in await model.generate() }
        try await waitForCondition { await provider.callCount() == 1 }

        model.cancel()
        XCTAssertEqual(model.phase, .idle)
        await provider.release()
        await generation.value

        XCTAssertEqual(model.phase, .idle)
    }

    func testPeriodMappingAndPlaylistLayoutsAreExact() {
        XCTAssertEqual(ListeningActivityPeriod.thisWeek.artRange, .thisWeek)
        XCTAssertEqual(ListeningActivityPeriod.thisMonth.artRange, .thisMonth)
        XCTAssertEqual(ListeningActivityPeriod.thisYear.artRange, .thisYear)
        XCTAssertEqual(ListeningActivityPeriod.lastWeek.artRange, .week)
        XCTAssertEqual(ListeningActivityPeriod.lastMonth.artRange, .month)
        XCTAssertEqual(ListeningActivityPeriod.lastYear.artRange, .year)
        XCTAssertEqual(ListeningActivityPeriod.allTime.artRange, .allTime)

        let id = UUID()
        XCTAssertEqual(
            playlistArtworkRequest(mbid: id, trackCount: 6),
            .playlist(mbid: id, dimension: 3, layout: .one)
        )
        XCTAssertEqual(
            playlistArtworkRequest(mbid: id, trackCount: 4),
            .playlist(mbid: id, dimension: 2, layout: .zero)
        )
        XCTAssertEqual(
            playlistArtworkRequest(mbid: id, trackCount: 1),
            .playlist(mbid: id, dimension: 1, layout: .zero)
        )
        XCTAssertNil(playlistArtworkRequest(mbid: id, trackCount: 0))
    }

    private func waitForCondition(
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else {
                XCTFail(
                    "Timed out waiting for asynchronous test state.",
                    file: file,
                    line: line
                )
                throw GeneratedArtworkTestError.timeout
            }
            try await clock.sleep(for: .milliseconds(1))
        }
    }
}

private enum GeneratedArtworkTestError: Error {
    case timeout
}

private actor GeneratedArtworkModelFixture: GeneratedArtworkProviding {
    enum Result: Sendable {
        case success(String)
        case unavailable
    }

    private let results: [Result]
    private let delay: Duration
    private var calls = 0

    init(results: [Result], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> GeneratedArtworkDocument? {
        let index = calls
        calls += 1
        if delay > .zero {
            try await ContinuousClock().sleep(for: delay)
        }
        switch results[min(index, results.count - 1)] {
        case let .success(svg):
            return GeneratedArtworkDocument(request: request, svg: svg)
        case .unavailable:
            return nil
        }
    }

    func callCount() -> Int { calls }
}

private actor CancellableGeneratedArtworkProvider: GeneratedArtworkProviding {
    private var calls = 0
    private var cancellations = 0

    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> GeneratedArtworkDocument? {
        calls += 1
        do {
            try await ContinuousClock().sleep(for: .seconds(30))
            return GeneratedArtworkDocument(request: request, svg: "<svg/>")
        } catch {
            cancellations += 1
            throw error
        }
    }

    func callCount() -> Int { calls }
    func cancellationCount() -> Int { cancellations }
}

private actor LateGeneratedArtworkProvider: GeneratedArtworkProviding {
    private var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> GeneratedArtworkDocument? {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
        return GeneratedArtworkDocument(request: request, svg: "<svg/>")
    }

    func callCount() -> Int { calls }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
