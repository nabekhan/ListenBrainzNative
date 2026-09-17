// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct APIClientTests {
    @Test("Endpoint paths retain path separators")
    func endpointPath() throws {
        let client = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )

        let request = try client.makeURLRequest(
            UserListensRequest(username: "test-user", latest: nil, earliest: nil, count: 25)
        )

        #expect(request.url?.path == "/1/user/test-user/listens")
        #expect(request.url?.absoluteString.contains("%2F1%2F") == false)
        #expect(request.url?.query?.contains("count=25") == true)
    }

    @Test("Endpoint-required terminal slash is preserved")
    func endpointTerminalSlash() throws {
        let client = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )

        let request = try client.makeURLRequest(
            SitewideFreshReleasesRequest(days: 14, includePast: true, includeFuture: true, sort: .releaseDate)
        )

        #expect(request.url?.absoluteString.contains("/1/explore/fresh-releases/?") == true)
        #expect(request.url?.query?.contains("days=14") == true)
    }

    @Test("Requests identify the application without sending an empty token")
    func requiredHeaders() throws {
        let userAgent = "TestClient/1.0 (+https://example.com)"
        let client = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: userAgent
        )

        let request = try client.makeURLRequest(SearchUserRequest("test"))

        #expect(request.value(forHTTPHeaderField: "User-Agent") == userAgent)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Encoded request bodies declare JSON content")
    func jsonBodyContentType() throws {
        let client = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let request = try client.makeURLRequest(MetadataRecordingRequest(
            mbids: [
                UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!,
                UUID(uuidString: "a6081bc1-2a76-4984-b21f-38bc3dcca3a5")!,
            ],
            including: [.artist, .release]
        ))

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody?.isEmpty == false)
    }

    @Test("Authenticated requests use ListenBrainz token authentication")
    func tokenHeader() throws {
        let client = ListenBrainzAPIClient(
            token: "secret-placeholder",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )

        let request = try client.makeURLRequest(ValidateTokenRequest())

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token secret-placeholder")
    }

    @Test("Tokens are never attached to an insecure custom root")
    func insecureTokenRoot() throws {
        let client = ListenBrainzAPIClient(
            token: "secret-placeholder",
            root: URL(string: "http://example.com")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )

        #expect(throws: LBError.invalidParam) {
            try client.makeURLRequest(ValidateTokenRequest())
        }
    }

    @Test("Custom roots require explicit authorization before receiving a token")
    func customRootTokenPolicy() throws {
        let root = URL(string: "https://listenbrainz.example.com")!
        let blocked = ListenBrainzAPIClient(
            token: "secret-placeholder",
            root: root,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let allowed = ListenBrainzAPIClient(
            token: "secret-placeholder",
            root: root,
            allowsTokenToCustomRoot: true,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )

        #expect(throws: LBError.invalidParam) {
            try blocked.makeURLRequest(ValidateTokenRequest())
        }
        let request = try allowed.makeURLRequest(ValidateTokenRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token secret-placeholder")
    }

    @Test("Rate limiting honors the longest server delay")
    func rateLimitHeaders() throws {
        let client = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://api.listenbrainz.org/1/validate-token")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "3", "X-RateLimit-Reset-In": "7"]
            )
        )

        #expect(client.rateLimitDelay(from: response) == 7)
    }

    @Test("Mapped 204 responses are handled before body decoding")
    func noContentResponse() throws {
        let client = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://api.listenbrainz.org/1/stats/user/test/listening-activity")!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )
        )

        #expect(
            client.responseError(
                from: response,
                for: StatsActivityRequest(user: "test", range: .thisWeek)
            ) == .noContent
        )
    }

    @Test("Authenticated redirects stay on the original origin")
    func authenticatedRedirectPolicy() throws {
        let policy = AuthenticatedRedirectDelegate()
        let source = try #require(URL(string: "https://api.listenbrainz.org/1/validate-token"))

        #expect(policy.allowsAuthenticatedRedirect(
            from: source,
            to: URL(string: "https://api.listenbrainz.org:443/1/validate-token/")!
        ))
        #expect(!policy.allowsAuthenticatedRedirect(
            from: source,
            to: URL(string: "https://example.com/collect")!
        ))
        #expect(!policy.allowsAuthenticatedRedirect(
            from: source,
            to: URL(string: "http://api.listenbrainz.org/1/validate-token")!
        ))
    }
}
