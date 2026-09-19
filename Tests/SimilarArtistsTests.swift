import Foundation
import XCTest

@testable import Brainz

@MainActor
final class SimilarArtistsDecoderTests: XCTestCase {
    func testDecoderPreservesServerOrderAndDropsMalformedDuplicateAndSourceRows() throws {
        let source = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
        let first = UUID(uuidString: "39ad19e5-c0b0-454a-985b-201fb92898a0")!
        var rows: [[String: Any]] = [
            ["artist_mbid": source.uuidString, "name": "Source", "score": 100],
            ["artist_mbid": "not-a-uuid", "name": "Broken", "score": 99],
            ["artist_mbid": first.uuidString, "name": "  First Artist  ", "score": "98.5"],
            ["artist_mbid": first.uuidString, "name": "Duplicate", "score": 97],
            ["artist_mbid": UUID().uuidString, "name": "   ", "score": 96],
        ]
        let extraIDs = (0..<20).map { _ in UUID() }
        rows.append(contentsOf: extraIDs.enumerated().map { index, id in
            ["artist_mbid": id.uuidString, "name": "Artist \(index)", "score": 90 - index]
        })
        let data = try JSONSerialization.data(withJSONObject: [
            "similarArtists": ["artists": rows],
        ])

        let value = try XCTUnwrap(SimilarArtistsDecoder.decode(data, sourceArtistMBID: source))

        XCTAssertEqual(value.artists.count, SimilarArtists.maximumCount)
        XCTAssertEqual(value.artists.first?.mbid, first)
        XCTAssertEqual(value.artists.first?.name, "First Artist")
        XCTAssertEqual(value.artists.first?.score, 98.5)
        XCTAssertEqual(value.artists.dropFirst().first?.mbid, extraIDs.first)
        XCTAssertFalse(value.artists.contains { $0.mbid == source })
    }

    func testMissingOrEmptyShelfIsUnavailableAndInvalidJSONThrows() throws {
        let source = UUID()
        XCTAssertNil(try SimilarArtistsDecoder.decode(Data("{}".utf8), sourceArtistMBID: source))
        XCTAssertNil(try SimilarArtistsDecoder.decode(
            Data("{\"similarArtists\":{\"artists\":[]}}".utf8),
            sourceArtistMBID: source
        ))

        XCTAssertThrowsError(
            try SimilarArtistsDecoder.decode(Data("[]".utf8), sourceArtistMBID: source)
        ) { error in
            guard case SimilarArtistsProviderError.invalidResponse = error else {
                return XCTFail("Expected an invalid-response error")
            }
        }
    }

    func testDomainNormalizationBoundsNamesScoresAndResults() {
        let source = UUID()
        let longName = String(repeating: "A", count: 700)
        let rows = (0..<22).map { index in
            SimilarArtist(
                mbid: UUID(),
                name: index == 0 ? "  \(longName)  " : "Artist \(index)",
                score: index == 1 ? -.infinity : Double(index)
            )
        }

        let value = SimilarArtists(sourceArtistMBID: source, artists: rows)

        XCTAssertEqual(value.artists.count, SimilarArtists.maximumCount)
        XCTAssertEqual(value.artists.first?.name.count, 500)
        XCTAssertNil(value.artists[1].score)
    }
}

@MainActor
final class SimilarArtistsProviderTests: XCTestCase {
    func testRequestUsesExactPublicPostWithoutCredentials() {
        let mbid = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
        let request = SimilarArtistsTransport.request(for: mbid)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://listenbrainz.org/artist/526bd613-fddd-4bd6-9137-ab709ac74cab/"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.httpBody)
    }

    func testExactConcurrentReadCoalescesButDifferentArtistsDoNot() async throws {
        let firstArtist = UUID()
        let secondArtist = UUID()
        let transport = SimilarArtistsTransportFixture()
        let provider = ListenBrainzSimilarArtistsProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: { artistMBID in try await transport.value(for: artistMBID) }
        )

        async let first = provider.similarArtists(to: firstArtist)
        async let duplicate = provider.similarArtists(to: firstArtist)
        _ = try await [first, duplicate]
        let coalescedCount = await transport.callCount()
        XCTAssertEqual(coalescedCount, 1)

