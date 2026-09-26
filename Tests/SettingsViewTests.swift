import SwiftUI
import UIKit
import XCTest

@testable import Brainz

final class SettingsViewTests: XCTestCase {
    @MainActor
    func testOpeningSettingsDoesNotLoadConnectedServices() async throws {
        let provider = SettingsCountingConnectedServicesProvider()
        let defaultsName = "SettingsViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let session = SessionModel(
            credentialStore: SettingsNoopCredentialStore(),
            defaults: defaults
        )
        let host = UIHostingController(
            rootView: NavigationStack {
                SettingsView(
                    account: Account(username: "fixture-listener", token: "fixture-token"),
                    session: session,
                    connectedServicesProvider: provider,
                    connectedServicesCache: EntityDetailCache()
                )
            }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let requestCount = await provider.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testAppearanceMapsToExpectedColorSchemes() {
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
        XCTAssertEqual(Set(AppAppearance.allCases), [.system, .light, .dark])
    }

    func testProfileURLKeepsUsernameInsideCanonicalPath() {
        let url = SettingsLinks.listenBrainzProfile(username: "listener/../other?#%")

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "listenbrainz.org")
        XCTAssertEqual(
            url.absoluteString,
            "https://listenbrainz.org/user/listener%2F..%2Fother%3F%23%25/"
        )
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
    }

    func testFixedLinksStayOnExpectedSecureHosts() {
        let links = [
            SettingsLinks.listenBrainzSettings,
            SettingsLinks.privacyPolicy,
            SettingsLinks.metaBrainzPrivacyChoices,
            SettingsLinks.repository,
            SettingsLinks.thirdPartyNotices,
            SettingsLinks.issues,
            SettingsLinks.privateSecurityReport,
        ]

        XCTAssertTrue(links.allSatisfy { $0.scheme == "https" })
        XCTAssertEqual(Set(links.compactMap(\.host)), ["listenbrainz.org", "github.com", "metabrainz.org"])
    }

    func testVersionDisplayHandlesMissingAndDuplicateValues() {
        XCTAssertEqual(SettingsAppVersion.display(version: "0.1.0", build: "1"), "0.1.0 (1)")
        XCTAssertEqual(SettingsAppVersion.display(version: "1", build: "1"), "1")
        XCTAssertEqual(SettingsAppVersion.display(version: nil, build: "7"), "7")
        XCTAssertEqual(SettingsAppVersion.display(version: " ", build: nil), "—")
    }
}

private actor SettingsCountingConnectedServicesProvider: ConnectedServicesProviding {
    private var count = 0

    func connectedServices(username: String) async throws -> ConnectedServices {
        count += 1
        return ConnectedServices(identifiers: [])
    }

    func requestCount() -> Int { count }
}

private struct SettingsNoopCredentialStore: CredentialStoring {
    func load() async throws -> LoadedCredential? { nil }
    func save(_ credential: StoredCredential) throws {}
    func delete() async throws {}
}
