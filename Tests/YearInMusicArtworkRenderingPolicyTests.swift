import Foundation
import XCTest
@preconcurrency import WebKit

@testable import Brainz

@MainActor
final class YearInMusicArtworkRenderingPolicyTests: XCTestCase {
    private let releaseID = "c6c2a65e-4781-4a84-ad7b-9d070f4a2814"

    func testPermitsOnlyCurrentOfficialArtworkResourceShapes() {
        let allowed = [
            "https://archive.org/download/mbid-\(releaseID)/mbid-\(releaseID)-32307917052_thumb250.jpg",
            "https://archive.org:443/download/mbid-\(releaseID)/mbid-\(releaseID)-32307917052_thumb500.jpg",
            "https://dn721904.ca.archive.org/0/items/mbid-\(releaseID)/mbid-\(releaseID)-32307917052_thumb250.jpg",
            "https://fonts.googleapis.com/css2?family=Inter:wght@300;900",
            "https://fonts.googleapis.com/css2?family=Inter:wght@300;500;900",
            "https://fonts.googleapis.com/css2?family=Anonymous%20Pro:wght@400;700",
            "https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTcviYwY.woff2",
            "https://fonts.gstatic.com/s/anonymouspro/v21/rP2Bp2a15UIB7Un-bOeISG3pHls29Q.woff2",
            "https://listenbrainz.org/static/img/cover-art-placeholder-grid.png",
        ]

        for value in allowed {
            XCTAssertTrue(
                SVGArtworkRenderingPolicy.permitsExternalResource(
                    URL(string: value)!
                ),
                value
            )
        }
    }

    func testRejectsLookalikesBroaderPathsAndModifiedResources() {
        let otherID = "23da0ddf-4104-47cf-b288-c5835fbf3b08"
        let rejected = [
            "http://archive.org/download/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb250.jpg",
            "https://archive.org:444/download/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb250.jpg",
            "https://user@archive.org/download/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb250.jpg",
            "https://archive.org.evil.example/download/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb250.jpg",
            "https://archive.org/download/mbid-\(releaseID)/mbid-\(otherID)-1_thumb250.jpg",
            "https://archive.org/download/mbid-\(releaseID)/mbid-\(releaseID)-cover_thumb250.jpg",
            "https://archive.org/download/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb1000.jpg",
            "https://archive.org/download/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb250.jpg?tracker=1",
            "https://archive.org/download/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb250.jpg#fragment",
            "https://archive.org/details/mbid-\(releaseID)",
            "https://dn721904.ca.archive.org/1/items/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb250.jpg",
            "https://ia721904.us.archive.org/0/items/mbid-\(releaseID)/mbid-\(releaseID)-1_thumb250.jpg",
            "https://fonts.googleapis.com/css2?family=Roboto:wght@400",
            "https://fonts.googleapis.com/css2?family=Inter:wght@300;900&display=swap",
            "https://fonts.googleapis.com/other?family=Inter:wght@300;900",
            "https://fonts.gstatic.com/s/roboto/v1/font.woff2",
            "https://fonts.gstatic.com/s/inter/v20/font.ttf",
            "https://listenbrainz.org/static/img/another-image.png",
            "https://api.listenbrainz.org/1/user/private-data",
            "https://example.com/tracker.png",
        ]

        for value in rejected {
            XCTAssertFalse(
                SVGArtworkRenderingPolicy.permitsExternalResource(
                    URL(string: value)!
                ),
                value
            )
        }
    }

