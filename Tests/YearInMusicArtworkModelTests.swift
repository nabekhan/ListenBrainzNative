import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class YearInMusicArtworkModelTests: XCTestCase {
    func testConstructionIsInertAndGenerateMakesOneCall() async {
        let provider = ArtworkModelFixtureProvider(results: [.success("<svg/>")])
        let model = YearInMusicArtworkModel(
            options: .init(username: "listener", year: 2025),
            provider: provider
        )

        XCTAssertEqual(model.phase, .idle)
        let callsBeforeGeneration = await provider.callCount()
        XCTAssertEqual(callsBeforeGeneration, 0)
        await model.generate()
        await model.generate()

        guard case let .ready(artwork) = model.phase else {
            return XCTFail("Expected generated artwork")
        }
        XCTAssertEqual(artwork.svg, "<svg/>")
        let callsAfterGeneration = await provider.callCount()
        XCTAssertEqual(callsAfterGeneration, 1)
    }

    func testUnavailableRetryAndCancellationAreSafe() async throws {
        let unavailable = ArtworkModelFixtureProvider(results: [.unavailable, .success("<svg/>")])
        let model = YearInMusicArtworkModel(
            options: .init(username: "listener", year: 2025),
            provider: unavailable
        )
        await model.generate()
        XCTAssertEqual(model.phase, .unavailable)
        await model.retry()
        guard case .ready = model.phase else { return XCTFail("Retry should recover") }
        let retryCallCount = await unavailable.callCount()
        XCTAssertEqual(retryCallCount, 2)

        let delayed = ArtworkModelFixtureProvider(results: [.success("<svg/>")], delay: .milliseconds(80))
        let cancellable = YearInMusicArtworkModel(
            options: .init(username: "listener", year: 2025),
            provider: delayed
        )
        let task = Task { await cancellable.generate() }
        while await delayed.callCount() == 0 { try await ContinuousClock().sleep(for: .milliseconds(1)) }
        cancellable.cancel()
        await task.value
        XCTAssertEqual(cancellable.phase, .idle)
        let cancellationCount = await delayed.cancellationCount()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testDuplicateTapDoesNotBeginAnotherRequest() async throws {
        let provider = ArtworkModelFixtureProvider(results: [.success("<svg/>")], delay: .milliseconds(35))
        let model = YearInMusicArtworkModel(
            options: .init(username: "listener", year: 2025),
            provider: provider
        )
        async let first: Void = model.generate()
        async let second: Void = model.generate()
        _ = await (first, second)
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }
}

private actor ArtworkModelFixtureProvider: YearInMusicArtworkProviding {
    enum Result: Sendable { case success(String), unavailable }

    private let results: [Result]
    private let delay: Duration
    private var calls = 0
    private var cancellations = 0

    init(results: [Result], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func artwork(for options: YearInMusicArtworkOptions) async throws -> YearInMusicArtwork? {
        let index = calls
        calls += 1
        if delay > .zero {
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch is CancellationError {
                cancellations += 1
                throw CancellationError()
            }
        }
        switch results.indices.contains(index) ? results[index] : results.last ?? .unavailable {
        case let .success(svg):
            return YearInMusicArtwork(options: options, source: LBYearInMusicArtwork(svg: svg))
        case .unavailable:
            return nil
        }
    }

    func callCount() -> Int { calls }

    func cancellationCount() -> Int { cancellations }
}
