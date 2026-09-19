import Foundation
import XCTest

@testable import Brainz

final class ArtistOriginsPresentationTests: XCTestCase {
    func testPresentationRanksLocallyByEitherMetricWithDeterministicTies() {
        let origins = ArtistOrigins(
            period: .thisYear,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [
                .init(countryCode: "USA", artistCount: 2, listenCount: 100, artists: []),
                .init(countryCode: "CAN", artistCount: 4, listenCount: 20, artists: []),
                .init(countryCode: "?", artistCount: 4, listenCount: 10, artists: []),
            ]
        )
        let locale = Locale(identifier: "en_US")

        let byArtists = ArtistOriginsPresentation(origins: origins, metric: .artists, locale: locale)
        XCTAssertEqual(byArtists.rows.map(\.country.code), ["CAN", nil, "USA"])
        XCTAssertEqual(byArtists.maximumValue, 4)

        let byListens = ArtistOriginsPresentation(origins: origins, metric: .listens, locale: locale)
        XCTAssertEqual(byListens.rows.map(\.country.code), ["USA", "CAN", nil])
        XCTAssertEqual(byListens.maximumValue, 100)
    }

    func testPresentationUsesLocalizedNamesAndAnExplicitUnknownFallback() throws {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(ArtistOriginsPresentation.countryName(code: "CAN", locale: locale), "Canada")
        XCTAssertEqual(ArtistOriginsPresentation.countryName(code: nil, locale: locale), "Unknown origin")
    }

    func testArtistOnlyRowsRemainVisibleWhenLegacyPayloadOmitsListenCounts() {
        let origins = ArtistOrigins(
            period: .allTime,
            from: .distantPast,
            to: .distantPast,
            lastUpdated: .distantPast,
            rows: [.init(countryCode: "CAN", artistCount: 3, listenCount: 0, artists: [])]
        )

        XCTAssertFalse(origins.isEmpty)
        XCTAssertEqual(origins.totalArtistCount, 3)
        XCTAssertEqual(origins.totalListenCount, 0)
    }
}
