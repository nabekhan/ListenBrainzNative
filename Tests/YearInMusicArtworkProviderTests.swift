import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class YearInMusicArtworkProviderTests: XCTestCase {
    func testNormalizesCacheIdentityIncludingOptions() async throws {
        let transport = ArtworkFixtureTransport(svg: "<svg/>")
        let provider = ListenBrainzYearInMusicArtworkProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            cache: YearInMusicArtworkCache()
        )
        let first = YearInMusicArtworkOptions(username: " Listener ", year: 2025, variant: .overview, anonymous: false)
        let same = YearInMusicArtworkOptions(username: "listener", year: 2025, variant: .overview, anonymous: false)
        let otherOptions = YearInMusicArtworkOptions(username: "listener", year: 2025, variant: .tracks, anonymous: false)

        _ = try await provider.artwork(for: first)
        _ = try await provider.artwork(for: same)
        _ = try await provider.artwork(for: otherOptions)

        let callCount = await transport.callCount()
        let calls = await transport.calls()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(calls, [
            .init(username: "listener", year: 2025, variant: .overview, anonymous: false),
            .init(username: "listener", year: 2025, variant: .tracks, anonymous: false),
        ])
    }

    func testCacheDoesNotReuseArtworkAcrossCredentialScopes() async throws {
        let cache = YearInMusicArtworkCache()
        let firstTransport = ArtworkFixtureTransport(svg: "<svg id=\"first\"/>")
        let secondTransport = ArtworkFixtureTransport(svg: "<svg id=\"second\"/>")
        let gate = RequestGate(minimumInterval: .zero)
        let firstProvider = ListenBrainzYearInMusicArtworkProvider(
            transport: firstTransport,
            gate: gate,
            cache: cache,
            readScope: .authenticated(token: "artwork-fixture-a")
        )
        let secondProvider = ListenBrainzYearInMusicArtworkProvider(
            transport: secondTransport,
            gate: gate,
            cache: cache,
            readScope: .authenticated(token: "artwork-fixture-b")
        )
        let options = YearInMusicArtworkOptions(username: "listener", year: 2025)

        let first = try await firstProvider.artwork(for: options)
        let second = try await secondProvider.artwork(for: options)
        let firstCallCount = await firstTransport.callCount()
        let secondCallCount = await secondTransport.callCount()

        XCTAssertEqual(first?.svg, "<svg id=\"first\"/>")
        XCTAssertEqual(second?.svg, "<svg id=\"second\"/>")
        XCTAssertEqual(firstCallCount, 1)
        XCTAssertEqual(secondCallCount, 1)
    }

    func testDuplicateLoadsCoalesceAndUnavailableIsCached() async throws {
        let transport = ArtworkFixtureTransport(svg: nil, delay: .milliseconds(30))
        let provider = ListenBrainzYearInMusicArtworkProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            cache: YearInMusicArtworkCache()
        )
        let options = YearInMusicArtworkOptions(username: "listener", year: 2025)

        async let first = provider.artwork(for: options)
        async let second = provider.artwork(for: options)
        let results = try await [first, second]
        XCTAssertEqual(results, [nil, nil])
        _ = try await provider.artwork(for: options)
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testProviderMapsRateLimitAfterTheGatedTransportCall() async throws {
        let transport = ArtworkFixtureTransport(error: .rateLimited(resetIn: 2))
        let provider = ListenBrainzYearInMusicArtworkProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            cache: YearInMusicArtworkCache()
        )
        do {
            _ = try await provider.artwork(for: .init(username: "listener", year: 2025))
            XCTFail("Expected rate limit")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testCancellationBeforeGateDelayDoesNotReachTransport() async throws {
        let gate = RequestGate(minimumInterval: .zero)
        await gate.deferRequests(for: .seconds(5))
        let transport = ArtworkFixtureTransport(svg: "<svg/>")
        let provider = ListenBrainzYearInMusicArtworkProvider(
            transport: transport,
            gate: gate,
            cache: YearInMusicArtworkCache()
        )

        let task = Task {
            try await provider.artwork(for: .init(username: "listener", year: 2025))
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: the shared flight had no remaining waiters.
        }
        try await ContinuousClock().sleep(for: .milliseconds(30))
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 0)
    }
}

private actor ArtworkFixtureTransport: YearInMusicArtworkTransport {
    struct Call: Equatable {
        let username: String
        let year: Int
        let variant: LBYearInMusicArtVariant
        let anonymous: Bool?
    }

    private let svg: String?
    private let delay: Duration
    private let error: LBError?
    private var recordedCalls: [Call] = []

    init(svg: String? = "<svg/>", delay: Duration = .zero, error: LBError? = nil) {
        self.svg = svg
        self.delay = delay
        self.error = error
    }

    func yearInMusic(username: String, year: Int, variant: LBYearInMusicArtVariant, anonymous: Bool?) async throws -> LBYearInMusicArtwork? {
        recordedCalls.append(.init(username: username, year: year, variant: variant, anonymous: anonymous))
        if delay > .zero { try await ContinuousClock().sleep(for: delay) }
        if let error { throw error }
        return svg.map(LBYearInMusicArtwork.init(svg:))
    }

    func callCount() -> Int { recordedCalls.count }
    func calls() -> [Call] { recordedCalls }
}
