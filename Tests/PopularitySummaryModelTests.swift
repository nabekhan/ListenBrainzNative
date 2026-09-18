import Foundation
import XCTest

@testable import Brainz

@MainActor
final class PopularitySummaryModelTests: XCTestCase {
    func testLoadedPopularityKeepsGlobalCountsSeparate() async throws {
        let entity = PopularityEntity(kind: .artist, mbid: UUID())
        let provider = PopularitySummaryFixtureProvider(results: [
            .success(GlobalPopularity(entity: entity, totalListenCount: 2_418_731, totalUserCount: 148_206)),
        ])
        let model = PopularitySummaryModel(entity: entity, provider: provider)

        await model.load()
        await model.load()

        XCTAssertEqual(
            model.phase,
            .loaded(GlobalPopularity(entity: entity, totalListenCount: 2_418_731, totalUserCount: 148_206))
        )
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testMissingAndMalformedCountsAreUnavailableRatherThanZero() async {
        let entity = PopularityEntity(kind: .recording, mbid: UUID())
        let provider = PopularitySummaryFixtureProvider(results: [
            .success(GlobalPopularity(entity: entity, totalListenCount: -1, totalUserCount: nil)),
        ])
        let model = PopularitySummaryModel(entity: entity, provider: provider)

        await model.load()

        XCTAssertEqual(model.phase, .unavailable)
    }

    func testRetryRecoversFromANonBlockingFailure() async {
        let entity = PopularityEntity(kind: .releaseGroup, mbid: UUID())
        let value = GlobalPopularity(entity: entity, totalListenCount: 8_301, totalUserCount: 742)
        let provider = PopularitySummaryFixtureProvider(results: [.failure, .success(value)])
        let model = PopularitySummaryModel(entity: entity, provider: provider)

        await model.load()
        guard case .failed = model.phase else {
            return XCTFail("Expected the initial request to fail")
        }

        await model.retry()

        XCTAssertEqual(model.phase, .loaded(value))
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testAccessibilityUsesFullLocalizedValuesInsteadOfCompactLabels() {
        let locale = Locale(identifier: "en_US")
        let entity = PopularityEntity(kind: .release, mbid: UUID())
        let presentation = PopularitySummaryPresentation(GlobalPopularity(
            entity: entity,
            totalListenCount: 2_418_731,
            totalUserCount: 148_206
        ))

        XCTAssertTrue(presentation.compact(2_418_731, locale: locale).count < "2,418,731".count)
        XCTAssertEqual(
            presentation.accessibilityLabel(locale: locale),
            "Across ListenBrainz, 2,418,731 listens from 148,206 listeners. Global totals, refreshed daily."
        )
    }
}

private actor PopularitySummaryFixtureProvider: PopularityProviding {
    enum Result: Sendable {
        case success(GlobalPopularity)
        case failure
    }

    private let results: [Result]
    private var calls = 0

    init(results: [Result]) {
        self.results = results
    }

    func popularity(for entity: PopularityEntity) async throws -> GlobalPopularity {
        let index = calls
        calls += 1
        switch results.indices.contains(index) ? results[index] : results.last ?? .failure {
        case let .success(value):
            return value
        case .failure:
            throw PopularitySummaryFixtureError.failed
        }
    }

    func callCount() -> Int { calls }
}

private enum PopularitySummaryFixtureError: LocalizedError {
    case failed

    var errorDescription: String? { "Fixture failed" }
}
