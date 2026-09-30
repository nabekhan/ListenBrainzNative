// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBSpotifyPlaylistImportTests {
    private let spotifyID = "4NHQUGzhtTLFvgF5SZesLK"
    private let importedMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    @Test("Spotify import listing uses the authenticated bounded endpoint")
    func listRequestContract() async throws {
        let mock = MockAPIClient(result: .success(LBSpotifyPlaylistImportList(
            playlists: [try summary(id: spotifyID, title: "Morning music")],
            isTruncated: false
        )))

        let result = try await LBCoreClient(mock).spotifyPlaylistsForImport()

        #expect(result.playlists.map(\.id) == [spotifyID])
        #expect(!result.isTruncated)
        let request = try #require(mock.request as? SpotifyPlaylistImportListRequest)
        #expect(request.data.path == "/1/playlist/import/spotify")
        #expect(request.data.method == .get)
        #expect(request.data.body == nil)
        #expect(request.data.statusErrors == [
            400: .badRequest,
            401: .invalidAuth,
            403: .forbidden,
            404: .notFound,
        ])
        #expect(request.data.maximumResponseBytes == 2 * 1_024 * 1_024)
    }

    @Test("Spotify import response retains bounded summaries and trusted artwork")
    func listResponseDecoding() throws {
        let decoded = try SpotifyPlaylistImportListRequest().decodeResponse(
            Data(#"""
            [{"id":"4NHQUGzhtTLFvgF5SZesLK","name":"Morning music","description":"Wake up","collaborative":false,"public":true,"owner":{"display_name":"Listener"},"tracks":{"total":12},"images":[{"url":"https://i.scdn.co/image/cover"}]}]
            """#.utf8),
            response: nil
        )

        let playlist = try #require(decoded.playlists.first)
        #expect(playlist.id == spotifyID)
        #expect(playlist.title == "Morning music")
        #expect(playlist.description == "Wake up")
        #expect(playlist.ownerName == "Listener")
        #expect(playlist.trackCount == 12)
        #expect(playlist.isPublic == true)
        #expect(!playlist.isCollaborative)
        #expect(playlist.artworkURL?.absoluteString == "https://i.scdn.co/image/cover")
        #expect(!decoded.isTruncated)
    }

    @Test("Spotify import listing never materializes more than 100 rows")
    func listResponseRowBound() throws {
        let row = #"{"id":"4NHQUGzhtTLFvgF5SZesLK","name":"Playlist","collaborative":false}"#
        let data = Data(("[" + Array(repeating: row, count: 101).joined(separator: ",") + "]").utf8)
        let decoded = try SpotifyPlaylistImportListRequest().decodeResponse(data, response: nil)
        #expect(decoded.playlists.count == 100)
        #expect(decoded.isTruncated)
    }

    @Test("Spotify track import has a single safe opaque path segment")
    func importRequestContract() async throws {
        let mock = MockAPIClient(result: .success(SpotifyPlaylistImportResponse(identifier: importedMBID)))

        let result = try await LBCoreClient(mock).importSpotifyPlaylist(spotifyPlaylistID: spotifyID)

        #expect(result == importedMBID)
        let request = try #require(mock.request as? ImportSpotifyPlaylistTracksRequest)
        #expect(request.data.path == "/1/playlist/spotify/\(spotifyID)/tracks")
        #expect(request.data.method == .get)
        #expect(request.data.body == nil)
        #expect(request.data.statusErrors == [
            400: .badRequest,
            401: .invalidAuth,
            403: .forbidden,
            404: .notFound,
        ])
        #expect(request.data.maximumResponseBytes == 32 * 1_024 * 1_024)
        #expect(!request.data.allowsRedirects)
    }

    @Test("Spotify import rejects unsafe playlist IDs before a request")
    func rejectsUnsafeIDs() async {
        let mock = MockAPIClient(result: .success(SpotifyPlaylistImportResponse(identifier: importedMBID)))
        for value in ["", "../playlist", "abc/def", "abc?def", "abc%2Fdef", "abc-def", String(repeating: "a", count: 129)] {
            await #expect(throws: LBError.invalidParam) {
                _ = try await LBCoreClient(mock).importSpotifyPlaylist(spotifyPlaylistID: value)
            }
        }
        #expect(mock.request == nil)
    }

    @Test("Spotify playlist import decodes only the canonical created identifier")
    func importResponseDecoding() throws {
        let decoded = try JSONDecoder.ListenBrainz.decode(
            SpotifyPlaylistImportResponse.self,
            from: Data(#"{"identifier":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","track":[{"large":"ignored"}]}"#.utf8)
        )
        #expect(decoded.identifier == importedMBID)
    }

    @Test("Spotify artwork accepts only credential-free standard HTTPS URLs")
    func artworkURLValidation() throws {
        let standard = try LBSpotifyPlaylistSummary(
            id: spotifyID,
            title: "Standard",
            artworkURL: URL(string: "https://i.scdn.co/image/cover")
        )
        let explicitHTTPS = try LBSpotifyPlaylistSummary(
            id: spotifyID,
            title: "Explicit HTTPS",
            artworkURL: URL(string: "https://i.scdn.co:443/image/cover")
        )
        let nonstandardPort = try LBSpotifyPlaylistSummary(
            id: spotifyID,
            title: "Nonstandard port",
            artworkURL: URL(string: "https://i.scdn.co:444/image/cover")
        )
        let credentialed = try LBSpotifyPlaylistSummary(
            id: spotifyID,
            title: "Credentialed",
            artworkURL: URL(string: "https://listener@i.scdn.co/image/cover")
        )
        let alternateCDN = try LBSpotifyPlaylistSummary(
            id: spotifyID,
            title: "Alternate CDN",
            artworkURL: URL(string: "https://image-cdn-ak.spotifycdn.com/image/cover")
        )
        let unrelatedHost = try LBSpotifyPlaylistSummary(
            id: spotifyID,
            title: "Unrelated host",
            artworkURL: URL(string: "https://example.com/image/cover")
        )

        #expect(standard.artworkURL != nil)
        #expect(explicitHTTPS.artworkURL != nil)
        #expect(nonstandardPort.artworkURL == nil)
        #expect(credentialed.artworkURL == nil)
        #expect(alternateCDN.artworkURL != nil)
        #expect(unrelatedHost.artworkURL == nil)
    }

    private func summary(id: String, title: String) throws -> LBSpotifyPlaylistSummary {
        try LBSpotifyPlaylistSummary(raw: .init(
            id: id,
            name: title,
            description: nil,
            images: nil,
            owner: nil,
            tracks: nil,
            isPublic: nil,
            isCollaborative: false
        ))
    }
}
