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

    func testAccessibilitySelectsEnglishPluralVariantsForZeroOneAndMany() {
        let locale = Locale(identifier: "en_US")
        let entity = PopularityEntity(kind: .recording, mbid: UUID())

        let zero = PopularitySummaryPresentation(GlobalPopularity(
            entity: entity,
            totalListenCount: 0,
            totalUserCount: 0
        ))
        let singular = PopularitySummaryPresentation(GlobalPopularity(
            entity: entity,
            totalListenCount: 1,
            totalUserCount: 1
        ))
        let plural = PopularitySummaryPresentation(GlobalPopularity(
            entity: entity,
            totalListenCount: 2,
            totalUserCount: 2
        ))

        XCTAssertEqual(
            zero.accessibilityLabel(locale: locale),
            "Across ListenBrainz, 0 listens from 0 listeners. Global totals, refreshed daily."
        )
        XCTAssertEqual(
            singular.accessibilityLabel(locale: locale),
            "Across ListenBrainz, 1 listen from 1 listener. Global totals, refreshed daily."
        )
        XCTAssertEqual(
            plural.accessibilityLabel(locale: locale),
            "Across ListenBrainz, 2 listens from 2 listeners. Global totals, refreshed daily."
        )
    }

    func testCatalogSelectsEnglishPluralVariantsAcrossCountPhrases() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(String(localized: "\(0) listens", locale: locale), "0 listens")
        XCTAssertEqual(String(localized: "\(1) listens", locale: locale), "1 listen")
        XCTAssertEqual(String(localized: "\(2) listens", locale: locale), "2 listens")
        XCTAssertEqual(String(localized: "\(0) artists", locale: locale), "0 artists")
        XCTAssertEqual(String(localized: "\(1) artists", locale: locale), "1 artist")
        XCTAssertEqual(String(localized: "\(2) artists", locale: locale), "2 artists")
        XCTAssertEqual(String(localized: "\(1) active days", locale: locale), "1 active day")
        XCTAssertEqual(String(localized: "\(2) active days", locale: locale), "2 active days")
        XCTAssertEqual(String(localized: "\(1) ratings", locale: locale), "1 rating")
        XCTAssertEqual(String(localized: "\(2) ratings", locale: locale), "2 ratings")
        XCTAssertEqual(String(localized: "\(1) releases", locale: locale), "1 release")
        XCTAssertEqual(String(localized: "\(2) releases", locale: locale), "2 releases")
        XCTAssertEqual(String(localized: "Read \(1) reviews", locale: locale), "Read 1 review")
        XCTAssertEqual(String(localized: "Read \(2) reviews", locale: locale), "Read 2 reviews")
        XCTAssertEqual(
            String(localized: "\(1) matched albums are ready", locale: locale),
            "1 matched album is ready"
        )
        XCTAssertEqual(
            String(localized: "\(2) matched albums are ready", locale: locale),
            "2 matched albums are ready"
        )
        XCTAssertEqual(
            String(localized: "\(1) unmapped tracks are left out.", locale: locale),
            "1 unmapped track is left out."
        )
        XCTAssertEqual(
            String(localized: "\(2) unmapped tracks are left out.", locale: locale),
            "2 unmapped tracks are left out."
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
