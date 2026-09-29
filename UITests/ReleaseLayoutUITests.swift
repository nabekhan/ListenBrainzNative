import XCTest
import UIKit

@MainActor
final class ReleaseLayoutUITests: XCTestCase {
    /// This intentionally touches production data only when the runner opts
    /// in. The token is provisioned directly to the simulator clipboard before
    /// launch; it is never accepted from an XCTest argument or environment
    /// value, and this test never reads the field after pasting.
    func testOptInLiveAuthenticationSmokeIsReadOnlyAndRestoresSession() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BRAINZ_LIVE_AUTH_SMOKE"] == "1",
            "Set BRAINZ_LIVE_AUTH_SMOKE=1 only for an intentional, clipboard-provisioned production read smoke test."
        )
        defer { clearSimulatorClipboard() }

        let app = XCUIApplication()
        app.launchArguments = ["-brainz-request-audit"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        if app.navigationBars["Welcome"].waitForExistence(timeout: 5) {
            pasteSimulatorClipboardToken(into: app)
            app.buttons["Continue with token"].tap()
        }

        assertLiveTab("Home", navigationTitle: "Home", in: app)
        assertLiveHomeContent(app)
        assertLiveTab("History", navigationTitle: "History", in: app)
        assertLiveTab("Discover", navigationTitle: "Discover", in: app)
        assertLiveTab("Taste", navigationTitle: "Taste", in: app)
        assertLiveTab("Profile", navigationTitle: "Profile", in: app)
        assertExpectedUsernameIfSupplied(in: app)
        assertLiveProfilePlaylistsSettle(in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertFalse(
            app.navigationBars["Welcome"].waitForExistence(timeout: 3),
            "A successful live smoke test should restore its Keychain-backed session after relaunch."
        )
        assertLiveTab("Profile", navigationTitle: "Profile", in: app)
        assertExpectedUsernameIfSupplied(in: app)
        assertLiveProfilePlaylistsSettle(in: app)
        app.terminate()
    }

    /// Removes only the simulator's local credential and private cached data.
    /// It does not mutate the ListenBrainz account or any server-side music
    /// data, and remains skipped unless a cleanup run explicitly opts in.
    func testOptInLiveAuthenticationCleanupRemovesLocalSession() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BRAINZ_LIVE_AUTH_CLEANUP"] == "1",
            "Set BRAINZ_LIVE_AUTH_CLEANUP=1 only when intentionally clearing a credentialed simulator."
        )
        let expectedUsername = try XCTUnwrap(
            liveExpectedUsername(),
            "Set BRAINZ_LIVE_EXPECTED_USERNAME before clearing a credentialed simulator."
        )

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertFalse(
            app.navigationBars["Welcome"].waitForExistence(timeout: 3),
            "The cleanup test expected an authenticated local session."
        )

        assertLiveTab("Profile", navigationTitle: "Profile", in: app)
        assertExpectedUsername(expectedUsername, in: app)
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        let disconnectButton = app.buttons["Disconnect account"].firstMatch
        reveal(disconnectButton, in: app.collectionViews.firstMatch)
        XCTAssertTrue(disconnectButton.waitForExistence(timeout: 10))
        disconnectButton.tap()
        XCTAssertTrue(
            app.staticTexts["Disconnect from ListenBrainz?"].waitForExistence(timeout: 10)
        )

        let confirmation = app.sheets.buttons["Disconnect account"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.tap()
        XCTAssertTrue(
            app.navigationBars["Welcome"].waitForExistence(timeout: 20),
            "Disconnecting did not return to the signed-out screen."
        )

        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(
            app.navigationBars["Welcome"].waitForExistence(timeout: 10),
            "The simulator restored a credential after local cleanup."
        )
        app.terminate()
    }

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
        assertMatrixPortraitWidth(window)
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

    func testHistorySavedFallbackKeepsRowsAndOffersOneClearRetry() throws {
        let app = launchFixture("-brainz-history-saved-error-demo")

        XCTAssertTrue(app.staticTexts["Couldn’t update this day"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Showing saved history instead."].exists)
        XCTAssertTrue(app.buttons["Try Again"].exists)
        keepScreenshot(named: "History-saved-fallback-notice")

        let savedRow = app.staticTexts["Night Drive"]
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        reveal(savedRow, in: list)
        XCTAssertTrue(savedRow.waitForExistence(timeout: 5))
        keepScreenshot(named: "History-saved-fallback")
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

    func testSavedPublicProfileNoticeExplainsOfflineFallback() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture("-brainz-saved-profile-demo")
        let window = app.windows.firstMatch
        let screen = app.scrollViews["saved-profile-visual-qa-screen"]
        let notice = app.descendants(matching: .any)["saved-profile-notice"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Showing saved profile"].exists)
        XCTAssertTrue(app.buttons["Try Again"].isHittable)
        assertVisibleFrame(notice, in: window)
        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "Saved-public-profile-offline")
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
        let origins = app.descendants(matching: .any)
            .matching(identifier: "year-in-music-artist-origins")
            .firstMatch
        let listeners = app.descendants(matching: .any)
            .matching(identifier: "year-in-music-similar-listeners")
            .firstMatch

        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        assertVisibleFrame(hero, in: window)
        keepScreenshot(named: "Year-in-Music-hero-iPad-Arabic-RTL")
        reveal(firstCard, in: screen)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        assertVisibleFrame(firstCard, in: window)
        keepScreenshot(named: "Year-in-Music-identity-iPad-Arabic-RTL")
        reveal(origins, in: screen)
        XCTAssertTrue(origins.waitForExistence(timeout: 5))
        assertVisibleFrame(origins, in: window)
        reveal(listeners, in: screen)
        XCTAssertTrue(listeners.waitForExistence(timeout: 5))
        assertVisibleFrame(listeners, in: window)
        keepScreenshot(named: "Year-in-Music-secondary-context-iPad-Arabic-RTL")
    }

    func testYearInMusicSecondaryContextUsesTheRequestDeniedFixture() throws {
        let app = launchFixture("-brainz-year-in-music-demo")
        let window = app.windows.firstMatch
        let screen = app.scrollViews["year-in-music-screen"]
        let origins = app.descendants(matching: .any)
            .matching(identifier: "year-in-music-artist-origins")
            .firstMatch
        let listeners = app.descendants(matching: .any)
            .matching(identifier: "year-in-music-similar-listeners")
            .firstMatch

        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        reveal(origins, in: screen)
        XCTAssertTrue(origins.waitForExistence(timeout: 5))
        assertVisibleFrame(origins, in: window)
        keepScreenshot(named: "Year-in-Music-artist-origins")

        reveal(listeners, in: screen)
        XCTAssertTrue(listeners.waitForExistence(timeout: 5))
        assertVisibleFrame(listeners, in: window)
        keepScreenshot(named: "Year-in-Music-similar-listeners")
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
        let origins = app.descendants(matching: .any)
            .matching(identifier: "year-in-music-artist-origins")
            .firstMatch
        let listeners = app.descendants(matching: .any)
            .matching(identifier: "year-in-music-similar-listeners")
            .firstMatch

        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        assertVisibleFrame(hero, in: window)
        keepScreenshot(named: "Year-in-Music-hero-iPad-pseudo-localized")
        reveal(firstCard, in: screen)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        assertVisibleFrame(firstCard, in: window)
        keepScreenshot(named: "Year-in-Music-identity-iPad-pseudo-localized")
        reveal(origins, in: screen)
        XCTAssertTrue(origins.waitForExistence(timeout: 5))
        assertVisibleFrame(origins, in: window)
        reveal(listeners, in: screen)
        XCTAssertTrue(listeners.waitForExistence(timeout: 5))
        assertVisibleFrame(listeners, in: window)
        keepScreenshot(named: "Year-in-Music-secondary-context-iPad-pseudo-localized")
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

    func testPlaylistExportOffersLinkedServiceWithExplicitConfirmation() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-playlist-export-demo",
            additionalArguments: ["-brainz-deny-request-gate-transport"]
        )
        let scrollView = app.scrollViews.firstMatch
        let loadServices = app.buttons["playlist-load-linked-services"]
        let spotify = app.buttons["playlist-service-export-spotify"]

        XCTAssertTrue(app.navigationBars["Export playlist"].waitForExistence(timeout: 10))
        reveal(loadServices, in: scrollView)
        XCTAssertTrue(loadServices.waitForExistence(timeout: 5))
        XCTAssertTrue(loadServices.isHittable)
        XCTAssertFalse(spotify.waitForExistence(timeout: 1))
        loadServices.tap()
        reveal(spotify, in: scrollView)
        XCTAssertTrue(spotify.waitForExistence(timeout: 5))
        XCTAssertTrue(spotify.isHittable)
        spotify.tap()

        XCTAssertTrue(app.staticTexts["Export to Spotify?"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts[
                "Creates a private Spotify copy. Changes won’t sync."
            ].exists
        )
        XCTAssertTrue(app.buttons["Export to Spotify"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        keepScreenshot(named: "Playlist-service-export-confirmation")
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

        if ProcessInfo.processInfo.environment["BRAINZ_UI_MATRIX_VARIANT"] == "dark-accessibility" {
            let window = app.windows.firstMatch
            assertVisibleFrame(totalListens, in: window)
            assertVisibleFrame(topArtist, in: window)
            XCTAssertGreaterThanOrEqual(
                topArtist.frame.minY,
                totalListens.frame.maxY,
                "Home metrics should stack vertically at maximum Dynamic Type."
            )
        }

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

    func testDoNotRecommendPreferenceIsLocalFixtureAndShowsInverseAction() throws {
        let app = launchFixture("-brainz-recording-do-not-recommend-demo")
        let actions = app.buttons["Recording actions"]

        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.tap()
        let preference = app.buttons["recording-recommendation-preference"]
        XCTAssertTrue(preference.waitForExistence(timeout: 5))
        preference.tap()
        let save = app.buttons["Save “don’t recommend”"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Remove “don’t recommend”"].exists)
        save.tap()

        let confirm = app.buttons["Save Preference"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        keepScreenshot(named: "Recording-do-not-recommend-confirmation")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Preference saved to ListenBrainz."].waitForExistence(timeout: 5))
        app.buttons["OK"].tap()

        actions.tap()
        XCTAssertTrue(preference.waitForExistence(timeout: 5))
        preference.tap()
        XCTAssertTrue(app.buttons["Remove “don’t recommend”"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save “don’t recommend”"].exists)
        keepScreenshot(named: "Recording-do-not-recommend-local-fixture")
    }

    func testCritiqueBrainzReaderLoadsOnlyAfterExplicitTap() throws {
        let app = launchFixture("-brainz-critiquebrainz-reader-demo")
        let loadMore = app.buttons["Load more reviews"]

        XCTAssertTrue(loadMore.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Priya"].exists)
        loadMore.tap()

        XCTAssertTrue(app.staticTexts["Priya"].waitForExistence(timeout: 10))
        XCTAssertFalse(loadMore.exists)
        keepScreenshot(named: "CritiqueBrainz-reader-local-append")
    }

    func testCritiqueBrainzReviewComposerIsLocalAccessibleAndRequiresConsent() throws {
        let app = launchFixture("-brainz-critiquebrainz-composer-demo")
        let editor = app.textViews["Review text"]
        let publish = app.buttons["Publish"]

        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(publish.exists)
        XCTAssertFalse(publish.isEnabled)
        XCTAssertTrue(app.staticTexts["25 more characters needed"].exists)

        let form = app.collectionViews.firstMatch
        let terms = app.switches["I agree to these publishing terms."]
        reveal(terms, in: form)
        XCTAssertTrue(terms.exists)
        XCTAssertTrue(terms.isHittable)

        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "CritiqueBrainz-review-composer")
    }

    func testUserDataExportExplainsPrivacyAndManualRefresh() throws {
        let app = launchFixture("-brainz-user-data-export-demo")
        let screen = app.scrollViews["user-data-export-screen"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Download your data"].exists)
        XCTAssertTrue(app.staticTexts["Keep this archive private"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "It can contain your full listening history and account data. Share or save it only where you trust."
            ].exists
        )
        XCTAssertTrue(app.buttons["Refresh"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "ListenBrainz prepares this in the background. Brainz checks only when you refresh."
            ].exists
        )

        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "User-data-export-iPad-private")
    }

    func testArchivedHistorySnapshotIsReadOnlyLocalAndAccessible() throws {
        let app = launchFixture("-brainz-archive-history-demo")
        let screen = app.collectionViews["archived-history-snapshot"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["History snapshot"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "This is a read-only copy. It won’t update or contact ListenBrainz while you browse."
            ].exists
        )
        let archiveRange = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label BEGINSWITH %@",
                "archived-history-range",
                "Archive range:"
            ))
            .firstMatch
        XCTAssertTrue(archiveRange.exists)
        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "Archived-history-snapshot-months")

        let september = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "September 2026"))
            .firstMatch
        reveal(september, in: screen)
        XCTAssertTrue(september.waitForExistence(timeout: 5))
        september.tap()

        XCTAssertTrue(app.navigationBars["September 2026"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Read-only snapshot"].exists)
        XCTAssertTrue(app.staticTexts["2 unreadable listens were skipped."].exists)
        let monthScreen = app.collectionViews["archived-history-month"]
        XCTAssertTrue(monthScreen.waitForExistence(timeout: 5))
        let archivedTrack = app.staticTexts["Archie, Marry Me"]
        reveal(archivedTrack, in: monthScreen)
        XCTAssertTrue(archivedTrack.exists)
        XCTAssertFalse(app.buttons["Love"].exists)
        XCTAssertFalse(app.buttons["Delete listen"].exists)

        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "Archived-history-snapshot-month")
    }

    func testSearchPaginationWaitsForExplicitLoadMoreAction() throws {
        let app = launchFixture(
            "-brainz-search-pagination-demo",
            additionalArguments: searchPaginationArguments
        )
        let loadMore = app.buttons["search-load-more"]

        XCTAssertTrue(app.staticTexts["Night Walks"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Deep Focus"].exists)
        XCTAssertFalse(app.staticTexts["Late Night Coding"].exists)
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        keepScreenshot(named: "Search-pagination-first-page")

        loadMore.tap()

        XCTAssertTrue(app.staticTexts["Late Night Coding"].waitForExistence(timeout: 10))
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "Deep Focus")).count,
            1
        )
        XCTAssertFalse(loadMore.exists)
        keepScreenshot(named: "Search-pagination-second-page")
    }

    func testSearchPaginationFailureKeepsResultsAndRetriesExplicitly() throws {
        let app = launchFixture(
            "-brainz-search-pagination-failure-demo",
            additionalArguments: searchPaginationArguments
        )
        let loadMore = app.buttons["search-load-more"]

        XCTAssertTrue(app.staticTexts["Night Walks"].waitForExistence(timeout: 15))
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        loadMore.tap()

        let error = app.descendants(matching: .any)["search-load-more-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Night Walks"].exists)
        XCTAssertTrue(app.staticTexts["More results are temporarily unavailable."].exists)
        keepScreenshot(named: "Search-pagination-inline-error")

        app.buttons["Try again"].tap()

        XCTAssertTrue(app.staticTexts["Late Night Coding"].waitForExistence(timeout: 10))
        XCTAssertFalse(error.exists)
    }

    func testCommunityChartsPageOnlyAfterExplicitLoadMoreAction() throws {
        let app = launchFixture("-brainz-community-charts-demo")
        let screen = app.scrollViews["community-charts-screen"]
        let loadMore = app.buttons["community-charts-load-more"]
        let firstArtist = app.staticTexts["Nina Simone"]
        let secondArtist = app.staticTexts["Radiohead"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Community charts"].exists)
        reveal(firstArtist, in: screen)
        XCTAssertTrue(firstArtist.exists)
        reveal(secondArtist, in: screen)
        XCTAssertTrue(secondArtist.exists)
        XCTAssertFalse(app.staticTexts["Björk"].exists)
        reveal(loadMore, in: screen)
        XCTAssertTrue(loadMore.isHittable)
        keepScreenshot(named: "Community-charts-first-page")

        loadMore.tap()

        let thirdArtist = app.staticTexts["Björk"]
        let fourthArtist = app.staticTexts["Massive Attack"]
        reveal(thirdArtist, in: screen)
        XCTAssertTrue(thirdArtist.exists)
        reveal(fourthArtist, in: screen)
        XCTAssertTrue(fourthArtist.exists)
        XCTAssertFalse(loadMore.exists)
        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "Community-charts-second-page")
    }

    func testFeedbackLibraryLoadsOnlyTheSelectedRatingAndPagesExplicitly() throws {
        let app = launchFixture("-brainz-feedback-library-demo")
        let screen = app.scrollViews["feedback-library-screen"]
        let loved = app.buttons["Loved"]
        let hated = app.buttons["Hated"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Loved & Hated"].exists)
        XCTAssertTrue(loved.waitForExistence(timeout: 10))
        XCTAssertTrue(hated.exists)
        XCTAssertTrue(
            app.staticTexts["A Long Way Home Through the Quietest Part of the Night"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.staticTexts["Skip This One"].exists)

        hated.tap()

        XCTAssertTrue(app.staticTexts["Skip This One"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Unmapped Demo"].exists)
        XCTAssertTrue(app.staticTexts["Details unavailable"].exists)

        loved.tap()
        let loadMore = app.buttons["feedback-load-more"]
        reveal(loadMore, in: screen)
        XCTAssertTrue(loadMore.isHittable)
        loadMore.tap()
        XCTAssertTrue(app.staticTexts["Signals"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["New Grass"].exists)
        XCTAssertFalse(app.buttons["feedback-load-more"].exists)

        try assertNoAccessibilityIssues(
            in: app,
            auditTypes: semanticAuditTypes.union(.elementDetection)
        )
        keepScreenshot(named: "Feedback-library-iPad-accessibility-audit")
    }

    func testFeedbackLibraryKeepsRowsWhenTheNextPageFails() throws {
        let app = launchFixture("-brainz-feedback-library-partial-error-demo")
        let screen = app.scrollViews["feedback-library-screen"]
        let firstTrack = app.staticTexts["A Long Way Home Through the Quietest Part of the Night"]
        let loadMore = app.buttons["feedback-load-more"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(firstTrack.waitForExistence(timeout: 10))
        reveal(loadMore, in: screen)
        XCTAssertTrue(loadMore.isHittable)
        loadMore.tap()

        XCTAssertTrue(app.staticTexts["Check your connection, then try again."].waitForExistence(timeout: 10))
        XCTAssertTrue(firstTrack.exists)
        XCTAssertTrue(app.buttons["Retry"].exists)
        keepScreenshot(named: "Feedback-library-iPad-partial-error")
    }

    func testFeedbackLibrarySurvivesRightToLeftLayout() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = launchFixture(
            "-brainz-feedback-library-demo",
            additionalArguments: arabicRightToLeftArguments
        )

        XCTAssertTrue(app.scrollViews["feedback-library-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Loved"].exists)
        XCTAssertTrue(app.buttons["Hated"].exists)
        keepScreenshot(named: "Feedback-library-iPad-RTL")
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

    private var searchPaginationArguments: [String] {
        [
            "-brainz-open-search",
            "-brainz-search-query", "ambient",
            "-brainz-search-scope", "playlists",
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
            "-app.appearance", "system",
        ] + additionalArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func pasteSimulatorClipboardToken(into app: XCUIApplication) {
        let tokenField = app.secureTextFields["User token"]
        XCTAssertTrue(
            tokenField.waitForExistence(timeout: 10),
            "The live smoke test expected the token field on the signed-out screen."
        )
        tokenField.tap()
        tokenField.press(forDuration: 1)

        let pasteItem = app.menuItems["Paste"]
        XCTAssertTrue(
            pasteItem.waitForExistence(timeout: 5),
            "Provision the simulator clipboard before running the opt-in live smoke test."
        )
        pasteItem.tap()
        clearSimulatorClipboard()
    }

    private func assertLiveHomeContent(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.scrollViews["home-screen"].waitForExistence(timeout: 35),
            "Home did not reach its stable read-only content anchor."
        )
    }

    private func assertLiveTab(
        _ tabName: String,
        navigationTitle: String,
        in app: XCUIApplication
    ) {
        let tab = app.tabBars.buttons[tabName]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing live smoke tab.")
        tab.tap()
        XCTAssertTrue(
            app.navigationBars[navigationTitle].waitForExistence(timeout: 35),
            "A read-only live smoke destination did not become stable."
        )
    }

    private func assertExpectedUsernameIfSupplied(in app: XCUIApplication) {
        guard let expectedUsername = liveExpectedUsername() else { return }
        assertExpectedUsername(expectedUsername, in: app)
    }

    private func assertExpectedUsername(_ expectedUsername: String, in app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts[expectedUsername].waitForExistence(timeout: 10),
            "The authenticated account did not match the optional expected account."
        )
    }

    private func liveExpectedUsername() -> String? {
        let username = ProcessInfo.processInfo.environment["BRAINZ_LIVE_EXPECTED_USERNAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return username?.isEmpty == false ? username : nil
    }

    private func clearSimulatorClipboard() {
        UIPasteboard.general.items = []
    }

    private func assertLiveProfilePlaylistsSettle(in app: XCUIApplication) {
        let scrollView = app.scrollViews["profile-screen"]
        XCTAssertTrue(
            scrollView.waitForExistence(timeout: 10),
            "The Profile screen did not expose its stable content anchor."
        )

        let sectionTitle = app.staticTexts["Playlists"]
        reveal(sectionTitle, in: scrollView)

        let readyState = app.descendants(matching: .any)["profile-playlists-ready"]
        let failedState = app.descendants(matching: .any)["profile-playlists-failed"]
        XCTAssertTrue(
            readyState.waitForExistence(timeout: 35),
            "The read-only profile playlist request did not settle successfully."
        )
        XCTAssertFalse(
            failedState.exists,
            "The read-only profile playlist request ended in an error state."
        )
    }

    private func assertMatrixPortraitWidth(
        _ window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch ProcessInfo.processInfo.environment["BRAINZ_UI_MATRIX_DEVICE"] {
        case "iphone":
            XCTAssertLessThan(
                window.frame.width,
                600,
                "The iPhone matrix destination unexpectedly used a regular-width window.",
                file: file,
                line: line
            )
        case "ipad":
            XCTAssertGreaterThanOrEqual(
                window.frame.width,
                600,
                "The iPad matrix destination unexpectedly used a compact-width window.",
                file: file,
                line: line
            )
        default:
            break
        }
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
