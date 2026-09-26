import XCTest

@MainActor
final class ReleaseLayoutUITests: XCTestCase {
    func testHomeFixtureUsesRegularWidthInPortrait() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture("-brainz-home-pin-demo")
        let window = app.windows.firstMatch

        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(window.frame.height, window.frame.width)
        XCTAssertTrue(app.staticTexts["@visual-home"].waitForExistence(timeout: 10))
        keepScreenshot(named: "Home-iPad-portrait")
    }

    func testHomeFixtureAdaptsToLandscape() throws {
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft
        defer { device.orientation = .portrait }

        let app = launchFixture("-brainz-home-pin-demo")
        let window = app.windows.firstMatch
        let accountLabel = app.staticTexts["@visual-home"]

        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue([.landscapeLeft, .landscapeRight].contains(device.orientation))
        XCTAssertTrue(accountLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(window.frame.intersects(accountLabel.frame))
        keepScreenshot(named: "Home-iPad-landscape")
    }

    func testHistoryControlsFollowRightToLeftLayout() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-history-day-demo",
            additionalArguments: [
                "-AppleLanguages", "(ar)",
                "-AppleLocale", "ar_SA",
                "-NSForceRightToLeftWritingDirection", "YES",
            ]
        )
        let previous = app.buttons["Previous day"]
        let next = app.buttons["Next day"]

        XCTAssertTrue(previous.waitForExistence(timeout: 10))
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(previous.frame.midX, next.frame.midX)
        keepScreenshot(named: "History-iPad-RTL")
    }

    func testFeedFixtureSurvivesRightToLeftLayout() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-feed-demo",
            additionalArguments: [
                "-brainz-open-feed",
                "-AppleLanguages", "(ar)",
                "-AppleLocale", "ar_SA",
                "-NSForceRightToLeftWritingDirection", "YES",
            ]
        )

        XCTAssertTrue(app.scrollViews["feed-screen"].waitForExistence(timeout: 15))
        keepScreenshot(named: "Feed-iPad-RTL")
    }

    func testProfilePlaylistsFixtureSurvivesRightToLeftLayout() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-profile-playlists-demo",
            additionalArguments: [
                "-AppleLanguages", "(ar)",
                "-AppleLocale", "ar_SA",
                "-NSForceRightToLeftWritingDirection", "YES",
            ]
        )

        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10))
        keepScreenshot(named: "Profile-playlists-iPad-RTL")
    }

    func testHomeFixtureSurvivesExpandedPseudoLocalization() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-home-pin-demo",
            additionalArguments: ["-NSDoubleLocalizedStrings", "YES"]
        )
        let accountLabel = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "visual-home"))
            .firstMatch

        XCTAssertTrue(accountLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.frame.intersects(accountLabel.frame))
        keepScreenshot(named: "Home-iPad-pseudo-localized")
    }

    func testPlaylistExportExplainsPrivateFileBeforeSharing() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture("-brainz-playlist-export-demo")

        XCTAssertTrue(app.navigationBars["Export playlist"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Private playlist"].exists)
        XCTAssertTrue(
            app.staticTexts["Anyone you share the file with can read its contents."].exists
        )
        let shareButton = app.buttons["Share playlist file"]
        XCTAssertTrue(shareButton.exists)
        let scrollView = app.scrollViews.firstMatch
        for _ in 0 ..< 3 where !shareButton.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(shareButton.isHittable)
        keepScreenshot(named: "Playlist-export-iPad-private")
    }

    func testHomeFixtureExposesMetricSemantics() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture("-brainz-home-pin-demo")
        let totalListens = app.descendants(matching: .any)["home-total-listens-metric"]
        let topArtist = app.descendants(matching: .any)["home-top-artist-metric"]

        XCTAssertTrue(totalListens.waitForExistence(timeout: 10))
        XCTAssertEqual(totalListens.label, "Total listens")
        XCTAssertFalse(accessibilityValue(of: totalListens).isEmpty)
        XCTAssertTrue(topArtist.waitForExistence(timeout: 10))
        XCTAssertEqual(topArtist.label, "Top artist")
        XCTAssertEqual(accessibilityValue(of: topArtist), "Harbor Lights")

        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "Home-iPad-accessibility-audit")
    }

    func testRecordingFeedbackExposesSelectionState() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture("-brainz-recording-feedback-demo")
        let love = app.buttons["recording-feedback-love"]
        let hate = app.buttons["recording-feedback-hate"]

        XCTAssertTrue(love.waitForExistence(timeout: 10))
        XCTAssertEqual(love.label, "Love")
        XCTAssertEqual(accessibilityValue(of: love), "Selected")
        XCTAssertTrue(love.isSelected)
        XCTAssertTrue(hate.exists)
        XCTAssertEqual(hate.label, "Hate")
        XCTAssertEqual(accessibilityValue(of: hate), "Not selected")
        XCTAssertFalse(hate.isSelected)

        let scrollView = app.scrollViews.firstMatch
        for _ in 0 ..< 3 where !love.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(love.isHittable)
        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "Recording-feedback-iPad-accessibility-audit")
    }

    private var semanticAuditTypes: XCUIAccessibilityAuditType {
        [
            .hitRegion,
            .sufficientElementDescription,
            .trait,
        ]
    }

    private func accessibilityValue(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    private func assertNoAccessibilityIssues(
        in app: XCUIApplication,
        auditTypes: XCUIAccessibilityAuditType
    ) throws {
        var descriptions: [String] = []
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            let element = issue.element
            descriptions.append(
                """
                \(issue.compactDescription): \(issue.detailedDescription)
                elementType=\(element.map { String(describing: $0.elementType) } ?? "none") \
                identifier=\(element?.identifier ?? "") label=\(element?.label ?? "") \
                value=\(element.map(self.accessibilityValue) ?? "") frame=\(element.map { String(describing: $0.frame) } ?? "none")
                """
            )
            return true
        }
        XCTAssertTrue(descriptions.isEmpty, descriptions.joined(separator: "\n\n"))
    }

    private func launchFixture(
        _ fixture: String,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            fixture,
            "-brainz-deny-request-gate-transport",
        ] + additionalArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
