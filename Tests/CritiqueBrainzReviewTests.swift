import Foundation
import XCTest

@testable import Brainz

@MainActor
final class CritiqueBrainzReviewModelTests: XCTestCase {
    func testFlatResponseDropsHiddenDraftWrongEntityAndMalformedRows() throws {
        let entity = CritiqueBrainzEntity(kind: .artist, mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!)
        let summary = try CritiqueBrainzReviewDecoder.decode(Data("""
        {"reviews":[
          {"id":"a4c81c31-0e10-4ee0-bd37-842c5dcdf7ad","entity_id":"526bd613-fddd-4bd6-9137-ab709ac74cab","entity_type":"artist","full_name":"Creative Commons Attribution-ShareAlike 3.0 Unported","license_id":"CC BY-SA 3.0","info_url":"https://creativecommons.org/licenses/by-sa/3.0/","rating":5,"published_on":"Tue, 15 Sep 2026 10:40:41 GMT","text":"Useful.","user":{"display_name":"Ada"}},
          {"id":"4602e98e-61f1-456b-85d0-a0fe0167d659","entity_id":"526bd613-fddd-4bd6-9137-ab709ac74cab","entity_type":"artist","is_hidden":true,"rating":5,"text":"Hidden"},
          {"id":"5e9ee8e7-85d9-4216-956c-8d699a5bd2e0","entity_id":"526bd613-fddd-4bd6-9137-ab709ac74cab","entity_type":"artist","is_draft":true,"rating":5,"text":"Draft"},
          {"id":"b5d2f714-c340-4924-9ee3-2a13d4b7c0d1","entity_id":"39ad19e5-c0b0-454a-985b-201fb92898a0","entity_type":"recording","rating":5,"text":"Wrong"},
          {"id":"not-a-uuid","entity_id":"526bd613-fddd-4bd6-9137-ab709ac74cab","entity_type":"artist","rating":5,"text":"Bad"}
        ]}
        """.utf8), for: entity)
        XCTAssertEqual(summary?.reviews.count, 1)
        XCTAssertEqual(summary?.reviews.first?.author, "Ada")
        XCTAssertEqual(summary?.reviews.first?.licenseID, "CC BY-SA 3.0")
        XCTAssertEqual(summary?.reviews.first?.licenseURL?.host, "creativecommons.org")
        XCTAssertNotNil(summary?.reviews.first?.publishedAt)
    }

    func testNestedLegacyShapeAndRatingOnlyAggregateRemainUseful() throws {
        let entity = CritiqueBrainzEntity(kind: .releaseGroup, mbid: UUID(uuidString: "eb8734c9-127d-495e-b908-9194cdbac45d")!)
        let nested = try CritiqueBrainzReviewDecoder.decode(Data("""
        {"reviews":[{"id":"a4c81c31-0e10-4ee0-bd37-842c5dcdf7ad","entity":{"id":"eb8734c9-127d-495e-b908-9194cdbac45d","type":"release_group"},"user":{"username":"mira"},"license":{"id":"CC0-1.0","info_url":"http://example.com/insecure"},"rating":null,"last_revision":{"rating":4,"text":"Still excellent."}}]}
        """.utf8), for: entity)
        XCTAssertEqual(nested?.reviews.first?.author, "mira")
        XCTAssertEqual(nested?.reviews.first?.rating, 4)
        XCTAssertEqual(nested?.reviews.first?.licenseID, "CC0-1.0")
        XCTAssertNil(nested?.reviews.first?.licenseURL)

        let ratingOnly = try CritiqueBrainzReviewDecoder.decode(Data("""
        {"reviews":[],"average_rating":{"count":2,"rating":4.5}}
        """.utf8), for: entity)
        XCTAssertEqual(ratingOnly?.reviews, [])
        XCTAssertEqual(ratingOnly?.averageRating, 4.5)
        XCTAssertEqual(ratingOnly?.ratingCount, 2)
    }