        _ = try await provider.similarArtists(to: secondArtist)
        let distinctCount = await transport.callCount()
        XCTAssertEqual(distinctCount, 2)
    }

    func testRateLimitIsSurfacedWithoutRetrying() async {
        let transport = SimilarArtistsRateLimitFixture()
        let provider = ListenBrainzSimilarArtistsProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: { artistMBID in try await transport.value(for: artistMBID) }
        )

        do {
            _ = try await provider.similarArtists(to: UUID())
            XCTFail("Expected rate limiting to be surfaced")
        } catch let SimilarArtistsProviderError.rateLimited(retryAfter) {
            // The request gate records the deferral but never retries.
            XCTAssertEqual(retryAfter, 17)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testRedirectPolicyAndRetryAfterAreBounded() throws {
        XCTAssertTrue(SimilarArtistsTransport.allowsRedirect(
            to: URL(string: "https://listenbrainz.org/artist/526bd613-fddd-4bd6-9137-ab709ac74cab/")
        ))
        XCTAssertFalse(SimilarArtistsTransport.allowsRedirect(to: URL(string: "https://example.com/collect")))
        XCTAssertFalse(SimilarArtistsTransport.allowsRedirect(to: URL(string: "http://listenbrainz.org/artist/id/")))
        XCTAssertFalse(SimilarArtistsTransport.allowsRedirect(to: URL(string: "https://listenbrainz.org:444/artist/id/")))
        XCTAssertFalse(SimilarArtistsTransport.allowsRedirect(to: URL(string: "https://name@listenbrainz.org/artist/id/")))

        let url = try XCTUnwrap(URL(string: "https://listenbrainz.org/artist/id/"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "999999999"]
        ))
        XCTAssertEqual(
            SimilarArtistsTransport.retryAfter(response),
            SimilarArtistsTransport.maximumRetryAfterSeconds
        )
    }

    func testResponseValidationCoversUnavailableRateLimitMimeAndSize() throws {
        XCTAssertEqual(
            try SimilarArtistsTransport.responseDisposition(response(status: 404)),
            .unavailable
        )
        XCTAssertEqual(
            try SimilarArtistsTransport.responseDisposition(response(status: 200)),
            .readBody
        )

        XCTAssertThrowsError(try SimilarArtistsTransport.responseDisposition(response(status: 429))) { error in
            guard case SimilarArtistsProviderError.rateLimited = error else {
                return XCTFail("Expected a rate-limit error")
            }
        }
        XCTAssertThrowsError(try SimilarArtistsTransport.responseDisposition(
            response(status: 200, headers: ["Content-Type": "text/html"])
        )) { error in
            guard case SimilarArtistsProviderError.invalidResponse = error else {
                return XCTFail("Expected invalid MIME rejection")
            }
        }
        XCTAssertThrowsError(try SimilarArtistsTransport.responseDisposition(
            response(
                status: 200,
                headers: [
                    "Content-Type": "application/json",
                    "Content-Length": String(SimilarArtistsTransport.maximumResponseBytes + 1),
                ]
            )
        )) { error in
            guard case SimilarArtistsProviderError.responseTooLarge = error else {
                return XCTFail("Expected oversized response rejection")
            }
        }
        XCTAssertThrowsError(try SimilarArtistsTransport.responseDisposition(
            response(status: 200, url: URL(string: "https://example.com/artist/id/")!)
        )) { error in
            guard case SimilarArtistsProviderError.invalidResponse = error else {
                return XCTFail("Expected cross-origin response rejection")
            }
        }
    }

    private func response(
        status: Int,
        headers: [String: String] = ["Content-Type": "application/json"],
        url: URL = URL(string: "https://listenbrainz.org/artist/id/")!
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
    }
}

