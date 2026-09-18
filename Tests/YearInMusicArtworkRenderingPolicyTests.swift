import Foundation
import XCTest

@testable import Brainz

final class YearInMusicArtworkRenderingPolicyTests: XCTestCase {
    func testOnlyCurrentOfficialArtworkResourceHostsArePermitted() {
        XCTAssertTrue(YearInMusicArtworkRenderingPolicy.permitsExternalResource(
            URL(string: "https://archive.org/download/mbid-release/cover.jpg")!
        ))
        XCTAssertTrue(YearInMusicArtworkRenderingPolicy.permitsExternalResource(
            URL(string: "https://fonts.googleapis.com/css2?family=Inter")!
        ))
        XCTAssertTrue(YearInMusicArtworkRenderingPolicy.permitsExternalResource(
            URL(string: "https://fonts.gstatic.com/s/inter/font.woff2")!
        ))

        XCTAssertFalse(YearInMusicArtworkRenderingPolicy.permitsExternalResource(
            URL(string: "http://archive.org/download/mbid-release/cover.jpg")!
        ))
        XCTAssertFalse(YearInMusicArtworkRenderingPolicy.permitsExternalResource(
            URL(string: "https://archive.org/details/unrelated")!
        ))
        XCTAssertFalse(YearInMusicArtworkRenderingPolicy.permitsExternalResource(
            URL(string: "https://api.listenbrainz.org/1/user/hidden")!
        ))
        XCTAssertFalse(YearInMusicArtworkRenderingPolicy.permitsExternalResource(
            URL(string: "https://example.com/tracker.png")!
        ))
    }

    func testContentRulesBlockFirstAndNameEveryAllowlistedHost() {
        let rules = YearInMusicArtworkRenderingPolicy.contentRuleList
        XCTAssertTrue(rules.contains(#""type":"block""#))
        XCTAssertTrue(rules.contains("archive\\\\.org/download"))
        XCTAssertTrue(rules.contains("fonts\\\\.googleapis\\\\.com"))
        XCTAssertTrue(rules.contains("fonts\\\\.gstatic\\\\.com"))
        XCTAssertFalse(rules.contains("listenbrainz\\\\.org"))
    }
}