    func testLicenseLinksRejectMisleadingHosts() throws {
        let entity = CritiqueBrainzEntity(kind: .artist, mbid: UUID())
        let summary = try CritiqueBrainzReviewDecoder.decode(Data("""
        {"reviews":[{"id":"a4c81c31-0e10-4ee0-bd37-842c5dcdf7ad","entity_id":"\(entity.mbid.uuidString)","entity_type":"artist","license_id":"CC BY-SA 3.0","info_url":"https://example.com/licenses/by-sa/3.0/","rating":5}]}
        """.utf8), for: entity)
        XCTAssertEqual(summary?.reviews.first?.licenseID, "CC BY-SA 3.0")
        XCTAssertNil(summary?.reviews.first?.licenseURL)
    }

    func testFreshCacheAvoidsRepeatReadAndStaleFailureKeepsContent() async {
        let entity = CritiqueBrainzEntity(kind: .recording, mbid: UUID())
        let value = CritiqueBrainzReviewSummary(
            entity: entity,
            reviews: [
                .init(
                    id: UUID(), author: nil, licenseID: nil, licenseURL: nil,
                    rating: 4, text: nil, publishedAt: nil
                )
            ],
            averageRating: 4,
            ratingCount: 1
        )
        let cache = EntityDetailCache<CritiqueBrainzReviewCacheKey, CritiqueBrainzReviewSummary>()
        let provider = CritiqueBrainzFixtureProvider(results: [.success(value)])
        let first = CritiqueBrainzReviewModel(entity: entity, provider: provider, cache: cache)
        let second = CritiqueBrainzReviewModel(entity: entity, provider: provider, cache: cache)
        await first.load(); await second.load()
        XCTAssertEqual(first.phase, .loaded(value)); XCTAssertEqual(second.phase, .loaded(value))
        let cachedCalls = await provider.callCount()
        XCTAssertEqual(cachedCalls, 1)

        let staleCache = EntityDetailCache<CritiqueBrainzReviewCacheKey, CritiqueBrainzReviewSummary>(timeToLive: -1)
        await staleCache.save(value, for: .init(entity: entity))
        let stale = CritiqueBrainzReviewModel(entity: entity, provider: CritiqueBrainzFixtureProvider(results: [.failure]), cache: staleCache)
        await stale.load()
        XCTAssertEqual(stale.phase, .loaded(value))
        XCTAssertEqual(stale.refreshMessage, "Fixture request failed.")
    }

    func testCancelledLoadReturnsToIdleWithoutCachingAResult() async {
        let entity = CritiqueBrainzEntity(kind: .artist, mbid: UUID())
        let provider = CritiqueBrainzSlowFixtureProvider()
        let model = CritiqueBrainzReviewModel(entity: entity, provider: provider, cache: EntityDetailCache())
        let task = Task { await model.load() }
        await provider.waitUntilStarted()
        task.cancel()
        await task.value
        XCTAssertEqual(model.phase, .idle)
    }

    func testUnavailableResponseIsCached() async {
        let entity = CritiqueBrainzEntity(kind: .artist, mbid: UUID())
        let provider = CritiqueBrainzFixtureProvider(results: [.success(nil)])
        let cache = EntityDetailCache<CritiqueBrainzReviewCacheKey, CritiqueBrainzReviewSummary>()
        let first = CritiqueBrainzReviewModel(entity: entity, provider: provider, cache: cache)
        let second = CritiqueBrainzReviewModel(entity: entity, provider: provider, cache: cache)

        await first.load()
        await second.load()

        XCTAssertEqual(first.phase, .unavailable)
        XCTAssertEqual(second.phase, .unavailable)
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }
}

@MainActor
final class CritiqueBrainzReviewProviderTests: XCTestCase {
    func testExactConcurrentReadCoalescesAndDifferentEntitiesDoNot() async throws {
        let firstEntity = CritiqueBrainzEntity(kind: .artist, mbid: UUID())
        let secondEntity = CritiqueBrainzEntity(kind: .recording, mbid: firstEntity.mbid)
        let transport = CritiqueBrainzTransportFixture(data: validJSON(entity: firstEntity))
        let provider = CritiqueBrainzReviewsProvider(gate: RequestGate(minimumInterval: .zero), transport: { _ in try await transport.value() })
        async let one = provider.reviews(for: firstEntity)
        async let two = provider.reviews(for: firstEntity)
        _ = try await [one, two]
        let coalescedCalls = await transport.callCount()
        XCTAssertEqual(coalescedCalls, 1)

        _ = try await provider.reviews(for: secondEntity)
        let separateCalls = await transport.callCount()
        XCTAssertEqual(separateCalls, 2)
    }