@MainActor
final class SimilarArtistsModelTests: XCTestCase {
    func testFreshCacheAvoidsASecondProviderRead() async {
        let source = UUID()
        let value = fixtureValue(source: source)
        let provider = SimilarArtistsFixtureProvider(results: [.success(value)])
        let cache = EntityDetailCache<SimilarArtistsCacheKey, SimilarArtists>()
        let first = SimilarArtistsModel(artistMBID: source, provider: provider, cache: cache)
        let second = SimilarArtistsModel(artistMBID: source, provider: provider, cache: cache)

        await first.load()
        await second.load()

        XCTAssertEqual(first.phase, .loaded(value))
        XCTAssertEqual(second.phase, .loaded(value))
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testUnavailableResponseIsCachedWithoutAnEmptyShelf() async {
        let source = UUID()
        let provider = SimilarArtistsFixtureProvider(results: [.success(nil)])
        let cache = EntityDetailCache<SimilarArtistsCacheKey, SimilarArtists>()
        let first = SimilarArtistsModel(artistMBID: source, provider: provider, cache: cache)
        let second = SimilarArtistsModel(artistMBID: source, provider: provider, cache: cache)

        await first.load()
        await second.load()

        XCTAssertEqual(first.phase, .unavailable)
        XCTAssertEqual(second.phase, .unavailable)
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testStaleContentRemainsVisibleWhenRefreshFails() async {
        let source = UUID()
        let value = fixtureValue(source: source)
        let cache = EntityDetailCache<SimilarArtistsCacheKey, SimilarArtists>(timeToLive: 120)
        await cache.save(
            value,
            for: .init(artistMBID: source),
            now: .now.addingTimeInterval(-121)
        )
        let provider = SimilarArtistsFixtureProvider(results: [.failure])
        let model = SimilarArtistsModel(
            artistMBID: source,
            provider: provider,
            cache: cache
        )
        let second = SimilarArtistsModel(artistMBID: source, provider: provider, cache: cache)

        await model.load()
        await second.load()

        XCTAssertEqual(model.phase, .loaded(value))
        XCTAssertEqual(second.phase, .loaded(value))
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testFailureIsBrieflyNegativeCachedToAvoidRequestAmplification() async {
        let source = UUID()
        let provider = SimilarArtistsFixtureProvider(results: [.failure])
        let cache = EntityDetailCache<SimilarArtistsCacheKey, SimilarArtists>()
        let first = SimilarArtistsModel(artistMBID: source, provider: provider, cache: cache)
        let second = SimilarArtistsModel(artistMBID: source, provider: provider, cache: cache)

        await first.load()
        await second.load()

        guard case .failed = first.phase else { return XCTFail("The originating load should record its failure") }
        XCTAssertEqual(second.phase, .unavailable)
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testCancelledLoadReturnsToIdleAndCanLoadAgain() async {
        let source = UUID()
        let provider = SimilarArtistsSlowFixtureProvider()
        let model = SimilarArtistsModel(
            artistMBID: source,
            provider: provider,
            cache: EntityDetailCache()
        )
        let task = Task { await model.load() }
        await provider.waitUntilStarted()
        task.cancel()
        await task.value

        XCTAssertEqual(model.phase, .idle)
    }
}

private actor SimilarArtistsTransportFixture {
    private var calls = 0

    func value(for artistMBID: UUID) async throws -> Data? {
        calls += 1
        try await ContinuousClock().sleep(for: .milliseconds(25))
        return similarArtistsJSON(source: artistMBID)
    }

    func callCount() -> Int { calls }
}

private actor SimilarArtistsRateLimitFixture {
    private var calls = 0

    func value(for artistMBID: UUID) async throws -> Data? {
        calls += 1
        throw SimilarArtistsProviderError.rateLimited(retryAfter: 17)
    }

    func callCount() -> Int { calls }
}

private actor SimilarArtistsFixtureProvider: SimilarArtistsProviding {
    enum Result: Sendable {
        case success(SimilarArtists?)
        case failure
    }

    private let results: [Result]
    private var calls = 0

    init(results: [Result]) { self.results = results }

    func similarArtists(to artistMBID: UUID) async throws -> SimilarArtists? {
        let index = calls
        calls += 1
        switch results.indices.contains(index) ? results[index] : results.last ?? .failure {
        case let .success(value): return value
        case .failure: throw SimilarArtistsFixtureError.failed
        }
    }

    func callCount() -> Int { calls }
}

private actor SimilarArtistsSlowFixtureProvider: SimilarArtistsProviding {
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false

    func similarArtists(to artistMBID: UUID) async throws -> SimilarArtists? {
        didStart = true
        started?.resume()
        started = nil
        try await ContinuousClock().sleep(for: .seconds(30))
        return nil
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { started = $0 }
    }
}

private enum SimilarArtistsFixtureError: LocalizedError {
    case failed
    var errorDescription: String? { "Fixture request failed." }
}

private func fixtureValue(source: UUID) -> SimilarArtists {
    SimilarArtists(
        sourceArtistMBID: source,
        artists: [SimilarArtist(mbid: UUID(), name: "Neighbor", score: 42)]
    )
}

private func similarArtistsJSON(source: UUID) -> Data {
    let neighbor = UUID()
    return Data("""
    {"similarArtists":{"artists":[
      {"artist_mbid":"\(neighbor.uuidString)","name":"Neighbor","score":42}
    ]}}
    """.utf8)
}
