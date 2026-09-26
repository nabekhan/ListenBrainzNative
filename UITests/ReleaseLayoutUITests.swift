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
