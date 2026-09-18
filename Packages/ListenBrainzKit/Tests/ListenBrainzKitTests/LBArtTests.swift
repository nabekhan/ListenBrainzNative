// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import ListenBrainzKit

@Suite
struct LBArtTests {
    @Test("Year in Music art requests encode every image variant and options")
    func requestSemantics() throws {
        let root = URL(string: "https://example.invalid")!
        let client = ListenBrainzAPIClient(token: "", root: root, userAgent: "Tests")

        for variant in LBYearInMusicArtVariant.allCases {
            let request = YearInMusicArtworkRequest(
                username: " name/with?reserved#characters ",
                year: 2025,
                variant: variant,
                anonymous: false
            )
            let url = try #require(try client.makeURLRequest(request).url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.percentEncodedPath == "/1/art/year-in-music/2025/%20name%2Fwith%3Freserved%23characters%20")
            let items = try #require(components.queryItems)
            #expect(items.first(where: { $0.name == "image" })?.value == variant.rawValue)
            #expect(items.first(where: { $0.name == "anonymous" })?.value == "false")
        }
    }

    @Test("Year in Music art omits anonymous query when unspecified")
    func optionalAnonymousQuery() throws {
        let request = YearInMusicArtworkRequest(
            username: "listener",
            year: 2025,
            variant: .overview,
            anonymous: nil
        )
        #expect(request.data.queryItems == ["image": ["overview"]])
        #expect(request.data.statusErrors[400] == .badRequest)
    }

    @Test("Year in Music art validates SVG responses and maps 204 to nil")
    func responseValidation() throws {
        let request = YearInMusicArtworkRequest(
            username: "listener",
            year: 2025,
            variant: .overview,
            anonymous: nil
        )
        let url = URL(string: "https://example.invalid/art.svg")!
        let svgResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/svg+xml; charset=utf-8"]
        )!
        let artwork = try request.decodeResponse(Data("<?xml version=\"1.0\"?><svg/>".utf8), response: svgResponse)
        #expect(artwork?.svg.contains("<svg") == true)

        let noContent = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!
        #expect(try request.decodeResponse(Data(), response: noContent) == nil)

        let wrongType = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(Data("<svg/>".utf8), response: wrongType)
        }
        let missingType = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(Data("<svg/>".utf8), response: missingType)
        }
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(Data([0xFF, 0xFE]), response: nil)
        }
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(Data("  \n".utf8), response: nil)
        }
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(Data("not an XML root <svg/>".utf8), response: nil)
        }
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(
                Data(repeating: 0x20, count: YearInMusicArtworkRequest.maximumPayloadSize + 1),
                response: nil
            )
        }
    }

    @Test("Year in Music art client executes typed request")
    func clientExecution() async throws {
        let expected = LBYearInMusicArtwork(svg: "<svg/>")
        let mock = MockAPIClient(result: .success(expected))
        let client = LBArtClient(mock)
        let result = try await client.yearInMusic(
            username: "listener",
            year: 2025,
            variant: .tracks,
            anonymous: true
        )
        #expect(result == expected)
        let request = try #require(mock.request as? YearInMusicArtworkRequest)
        #expect(request.data.queryItems["image"] == ["tracks"])
        #expect(request.data.queryItems["anonymous"] == ["true"])
    }
}