    func testSVGValidationAllowsOfficialResourcesAndIgnoresNavigationLinks() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <style>
            @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;900');
            rect { fill: url(#gradient); }
          </style>
          <defs><linearGradient id="gradient"/></defs>
          <a href="https://listenbrainz.org/artist/\(releaseID)">
            <image href="https://archive.org/download/mbid-\(releaseID)/mbid-\(releaseID)-32307917052_thumb500.jpg"/>
          </a>
          <image href="https://listenbrainz.org/static/img/cover-art-placeholder-grid.png"/>
        </svg>
        """

        XCTAssertTrue(
            SVGArtworkRenderingPolicy.permitsExternalResources(in: svg)
        )
    }

    func testSVGValidationRejectsUnknownAbsoluteProtocolRelativeAndCSSResources() {
        let documents = [
            """
            <svg xmlns="http://www.w3.org/2000/svg">
              <image href="https://example.com/tracker.png"/>
            </svg>
            """,
            """
            <svg xmlns="http://www.w3.org/2000/svg">
              <image href="//example.com/tracker.png"/>
            </svg>
            """,
            """
            <svg xmlns="http://www.w3.org/2000/svg">
              <style>rect { fill: url(https://example.com/tracker.png); }</style>
            </svg>
            """,
            "<svg",
        ]

        for svg in documents {
            XCTAssertFalse(
                SVGArtworkRenderingPolicy.permitsExternalResources(in: svg),
                svg
            )
        }
    }

    func testPreparedDocumentEmbedsSVGAndEscapesTheAccessibilityLabel() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <rect width="12" height="12" fill="#ff0000"/>
        </svg>
        """

        let document = try XCTUnwrap(
            SVGArtworkRenderingPolicy.prepareDocument(
                svg: svg,
                accessibilityLabel: "Taylor & \"Friends\" <2026>"
            )
        )

        XCTAssertTrue(document.contains("data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())"))
        XCTAssertTrue(document.contains(#"aria-label="Taylor &amp; &quot;Friends&quot; &lt;2026&gt;""#))
    }

    func testPreparedDocumentRejectsUnsafeArtwork() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <image href="https://example.com/tracker.png"/>
        </svg>
        """

        XCTAssertNil(
            SVGArtworkRenderingPolicy.prepareDocument(
                svg: svg,
                accessibilityLabel: "Unsafe artwork"
            )
        )
    }

    func testPreparedDocumentHandlesALargeBoundedArtworkPayload() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <metadata>\(String(repeating: "a", count: 4 * 1_024 * 1_024 - 128))</metadata>
          <rect width="12" height="12"/>
        </svg>
        """

        let document = try XCTUnwrap(
            SVGArtworkRenderingPolicy.prepareDocument(
                svg: svg,
                accessibilityLabel: "Large artwork"
            )
        )

        XCTAssertGreaterThan(document.utf8.count, svg.utf8.count)
    }

    func testNavigationRegistryRejectsAStaleGenerationAndConsumesTheCurrentOneOnce() {
        let staleNavigation = NSObject()
        let currentNavigation = NSObject()
        var registry = SVGArtworkNavigationRegistry()
        registry.register(staleNavigation, generation: 1)
        registry.register(currentNavigation, generation: 2)

        XCTAssertNil(
            registry.consume(
                staleNavigation,
                currentGeneration: 2
            )
        )
        XCTAssertEqual(
            registry.consume(
                currentNavigation,
                currentGeneration: 2
            ),
            2
        )
        XCTAssertNil(
            registry.consume(
                currentNavigation,
                currentGeneration: 2
            )
        )
    }

    func testNavigationRegistryInvalidationRejectsEveryOutstandingNavigation() {
        let navigation = NSObject()
        var registry = SVGArtworkNavigationRegistry()
        registry.register(navigation, generation: 1)

        registry.removeAll()

        XCTAssertNil(
            registry.consume(
                navigation,
                currentGeneration: 1
            )
        )
    }

    func testContentRulesBlockFirstNameEveryAllowedHostAndCompile() async throws {
        let rules = SVGArtworkRenderingPolicy.contentRuleList
        XCTAssertTrue(rules.contains(#""type": "block""#))
        XCTAssertTrue(rules.contains("archive\\\\.org"))
        XCTAssertTrue(rules.contains("dn[0-9]+\\\\.ca\\\\.archive\\\\.org"))
        XCTAssertTrue(rules.contains("fonts\\\\.googleapis\\\\.com"))
        XCTAssertTrue(rules.contains("fonts\\\\.gstatic\\\\.com"))
        XCTAssertTrue(rules.contains("listenbrainz\\\\.org"))

        let compiled = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<WKContentRuleList, any Error>) in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "Brainz-RenderingPolicy-Test-\(UUID().uuidString)",
                encodedContentRuleList: rules
            ) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(
                        throwing: error ?? CocoaError(.coderInvalidValue)
                    )
                }
            }
        }
        XCTAssertNotNil(compiled)
    }
}
