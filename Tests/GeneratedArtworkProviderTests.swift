import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

final class GeneratedArtworkProviderTests: XCTestCase {
    func testPublicArtworkUsesAnonymousCacheAcrossViewerTokens() async throws {
        let transport = RecordingGeneratedArtworkTransport(
            outcome: .artwork("<svg id=\"public\"/>")
        )
        let gate = RequestGate(minimumInterval: .zero)
        let cache = GeneratedArtworkCache()
        let first = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: gate,
            cache: cache,
            authenticatedScope: .authenticated(token: "fixture-token-a")
        )
        let second = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: gate,
            cache: cache,
            authenticatedScope: .authenticated(token: "fixture-token-b")
        )
        let request = GeneratedArtworkRequest.statistics(
            username: "listener",
            range: .thisMonth
        )

        let firstValue = try await first.artwork(for: request)
        let secondValue = try await second.artwork(for: request)

        XCTAssertEqual(firstValue?.svg, "<svg id=\"public\"/>")
        XCTAssertEqual(secondValue, firstValue)
        let calls = await transport.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testCustomArtworkUsesAnonymousScopeAndOrderedRequestIdentity() async throws {
        let transport = RecordingGeneratedArtworkTransport(
            outcome: .artwork("<svg id=\"custom\"/>")
        )
        let gate = RequestGate(minimumInterval: .zero)
        let cache = GeneratedArtworkCache()
        let firstProvider = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: gate,
            cache: cache,
            authenticatedScope: .authenticated(token: "fixture-token-a")
        )
        let secondProvider = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: gate,
            cache: cache,
            authenticatedScope: .authenticated(token: "fixture-token-b")
        )
        let first = UUID()
        let second = UUID()
        let request = GeneratedArtworkRequest.custom(
            releaseMBIDs: [first, second],
            dimension: 2,
            layout: .zero
        )

        _ = try await firstProvider.artwork(for: request)
        _ = try await secondProvider.artwork(for: request)
        _ = try await firstProvider.artwork(
            for: .custom(
                releaseMBIDs: [second, first],
                dimension: 2,
                layout: .zero
            )
        )

        let calls = await transport.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testPlaylistArtworkDoesNotCrossAuthenticatedScopes() async throws {
        let transport = RecordingGeneratedArtworkTransport(
            outcome: .artwork("<svg/>")
        )
        let gate = RequestGate(minimumInterval: .zero)
        let cache = GeneratedArtworkCache()
        let first = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: gate,
            cache: cache,
            authenticatedScope: .authenticated(token: "fixture-token-a")
        )
        let second = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: gate,
            cache: cache,
            authenticatedScope: .authenticated(token: "fixture-token-b")
        )
        let request = GeneratedArtworkRequest.playlist(
            mbid: UUID(),
            dimension: 1,
            layout: .zero
        )

        _ = try await first.artwork(for: request)
        _ = try await second.artwork(for: request)

        let calls = await transport.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testPlaylistWithoutTokenFailsBeforeTransport() async {
        let transport = RecordingGeneratedArtworkTransport(
            outcome: .artwork("<svg/>")
        )
        let provider = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            hasAuthenticatedToken: false
        )

        do {
            _ = try await provider.artwork(
                for: .playlist(
                    mbid: UUID(),
                    dimension: 1,
                    layout: .zero
                )
            )
            XCTFail("Expected local authentication rejection")
        } catch ProviderError.invalidToken {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await transport.callCount()
        XCTAssertEqual(calls, 0)
    }

    func testAuthenticationAndMalformedArtworkErrorsUseReadableMessages() async {
        let request = GeneratedArtworkRequest.playlist(
            mbid: UUID(),
            dimension: 1,
            layout: .zero
        )
        let authenticationProvider = ListenBrainzGeneratedArtworkProvider(
            transport: RecordingGeneratedArtworkTransport(
                outcome: .failure(.invalidAuth)
            ),
            gate: RequestGate(minimumInterval: .zero)
        )
        do {
            _ = try await authenticationProvider.artwork(for: request)
            XCTFail("Expected authentication failure")
        } catch ProviderError.invalidToken {
            XCTAssertEqual(
                errorDescription(ProviderError.invalidToken),
                "ListenBrainz couldn’t verify this token. Check the token and try again."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let malformedProvider = ListenBrainzGeneratedArtworkProvider(
            transport: RecordingGeneratedArtworkTransport(
                outcome: .failure(.invalidResponse)
            ),
            gate: RequestGate(minimumInterval: .zero)
        )
        do {
            _ = try await malformedProvider.artwork(
                for: .artist(mbid: UUID())
            )
            XCTFail("Expected invalid artwork failure")
        } catch let error as GeneratedArtworkProviderError {
            XCTAssertEqual(
                error.errorDescription,
                "ListenBrainz returned artwork Brainz couldn’t open. Try again later."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEveryDisplayOptionParticipatesInRequestIdentity() {
        let base = LBArtGridOptions.nativeDefault
        let options = [
            base,
            .init(
                captions: !base.captions,
                skipMissing: base.skipMissing,
                showRank: base.showRank,
                showListenCount: base.showListenCount,
                showRelease: base.showRelease,
                showArtist: base.showArtist
            ),
            .init(
                captions: base.captions,
                skipMissing: !base.skipMissing,
                showRank: base.showRank,
                showListenCount: base.showListenCount,
                showRelease: base.showRelease,
                showArtist: base.showArtist
            ),
            .init(
                captions: base.captions,
                skipMissing: base.skipMissing,
                showRank: !base.showRank,
                showListenCount: base.showListenCount,
                showRelease: base.showRelease,
                showArtist: base.showArtist
            ),
            .init(
                captions: base.captions,
                skipMissing: base.skipMissing,
                showRank: base.showRank,
                showListenCount: !base.showListenCount,
                showRelease: base.showRelease,
                showArtist: base.showArtist
            ),
            .init(
                captions: base.captions,
                skipMissing: base.skipMissing,
                showRank: base.showRank,
                showListenCount: base.showListenCount,
                showRelease: !base.showRelease,
                showArtist: base.showArtist
            ),
            .init(
                captions: base.captions,
                skipMissing: base.skipMissing,
                showRank: base.showRank,
                showListenCount: base.showListenCount,
                showRelease: base.showRelease,
                showArtist: !base.showArtist
            ),
        ]
        let keys = Set(options.map { option in
            RequestGate.ReadKey.generatedArtwork(
                .anonymous,
                request: .statistics(
                    username: "listener",
                    range: .thisMonth,
                    options: option
                )
            )
        })

        XCTAssertEqual(keys.count, options.count)
    }

    func testDuplicateReadsCoalesceAndUnavailableIsCached() async throws {
        let transport = RecordingGeneratedArtworkTransport(
            outcome: .unavailable,
            delay: .milliseconds(40)
        )
        let provider = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let request = GeneratedArtworkRequest.artist(mbid: UUID())

        async let first = provider.artwork(for: request)
        async let second = provider.artwork(for: request)
        let values = try await [first, second]
        XCTAssertEqual(values, [nil, nil])

        _ = try await provider.artwork(for: request)
        let calls = await transport.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testExpectedAbsenceIsCachedAndRateLimitRemainsVisible() async throws {
        let missingTransport = RecordingGeneratedArtworkTransport(
            outcome: .failure(.notFound)
        )
        let missingProvider = ListenBrainzGeneratedArtworkProvider(
            transport: missingTransport,
            gate: RequestGate(minimumInterval: .zero)
        )
        let request = GeneratedArtworkRequest.artist(mbid: UUID())

        let firstMissing = try await missingProvider.artwork(for: request)
        let secondMissing = try await missingProvider.artwork(for: request)
        XCTAssertNil(firstMissing)
        XCTAssertNil(secondMissing)
        let missingCalls = await missingTransport.callCount()
        XCTAssertEqual(missingCalls, 1)

        let limitedTransport = RecordingGeneratedArtworkTransport(
            outcome: .failure(.rateLimited(resetIn: 2))
        )
        let limitedProvider = ListenBrainzGeneratedArtworkProvider(
            transport: limitedTransport,
            gate: RequestGate(minimumInterval: .zero)
        )
        do {
            _ = try await limitedProvider.artwork(
                for: .artist(mbid: UUID())
            )
            XCTFail("Expected rate limit")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledReadDrainsBeforeEquivalentReplacementStarts() async throws {
        let transport = BlockingGeneratedArtworkTransport()
        let gate = RequestGate(minimumInterval: .zero)
        let provider = ListenBrainzGeneratedArtworkProvider(
            transport: transport,
            gate: gate
        )
        let request = GeneratedArtworkRequest.artist(mbid: UUID())
        let key = RequestGate.ReadKey.generatedArtwork(
            .anonymous,
            request: request
        )

        let first = Task { try await provider.artwork(for: request) }
        try await waitForCondition { await transport.startedCount() == 1 }
        first.cancel()
        do {
            _ = try await first.value
            XCTFail("The cancelled waiter should return immediately")
        } catch is CancellationError {
            // Expected.
        }
        let isDraining = await gate.isReadDrainingForTesting(key)
        XCTAssertTrue(isDraining)

        let replacement = Task { try await provider.artwork(for: request) }
        try await waitForCondition {
            await gate.drainingWaiterCountForTesting(key) == 1
        }
        let startsWhileDraining = await transport.startedCount()
        XCTAssertEqual(startsWhileDraining, 1)

        await transport.releaseOne()
        try await waitForCondition { await transport.startedCount() == 2 }
        await transport.releaseAll()
        let replacementValue = try await replacement.value

        XCTAssertEqual(replacementValue?.svg, "<svg id=\"2\"/>")
    }

    func testCacheSeparatesScopesCachesNilExpiresAndTrimsLRU() async {
        let cache = GeneratedArtworkCache(
            timeToLive: 10,
            maximumEntryCount: 2
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let first = GeneratedArtworkRequest.artist(mbid: UUID())
        let second = GeneratedArtworkRequest.artist(mbid: UUID())
        let third = GeneratedArtworkRequest.artist(mbid: UUID())
        let scopeA = RequestGate.ReadScope.authenticated(token: "fixture-a")
        let scopeB = RequestGate.ReadScope.authenticated(token: "fixture-b")

        await cache.insert(nil, request: first, scope: scopeA, now: start)
        let initialHit = await cache.lookup(
            request: first,
            scope: scopeA,
            now: start
        )
        XCTAssertEqual(initialHit, .hit(nil))
        let otherScope = await cache.lookup(
            request: first,
            scope: scopeB,
            now: start
        )
        XCTAssertEqual(otherScope, .miss)

        let secondDocument = GeneratedArtworkDocument(
            request: second,
            svg: "<svg id=\"second\"/>"
        )
        await cache.insert(
            secondDocument,
            request: second,
            scope: scopeA,
            now: start.addingTimeInterval(1)
        )
        _ = await cache.lookup(
            request: first,
            scope: scopeA,
            now: start.addingTimeInterval(2)
        )
        let thirdDocument = GeneratedArtworkDocument(
            request: third,
            svg: "<svg id=\"third\"/>"
        )
        await cache.insert(
            thirdDocument,
            request: third,
            scope: scopeA,
            now: start.addingTimeInterval(3)
        )

        let evicted = await cache.lookup(
            request: second,
            scope: scopeA,
            now: start.addingTimeInterval(3)
        )
        XCTAssertEqual(evicted, .miss)
        let beforeExpiry = await cache.lookup(
            request: first,
            scope: scopeA,
            now: start.addingTimeInterval(9)
        )
        XCTAssertEqual(beforeExpiry, .hit(nil))
        let expired = await cache.lookup(
            request: first,
            scope: scopeA,
            now: start.addingTimeInterval(10)
        )
        XCTAssertEqual(expired, .miss)
        let retained = await cache.lookup(
            request: third,
            scope: scopeA,
            now: start.addingTimeInterval(10)
        )
        XCTAssertEqual(retained, .hit(thirdDocument))
    }

    func testCacheAlsoTrimsLeastRecentlyUsedArtworkByByteBudget() async {
        let cache = GeneratedArtworkCache(
            maximumEntryCount: 8,
            maximumByteCount: 30
        )
        let first = GeneratedArtworkRequest.artist(mbid: UUID())
        let second = GeneratedArtworkRequest.artist(mbid: UUID())
        let scope = RequestGate.ReadScope.anonymous
        let start = Date(timeIntervalSince1970: 2_000)

        await cache.insert(
            GeneratedArtworkDocument(
                request: first,
                svg: String(repeating: "a", count: 20)
            ),
            request: first,
            scope: scope,
            now: start
        )
        await cache.insert(
            GeneratedArtworkDocument(
                request: second,
                svg: String(repeating: "b", count: 20)
            ),
            request: second,
            scope: scope,
            now: start.addingTimeInterval(1)
        )

        let evicted = await cache.lookup(
            request: first,
            scope: scope,
            now: start.addingTimeInterval(1)
        )
        let retained = await cache.lookup(
            request: second,
            scope: scope,
            now: start.addingTimeInterval(1)
        )
        XCTAssertEqual(evicted, .miss)
        XCTAssertEqual(
            retained,
            .hit(
                GeneratedArtworkDocument(
                    request: second,
                    svg: String(repeating: "b", count: 20)
                )
            )
        )
    }

    private func errorDescription(_ error: any LocalizedError) -> String? {
        error.errorDescription
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
                throw GeneratedArtworkProviderTestError.timeout
            }
            try await clock.sleep(for: .milliseconds(1))
        }
    }
}

private enum GeneratedArtworkProviderTestError: Error {
    case timeout
}

private actor RecordingGeneratedArtworkTransport: GeneratedArtworkTransport {
    enum Outcome: Sendable {
        case artwork(String)
        case unavailable
        case failure(LBError)
    }

    private let outcome: Outcome
    private let delay: Duration
    private var requests: [GeneratedArtworkRequest] = []

    init(outcome: Outcome, delay: Duration = .zero) {
        self.outcome = outcome
        self.delay = delay
    }

    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> LBGeneratedArtwork? {
        requests.append(request)
        if delay > .zero {
            try await ContinuousClock().sleep(for: delay)
        }
        switch outcome {
        case let .artwork(svg):
            return LBGeneratedArtwork(svg: svg)
        case .unavailable:
            return nil
        case let .failure(error):
            throw error
        }
    }

    func callCount() -> Int { requests.count }
}

private actor BlockingGeneratedArtworkTransport: GeneratedArtworkTransport {
    private var starts = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> LBGeneratedArtwork? {
        starts += 1
        let call = starts
        await withCheckedContinuation { continuations.append($0) }
        try Task.checkCancellation()
        return LBGeneratedArtwork(svg: "<svg id=\"\(call)\"/>")
    }

    func startedCount() -> Int { starts }

    func releaseOne() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