    func testDistinctReadsRespectConfiguredStartSpacing() async throws {
        let firstEntity = CritiqueBrainzEntity(kind: .artist, mbid: UUID())
        let secondEntity = CritiqueBrainzEntity(kind: .recording, mbid: UUID())
        let starts = CritiqueBrainzStartRecorder()
        let provider = CritiqueBrainzReviewsProvider(
            gate: RequestGate(
                minimumInterval: .milliseconds(100),
                maximumConcurrentReads: 1,
                pacesReadStarts: true
            ),
            transport: { entity in
                await starts.record()
                return validJSON(entity: entity)
            }
        )

        async let first = provider.reviews(for: firstEntity)
        async let second = provider.reviews(for: secondEntity)
        _ = try await (first, second)

        let times = await starts.values()
        XCTAssertEqual(times.count, 2)
        guard times.count == 2 else { return }
        XCTAssertGreaterThanOrEqual(times[0].duration(to: times[1]), .milliseconds(90))
    }

    func testTransportRejectsCrossOriginAndDowngradeRedirects() {
        XCTAssertTrue(CritiqueBrainzTransport.allowsRedirect(to: URL(string: "https://critiquebrainz.org/ws/1/review/?limit=5")))
        XCTAssertFalse(CritiqueBrainzTransport.allowsRedirect(to: URL(string: "https://example.com/collect")))
        XCTAssertFalse(CritiqueBrainzTransport.allowsRedirect(to: URL(string: "http://critiquebrainz.org/ws/1/review/")))
        XCTAssertFalse(CritiqueBrainzTransport.allowsRedirect(to: URL(string: "https://critiquebrainz.org:444/ws/1/review/")))
    }

    func testRetryAfterIsBounded() throws {
        let url = try XCTUnwrap(URL(string: "https://critiquebrainz.org/ws/1/review/"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "999999999"]
        ))
        XCTAssertEqual(
            CritiqueBrainzTransport.retryAfter(response),
            CritiqueBrainzTransport.maximumRetryAfterSeconds
        )
    }
}

private actor CritiqueBrainzFixtureProvider: CritiqueBrainzReviewsProviding {
    enum Result: Sendable { case success(CritiqueBrainzReviewSummary?), failure }
    private let results: [Result]; private var calls = 0
    init(results: [Result]) { self.results = results }
    func reviews(for entity: CritiqueBrainzEntity) async throws -> CritiqueBrainzReviewSummary? {
        let index = calls; calls += 1
        switch results.indices.contains(index) ? results[index] : results.last! {
        case let .success(value): return value
        case .failure: throw CritiqueBrainzFixtureError.failed
        }
    }
    func callCount() -> Int { calls }
}

private actor CritiqueBrainzTransportFixture {
    private let data: Data; private var calls = 0
    init(data: Data) { self.data = data }
    func value() async throws -> Data { calls += 1; try await ContinuousClock().sleep(for: .milliseconds(25)); return data }
    func callCount() -> Int { calls }
}

private actor CritiqueBrainzStartRecorder {
    private var starts: [ContinuousClock.Instant] = []
    func record() { starts.append(.now) }
    func values() -> [ContinuousClock.Instant] { starts }
}

private actor CritiqueBrainzSlowFixtureProvider: CritiqueBrainzReviewsProviding {
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false

    func reviews(for entity: CritiqueBrainzEntity) async throws -> CritiqueBrainzReviewSummary? {
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

private enum CritiqueBrainzFixtureError: LocalizedError { case failed; var errorDescription: String? { "Fixture request failed." } }

private func validJSON(entity: CritiqueBrainzEntity) -> Data {
    Data("""
    {"reviews":[{"id":"a4c81c31-0e10-4ee0-bd37-842c5dcdf7ad","entity_id":"\(entity.mbid.uuidString)","entity_type":"\(entity.kind.rawValue)","rating":4}]}
    """.utf8)
}
