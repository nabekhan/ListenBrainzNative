import XCTest
@testable import Brainz

final class ListenBrainzWebSignInPolicyTests: XCTestCase {
    func testObservedOAuthRouteSequenceIsAccepted() throws {
        XCTAssertEqual(
            route("https://listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F", matching: nil),
            .initial
        )
        let authorization = try authorize(state: "state-123")
        XCTAssertEqual(route(authorizeURL(state: "state-123"), matching: nil), .authorize(authorization))
        XCTAssertEqual(route(loginURL(state: "state-123"), matching: authorization), .login(authorization))
        XCTAssertEqual(route(loginURL(state: "state-123"), method: "POST", matching: authorization), .login(authorization))
        XCTAssertEqual(route(authorizeURL(state: "state-123"), matching: authorization), .authorize(authorization))
        XCTAssertEqual(route(authorizeURL(state: "state-123"), method: "POST", matching: authorization), .authorize(authorization))
        XCTAssertEqual(route(callbackURL(code: "code-123", state: "state-123"), matching: authorization), .callback(code: "code-123", authorization: authorization))
        XCTAssertEqual(route("https://listenbrainz.org/settings/", matching: authorization), .completion)
    }

    func testOAuthRouteRejectsUnexpectedHostsMethodsPathsAndQueries() throws {
        let authorization = try authorize(state: "state-123")
        XCTAssertNil(route("https://evil-listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F", matching: nil))
        XCTAssertNil(route("https://login.listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F", matching: nil))
        XCTAssertNil(route("http://listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F", matching: nil))
        XCTAssertNil(route("https://user@listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F", matching: nil))
        XCTAssertNil(route("https://listenbrainz.org:444/login/musicbrainz/?next=%2Fsettings%2F", matching: nil))
        XCTAssertNil(route("https://listenbrainz.org/login%2Fmusicbrainz/?next=%2Fsettings%2F", matching: nil))
        XCTAssertNil(route("https://listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F#fragment", matching: nil))
        XCTAssertNil(route("https://listenbrainz.org/login/musicbrainz/?next=settings", matching: nil))
        XCTAssertNil(route("https://listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F&next=%2Fsettings%2F", matching: nil))
        XCTAssertNil(route("https://listenbrainz.org/login/musicbrainz/?next=%2Fsettings%2F", method: "POST", matching: nil))
        XCTAssertNil(route(authorizeURL(state: "state-123", extra: "&state=duplicate"), matching: nil))
        XCTAssertNil(route(authorizeURL(state: "state-123", extra: "&unexpected=value"), matching: nil))
        XCTAssertNil(route(authorizeURL(state: ""), matching: nil))
        XCTAssertNil(route(authorizeURL(state: "state-123"), method: "POST", matching: nil))
        XCTAssertNil(route(loginURL(state: "different-state"), matching: authorization))
        XCTAssertNil(route(loginURL(state: "state-123"), method: "PUT", matching: authorization))
        XCTAssertNil(route(loginURL(state: "state-123") + "%23fragment", matching: authorization))
        XCTAssertNil(route(callbackURL(code: "code-123", state: "different-state"), matching: authorization))
        XCTAssertNil(route(callbackURL(code: "", state: "state-123"), matching: authorization))
        XCTAssertNil(route(callbackURL(code: "code-123", state: "state-123", extra: "&extra=1"), matching: authorization))
        XCTAssertNil(route("https://listenbrainz.org/settings/?extra=1", matching: authorization))
    }

    func testExtractionBrowserPermitsOnlyExactSettingsPage() {
        XCTAssertTrue(ListenBrainzWebSignInPolicy.permits(URL(string: "https://listenbrainz.org/settings/")!, in: .extraction))
        XCTAssertFalse(ListenBrainzWebSignInPolicy.permits(URL(string: "https://listenbrainz.org/settings")!, in: .extraction))
        XCTAssertFalse(ListenBrainzWebSignInPolicy.permits(URL(string: "https://listenbrainz.org/settings/?next=profile")!, in: .extraction))
        XCTAssertFalse(ListenBrainzWebSignInPolicy.permits(URL(string: "https://listenbrainz.org/settings%2F")!, in: .extraction))
    }

    func testCanonicalTokenRequiresLowercaseUUIDWithoutWhitespace() {
        XCTAssertEqual(ListenBrainzWebSignInPolicy.canonicalToken(from: "123e4567-e89b-12d3-a456-426614174000"), "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertNil(ListenBrainzWebSignInPolicy.canonicalToken(from: " 123e4567-e89b-12d3-a456-426614174000"))
        XCTAssertNil(ListenBrainzWebSignInPolicy.canonicalToken(from: "123E4567-E89B-12D3-A456-426614174000"))
        XCTAssertNil(ListenBrainzWebSignInPolicy.canonicalToken(from: "not-a-token"))
    }

    private func authorize(state: String) throws -> ListenBrainzWebSignInPolicy.Authorization {
        guard case .authorize(let authorization)? = route(authorizeURL(state: state), matching: nil) else {
            throw NSError(domain: "ListenBrainzWebSignInPolicyTests", code: 1)
        }
        return authorization
    }

    private func route(_ string: String, method: String = "GET", matching: ListenBrainzWebSignInPolicy.Authorization?) -> ListenBrainzWebSignInPolicy.CredentialRoute? {
        ListenBrainzWebSignInPolicy.credentialRoute(for: URL(string: string)!, method: method, matching: matching)
    }

    private func authorizeURL(state: String, extra: String = "") -> String {
        "https://metabrainz.org/oauth2/authorize?response_type=code&client_id=5i5ZSOSjNGDCVt3yOovLkDb2&redirect_uri=https%3A%2F%2Flistenbrainz.org%2Flogin%2Fmusicbrainz%2Fpost%2F&scope=musicbrainz%3Atag+musicbrainz%3Arating+profile+email&state=\(state)&access_type=offline\(extra)"
    }

    private func loginURL(state: String) -> String {
        let next = authorizeURL(state: state).replacingOccurrences(of: "https://metabrainz.org", with: "")
        var components = URLComponents(string: "https://metabrainz.org/login")!
        components.queryItems = [URLQueryItem(name: "next", value: next)]
        return components.url!.absoluteString
    }

    private func callbackURL(code: String, state: String, extra: String = "") -> String {
        "https://listenbrainz.org/login/musicbrainz/post/?code=\(code)&state=\(state)\(extra)"
    }
}
