// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import ListenBrainzKit

@Suite
struct LBArtTests {
    private let root = URL(string: "https://example.invalid")!

    @Test("Year in Music art requests encode every image variant and option")
    func yearInMusicRequestSemantics() throws {
        let client = ListenBrainzAPIClient(
            token: "",
            root: root,
            userAgent: "Tests"
        )

        for variant in LBYearInMusicArtVariant.allCases {
            let request = YearInMusicArtworkRequest(
                username: " name/with?reserved#characters ",
                year: 2025,
                variant: variant,
                anonymous: false
            )
            let url = try #require(try client.makeURLRequest(request).url)
            let components = try #require(
                URLComponents(url: url, resolvingAgainstBaseURL: false)
            )
            #expect(
                components.percentEncodedPath
                    == "/1/art/year-in-music/2025/%20name%2Fwith%3Freserved%23characters%20"
            )
            let items = try #require(components.queryItems)
            #expect(
                items.first(where: { $0.name == "image" })?.value
                    == variant.rawValue
            )
            #expect(
                items.first(where: { $0.name == "anonymous" })?.value
                    == "false"
            )
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

    @Test("Statistics art sends its exact path and every display option")
    func statisticsGridSemantics() throws {
        let options = LBArtGridOptions(
            captions: false,
            skipMissing: false,
            showRank: true,
            showListenCount: false,
            showRelease: false,
            showArtist: true
        )
        let request = try StatisticsGridArtworkRequest(
            username: "name/with?reserved#characters",
            range: .halfYearly,
            dimension: 4,
            layout: .three,
            imageSize: 1_024,
            options: options
        )
        let urlRequest = try makeURLRequest(request)
        let url = try #require(urlRequest.url)
        let components = try #require(
            URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        )

        #expect(urlRequest.httpMethod == "GET")
        #expect(
            components.percentEncodedPath
                == "/1/art/grid-stats/name%2Fwith%3Freserved%23characters/half_yearly/4/3/1024"
        )
        #expect(queryValues(components) == [
            "caption": "false",
            "show-artist": "true",
            "show-listen-count": "false",
            "show-rank": "true",
            "show-release": "false",
            "skip-missing": "false",
        ])
        #expect(request.data.statusErrors == [400: .badRequest, 404: .notFound])
    }

    @Test("Artist and playlist art use their exact public and authenticated shapes")
    func artistAndPlaylistSemantics() throws {
        let mbid = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let artist = try ArtistGridArtworkRequest(
            artistMBID: mbid,
            dimension: 3,
            layout: .two,
            imageSize: 128,
            options: .init(captions: false, skipMissing: true)
        )
        let artistRequest = try makeURLRequest(artist)
        let artistURL = try #require(artistRequest.url)
        let artistComponents = try #require(
            URLComponents(
                url: artistURL,
                resolvingAgainstBaseURL: false
            )
        )
        #expect(artistRequest.httpMethod == "GET")
        #expect(
            artistComponents.path
                == "/1/art/artist-grid/11111111-2222-4333-8444-555555555555/3/2/128"
        )
        #expect(queryValues(artistComponents) == [
            "caption": "false",
            "skip-missing": "true",
        ])

        let playlist = try PlaylistArtworkRequest(
            playlistMBID: mbid,
            dimension: 5,
            layout: .one
        )
        let playlistRequest = try makeURLRequest(playlist)
        #expect(playlistRequest.httpMethod == "POST")
        #expect(
            playlistRequest.url?.path
                == "/1/art/playlist/11111111-2222-4333-8444-555555555555/5/1"
        )
        #expect(playlist.data.queryItems.isEmpty)
        #expect(playlist.data.statusErrors[400] == .badRequest)
        #expect(playlist.data.statusErrors[401] == .invalidAuth)
        #expect(playlist.data.statusErrors[404] == .notFound)
    }

    @Test("Custom grid art sends one bounded ordered JSON request")
    func customGridSemantics() throws {
        let first = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let second = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let request = try CustomGridArtworkRequest(
            items: .releases([first, second]),
            dimension: 3,
            layout: .one,
            imageSize: 924,
            background: .hex("#AbC123"),
            captions: true,
            skipMissing: false,
            showMissingCoverPlaceholder: true,
            coverArtSize: .large
        )
        let urlRequest = try makeURLRequest(request)
        let bodyData = try #require(urlRequest.httpBody)
        let body = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )

        #expect(urlRequest.httpMethod == "POST")
        let url = try #require(urlRequest.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        #expect(components.percentEncodedPath == "/1/art/grid/")
        #expect(urlRequest.url?.query?.isEmpty != false)
        #expect(
            urlRequest.value(forHTTPHeaderField: "Content-Type")
                == "application/json"
        )
        #expect(body["background"] as? String == "#abc123")
        #expect(body["image_size"] as? Int == 924)
        #expect(body["dimension"] as? Int == 3)
        #expect(body["layout"] as? Int == 1)
        #expect(body["caption"] as? Bool == true)
        #expect(body["skip-missing"] as? Bool == false)
        #expect(body["show-caa"] as? Bool == true)
        #expect(body["cover_art_size"] as? Int == 500)
        #expect(body["release_mbids"] as? [String] == [
            "11111111-2222-4333-8444-555555555555",
            "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        ])
        #expect(body["release_group_mbids"] == nil)
        #expect(request.data.statusErrors == [400: .badRequest])
        #expect(
            request.data.maximumResponseBytes
                == ArtSVGResponseDecoder.maximumPayloadSize
        )
    }

    @Test("Custom grid art keeps release-group identity separate")
    func customGridReleaseGroupSemantics() throws {
        let mbid = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let request = try CustomGridArtworkRequest(
            items: .releaseGroups([mbid]),
            dimension: 1,
            layout: .zero,
            imageSize: 128,
            background: .transparent,
            captions: false,
            skipMissing: true,
            showMissingCoverPlaceholder: false,
            coverArtSize: .compact
        )
        let urlRequest = try makeURLRequest(request)
        let bodyData = try #require(urlRequest.httpBody)
        let body = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )

        #expect(body["release_mbids"] == nil)
        #expect(body["release_group_mbids"] as? [String] == [
            "11111111-2222-4333-8444-555555555555",
        ])
        #expect(body["background"] as? String == "transparent")
        #expect(body["cover_art_size"] as? Int == 250)
    }

    @Test("Every documented dimension and layout combination is accepted")
    func validGridBounds() throws {
        let valid: [(Int, [LBArtGridLayout])] = [
            (1, [.zero]),
            (2, [.zero]),
            (3, [.zero, .one, .two]),
            (4, [.zero, .one, .two, .three]),
            (5, [.zero, .one]),
        ]
        for (dimension, layouts) in valid {
            for layout in layouts {
                _ = try StatisticsGridArtworkRequest(
                    username: "listener",
                    range: .month,
                    dimension: dimension,
                    layout: layout,
                    imageSize: 128,
                    options: .nativeDefault
                )
                _ = try ArtistGridArtworkRequest(
                    artistMBID: UUID(),
                    dimension: dimension,
                    layout: layout,
                    imageSize: 1_024,
                    options: .nativeDefault
                )
                _ = try PlaylistArtworkRequest(
                    playlistMBID: UUID(),
                    dimension: dimension,
                    layout: layout
                )
            }
        }
    }

    @Test("Invalid generic-art bounds throw instead of trapping")
    func invalidGridBounds() {
        #expect(throws: LBError.invalidParam) {
            _ = try StatisticsGridArtworkRequest(
                username: "listener",
                range: .month,
                dimension: 0,
                layout: .zero,
                imageSize: 924,
                options: .nativeDefault
            )
        }
        #expect(throws: LBError.invalidParam) {
            _ = try ArtistGridArtworkRequest(
                artistMBID: UUID(),
                dimension: 2,
                layout: .one,
                imageSize: 924,
                options: .nativeDefault
            )
        }
        #expect(throws: LBError.invalidParam) {
            _ = try PlaylistArtworkRequest(
                playlistMBID: UUID(),
                dimension: 5,
                layout: .two
            )
        }
        for size in [127, 1_025] {
            #expect(throws: LBError.invalidParam) {
                _ = try StatisticsGridArtworkRequest(
                    username: "listener",
                    range: .month,
                    dimension: 3,
                    layout: .one,
                    imageSize: size,
                    options: .nativeDefault
                )
            }
        }

        for items in [
            LBCustomArtGridItems.releases([]),
            .releaseGroups(Array(repeating: UUID(), count: 101)),
        ] {
            #expect(throws: LBError.invalidParam) {
                _ = try CustomGridArtworkRequest(
                    items: items,
                    dimension: 3,
                    layout: .zero,
                    imageSize: 924,
                    background: .black,
                    captions: false,
                    skipMissing: false,
                    showMissingCoverPlaceholder: true,
                    coverArtSize: .large
                )
            }
        }
        #expect(throws: LBError.invalidParam) {
            _ = try CustomGridArtworkRequest(
                items: .releases([UUID()]),
                dimension: 3,
                layout: .zero,
                imageSize: 924,
                background: .hex("not-a-color"),
                captions: false,
                skipMissing: false,
                showMissingCoverPlaceholder: true,
                coverArtSize: .large
            )
        }
    }

    @Test("Invalid client calls fail before transport")
    func invalidClientCallsDoNotExecute() async {
        let mock = MockAPIClient(result: .failure(.unknownError))
        let client = LBArtClient(mock)

        await #expect(throws: LBError.invalidParam) {
            _ = try await client.statisticsGrid(
                username: "listener",
                range: .month,
                dimension: 6
            )
        }
        #expect(mock.request == nil)

        await #expect(throws: LBError.invalidParam) {
            _ = try await client.artistGrid(
                artistMBID: UUID(),
                dimension: 4,
                layout: .zero,
                imageSize: 2_000
            )
        }
        #expect(mock.request == nil)

        await #expect(throws: LBError.invalidParam) {
            _ = try await client.playlistArtwork(
                playlistMBID: UUID(),
                dimension: 2,
                layout: .one
            )
        }
        #expect(mock.request == nil)
    }

    @Test("Art responses require a bounded SVG with the correct MIME type")
    func responseValidation() throws {
        let request = try StatisticsGridArtworkRequest(
            username: "listener",
            range: .month,
            dimension: 3,
            layout: .one,
            imageSize: 924,
            options: .nativeDefault
        )
        let svgResponse = HTTPURLResponse(
            url: root,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/svg+xml; charset=utf-8"]
        )!
        let artwork = try request.decodeResponse(
            Data("<?xml version=\"1.0\"?><svg/>".utf8),
            response: svgResponse
        )
        #expect(artwork?.svg.contains("<svg") == true)

        let noContent = HTTPURLResponse(
            url: root,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(try request.decodeResponse(Data(), response: noContent) == nil)

        let wrongType = HTTPURLResponse(
            url: root,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(
                Data("<svg/>".utf8),
                response: wrongType
            )
        }
        let missingType = HTTPURLResponse(
            url: root,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(
                Data("<svg/>".utf8),
                response: missingType
            )
        }
        for malformed in [
            Data([0xFF, 0xFE]),
            Data("  \n".utf8),
            Data("not an XML root <svg/>".utf8),
        ] {
            #expect(throws: LBError.invalidResponse) {
                _ = try request.decodeResponse(malformed, response: nil)
            }
        }
        #expect(throws: LBError.invalidResponse) {
            _ = try request.decodeResponse(
                Data(
                    repeating: 0x20,
                    count: ArtSVGResponseDecoder.maximumPayloadSize + 1
                ),
                response: nil
            )
        }
    }

    @Test("Year in Music and generic clients execute typed requests")
    func clientExecution() async throws {
        let yearExpected = LBYearInMusicArtwork(svg: "<svg id=\"year\"/>")
        let yearMock = MockAPIClient(result: .success(yearExpected))
        let yearResult = try await LBArtClient(yearMock).yearInMusic(
            username: "listener",
            year: 2025,
            variant: .tracks,
            anonymous: true
        )
        #expect(yearResult == yearExpected)
        let yearRequest = try #require(
            yearMock.request as? YearInMusicArtworkRequest
        )
        #expect(yearRequest.data.queryItems["image"] == ["tracks"])
        #expect(yearRequest.data.queryItems["anonymous"] == ["true"])

        let genericExpected = LBGeneratedArtwork(svg: "<svg id=\"grid\"/>")
        let statsMock = MockAPIClient(result: .success(genericExpected))
        #expect(
            try await LBArtClient(statsMock).statisticsGrid(
                username: "listener",
                range: .thisMonth
            ) == genericExpected
        )
        #expect(statsMock.request is StatisticsGridArtworkRequest)

        let artistMock = MockAPIClient(result: .success(genericExpected))
        #expect(
            try await LBArtClient(artistMock).artistGrid(
                artistMBID: UUID()
            ) == genericExpected
        )
        #expect(artistMock.request is ArtistGridArtworkRequest)

        let playlistMock = MockAPIClient(result: .success(genericExpected))
        #expect(
            try await LBArtClient(playlistMock).playlistArtwork(
                playlistMBID: UUID(),
                dimension: 1,
                layout: .zero
            ) == genericExpected
        )
        #expect(playlistMock.request is PlaylistArtworkRequest)

        let customMock = MockAPIClient(result: .success(genericExpected))
        #expect(
            try await LBArtClient(customMock).customGrid(
                items: .releases([UUID()]),
                dimension: 1,
                layout: .zero
            ) == genericExpected
        )
        #expect(customMock.request is CustomGridArtworkRequest)
    }

    private func makeURLRequest<Request: APIRequest>(
        _ request: Request
    ) throws -> URLRequest {
        try ListenBrainzAPIClient(
            token: "",
            root: root,
            userAgent: "Tests"
        ).makeURLRequest(request)
    }

    private func queryValues(_ components: URLComponents) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
                guard let value = $0.value else { return nil }
                return ($0.name, value)
            }
        )
    }
}
