// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBPlaylistServiceExportTests {
    private let playlistMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    @Test("Service exports use exact paths, visibility, and bounded responses", arguments: [
        (LBPlaylistService.spotify, "spotify", "https://open.spotify.com/playlist/abc"),
        (LBPlaylistService.appleMusic, "apple_music", "https://music.apple.com/ca/playlist/mix/pl.abc"),
        (LBPlaylistService.soundCloud, "soundcloud", "https://soundcloud.com/listener/sets/mix"),
    ])
    func requestContract(service: LBPlaylistService, pathService: String, externalURL: String) async throws {
        let mock = MockAPIClient(result: .success(
            PlaylistServiceExportResponse(externalUrl: externalURL)
        ))

        let result = try await LBCoreClient(mock).exportPlaylist(
            mbid: playlistMBID,
            to: service,
            isPublic: false
        )

        #expect(result.absoluteString == externalURL)
        let request = try #require(mock.request as? ExportPlaylistToServiceRequest)
        #expect(request.data.path == "/1/playlist/\(playlistMBID.uuidString)/export/\(pathService)")
        #expect(request.data.method == .post)
        #expect(request.data.queryItems == ["is_public": ["false"]])
        #expect(request.data.body == nil)
        #expect(request.data.statusErrors == [
            400: .badRequest,
            401: .invalidAuth,
            403: .forbidden,
            404: .notFound,
        ])
        #expect(request.data.maximumResponseBytes == 64 * 1_024)
    }

    @Test("Export responses decode the server external URL field")
    func responseDecoding() throws {
        let decoded = try JSONDecoder.ListenBrainz.decode(
            PlaylistServiceExportResponse.self,
            from: Data(#"{"external_url":"https://open.spotify.com/playlist/abc"}"#.utf8)
        )

        #expect(decoded.externalUrl == "https://open.spotify.com/playlist/abc")
    }

    @Test("Export rejects untrusted or malformed destination URLs", arguments: [
        "http://open.spotify.com/playlist/abc",
        "https://example.com/playlist/abc",
        "https://user@open.spotify.com/playlist/abc",
        "https://open.spotify.com:8443/playlist/abc",
        "https://open.spotify.com/",
        "https://open.spotify.com/playlist/abc#fragment",
        "https://open.spotify.com/track/abc",
        "https://open.spotify.com/redirect?url=https://example.com",
        "https://open.spotify.com/playlist/%2Fredirect",
    ])
    func invalidExternalURL(externalURL: String) async {
        let mock = MockAPIClient(result: .success(
            PlaylistServiceExportResponse(externalUrl: externalURL)
        ))

        await #expect(throws: LBError.invalidResponse) {
            _ = try await LBCoreClient(mock).exportPlaylist(
                mbid: playlistMBID,
                to: .spotify,
                isPublic: true
            )
        }
    }

    @Test("Service URLs cannot be swapped between providers")
    func providerHostMismatch() async {
        let mock = MockAPIClient(result: .success(
            PlaylistServiceExportResponse(
                externalUrl: "https://music.apple.com/ca/playlist/mix/pl.abc"
            )
        ))

        await #expect(throws: LBError.invalidResponse) {
            _ = try await LBCoreClient(mock).exportPlaylist(
                mbid: playlistMBID,
                to: .spotify,
                isPublic: true
            )
        }
    }

    @Test("Each provider requires its playlist URL shape", arguments: [
        (LBPlaylistService.appleMusic, "https://music.apple.com/ca/album/example/123"),
        (LBPlaylistService.soundCloud, "https://soundcloud.com/listener/tracks/example"),
    ])
    func providerPathMismatch(service: LBPlaylistService, externalURL: String) async {
        let mock = MockAPIClient(result: .success(
            PlaylistServiceExportResponse(externalUrl: externalURL)
        ))

        await #expect(throws: LBError.invalidResponse) {
            _ = try await LBCoreClient(mock).exportPlaylist(
                mbid: playlistMBID,
                to: service,
                isPublic: true
            )
        }
    }
}
