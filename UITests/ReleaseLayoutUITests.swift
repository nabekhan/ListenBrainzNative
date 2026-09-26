import XCTest

@MainActor
final class ReleaseLayoutUITests: XCTestCase {
    func testLiveWebSignInReachesOfficialMetaBrainzPage() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BRAINZ_LIVE_AUTH_ROUTE"] == "1",
            "Set BRAINZ_LIVE_AUTH_ROUTE=1 in the UI-test runner to run this intentional production route check."
        )

        let app = XCUIApplication()
        app.launchArguments = ["-brainz-authentication-demo"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let continueButton = app.buttons["continue-musicbrainz-sign-in"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        continueButton.tap()

        let officialHost = app.staticTexts
            .matching(identifier: "official-sign-in-host")
            .matching(
                NSPredicate(
                    format: "label == %@",
                    "Official site: metabrainz.org"
                )
            )
            .firstMatch
        XCTAssertTrue(
            officialHost.waitForExistence(timeout: 30),
            "The guarded sign-in flow did not reach the exact official MetaBrainz host."
        )
        XCTAssertEqual(officialHost.label, "Official site: metabrainz.org")
        XCTAssertFalse(app.staticTexts["Sign-in unavailable"].exists)

        app.buttons["Cancel"].tap()
    }

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

    func testHomeMetricsFollowArabicRightToLeftLayout() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-home-pin-demo",
            additionalArguments: arabicRightToLeftArguments
        )
        let window = app.windows.firstMatch
        let screen = app.scrollViews["home-screen"]
        let totalListens = app.descendants(matching: .any)["home-total-listens-metric"]
        let topArtist = app.descendants(matching: .any)["home-top-artist-metric"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(totalListens.waitForExistence(timeout: 10))
        XCTAssertTrue(topArtist.waitForExistence(timeout: 10))
        assertVisibleFrame(totalListens, in: window)
        assertVisibleFrame(topArtist, in: window)
        XCTAssertGreaterThan(totalListens.frame.midX, topArtist.frame.midX)
        keepScreenshot(named: "Home-iPad-Arabic-RTL")
    }

    func testArtistHighlightsFixtureSurvivesArabicRightToLeftLayout() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-artist-highlights-demo",
            additionalArguments: arabicRightToLeftArguments
        )
        let window = app.windows.firstMatch
        let screen = app.scrollViews["artist-highlights-screen"]
        let category = app.descendants(matching: .any)["artist-highlights-category"]

        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        XCTAssertTrue(category.waitForExistence(timeout: 15))
        assertVisibleFrame(screen, in: window)
        assertVisibleFrame(category, in: window)
        keepScreenshot(named: "Artist-highlights-iPad-Arabic-RTL")
    }

    func testArtistOriginsCountryFixtureSurvivesArabicRightToLeftLayout() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-artist-origins-country-demo",
            additionalArguments: arabicRightToLeftArguments
        )
        let window = app.windows.firstMatch
        let sheet = app.descendants(matching: .any)["artist-origins-country-sheet"]
        let summary = app.descendants(matching: .any)
            .matching(identifier: "artist-origins-country-summary")
            .firstMatch

        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        assertVisibleFrame(sheet, in: window)
        assertVisibleFrame(summary, in: window)
        keepScreenshot(named: "Artist-origins-country-iPad-Arabic-RTL")
    }

    func testYearInMusicFixtureSurvivesArabicRightToLeftLayout() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-year-in-music-demo",
            additionalArguments: arabicRightToLeftArguments
        )
        let window = app.windows.firstMatch
        let screen = app.scrollViews["year-in-music-screen"]
        let hero = app.descendants(matching: .any)["year-in-music-hero"]
        let firstCard = app.descendants(matching: .any)
            .matching(identifier: "year-in-music-identity-card")
            .firstMatch

        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        assertVisibleFrame(hero, in: window)
        keepScreenshot(named: "Year-in-Music-hero-iPad-Arabic-RTL")
        reveal(firstCard, in: screen)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        assertVisibleFrame(firstCard, in: window)
        keepScreenshot(named: "Year-in-Music-identity-iPad-Arabic-RTL")
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

    func testYearInMusicFixtureSurvivesExpandedPseudoLocalization() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-year-in-music-demo",
            additionalArguments: ["-NSDoubleLocalizedStrings", "YES"]
        )
        let window = app.windows.firstMatch
        let screen = app.scrollViews["year-in-music-screen"]
        let hero = app.descendants(matching: .any)["year-in-music-hero"]
        let firstCard = app.descendants(matching: .any)
            .matching(identifier: "year-in-music-identity-card")
            .firstMatch

        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        assertVisibleFrame(hero, in: window)
        keepScreenshot(named: "Year-in-Music-hero-iPad-pseudo-localized")
        reveal(firstCard, in: screen)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        assertVisibleFrame(firstCard, in: window)
        keepScreenshot(named: "Year-in-Music-identity-iPad-pseudo-localized")
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

    private var arabicRightToLeftArguments: [String] {
        [
            "-AppleLanguages", "(ar)",
            "-AppleLocale", "ar_SA",
            "-NSForceRightToLeftWritingDirection", "YES",
        ]
    }

    private func assertVisibleFrame(
        _ element: XCUIElement,
        in window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(element.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(element.frame.height, 0, file: file, line: line)
        XCTAssertTrue(window.frame.intersects(element.frame), file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, in scrollView: XCUIElement) {
        for _ in 0 ..< 6 {
            if element.exists, scrollView.frame.intersects(element.frame) { return }
            scrollView.swipeUp()
        }
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
