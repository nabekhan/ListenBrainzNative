// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBCoreTests {
    @Test("searchUser gets a list of users")
    func searchUser() async throws {
        let mockRes = SearchUserRequest
            .Result(users: [.init(userName: "abc"),
                            .init(userName: "def")])
        let client = LBCoreClient(MockAPIClient(result: .success(mockRes)))

        #expect(try await client.searchUser(term: "") == ["abc", "def"])
        let request = try #require((client.apiClient as? MockAPIClient)?.request as? SearchUserRequest)
        #expect(request.data.path == "/1/search/users/")
        #expect(request.data.preservesTrailingSlash)
    }

    @Test("Public playlist search uses the generic search endpoint and clamps paging")
    func searchPlaylists() async throws {
        let client = LBCoreClient(MockAPIClient(result: .success(
            RawPlaylistResponse(playlists: [])
        )))

        let playlists = try await client.searchPlaylists(query: "ambient", count: 400, offset: -9)

        #expect(playlists.isEmpty)
        let request = try #require((client.apiClient as? MockAPIClient)?.request as? SearchPlaylistsRequest)
        #expect(request.data.path == "/1/playlist/search")
        #expect(request.data.queryItems["query"] == ["ambient"])
        #expect(request.data.queryItems["count"] == ["100"])
        #expect(request.data.queryItems["offset"] == ["0"])
    }

    @Test("Public playlist search rejects short queries before transport")
    func searchPlaylistsRejectsShortQuery() async {
        let mock = MockAPIClient(result: .success(RawPlaylistResponse(playlists: [])))
        let client = LBCoreClient(mock)

        await #expect(throws: LBError.invalidParam) {
            _ = try await client.searchPlaylists(query: " ab ")
        }
        #expect(mock.request == nil)
    }

    @Test("User playlist page retains pagination metadata and legacy list API")
    func userPlaylistsPage() async throws {
        let mock = MockAPIClient(result: .success(try playlistPageResponse(requestedCount: 10)))
        let client = LBCoreClient(mock)

        let page = try await client.userPlaylistsPage(username: "listener", count: 10, offset: 20)

        #expect(page.requestedCount == 10)
        #expect(page.offset == 20)
        #expect(page.playlistCount == 42)
        #expect(page.playlists.count == 1)
        #expect(page.playlists.map(\.title) == ["Quiet records"])
        let request = try #require(mock.request as? UserPlaylistsRequest)
        #expect(request.data.path == "/1/user/listener/playlists")
        #expect(request.data.queryItems["count"] == ["10"])
        #expect(request.data.queryItems["offset"] == ["20"])
        #expect(request.data.statusErrors[404] == .notFound)

        let legacyMock = MockAPIClient(result: .success(try playlistPageResponse(requestedCount: 10)))
        let legacy = try await LBCoreClient(legacyMock).userPlaylists(
            username: "listener", count: 10, offset: 20
        )
        #expect(legacy.map(\.title) == page.playlists.map(\.title))
    }

    @Test("User playlist page tolerates absent pagination and omits default query items")
    func userPlaylistsPageWithoutPaginationMetadata() async throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            RawPlaylistResponse.self,
            from: Data(#"{"playlists": []}"#.utf8)
        )
        let mock = MockAPIClient(result: .success(response))

        let page = try await LBCoreClient(mock).userPlaylistsPage(username: "listener")

        #expect(page.playlists.isEmpty)
        #expect(page.requestedCount == nil)
        #expect(page.offset == nil)
        #expect(page.playlistCount == nil)
        let request = try #require(mock.request as? UserPlaylistsRequest)
        #expect(request.data.queryItems["count"] == nil)
        #expect(request.data.queryItems["offset"] == nil)
    }

    @Test("Created-for playlist page preserves endpoint pagination")
    func userPlaylistsCreatedForPage() async throws {
        let mock = MockAPIClient(result: .success(try playlistPageResponse(requestedCount: 5)))
        let page = try await LBCoreClient(mock).userPlaylistsCreatedForPage(
            username: "listener", count: 5, offset: 15
        )

        #expect(page.requestedCount == 5)
        #expect(page.offset == 20)
        #expect(page.playlistCount == 42)
        let request = try #require(mock.request as? UserPlaylistsCreatedForRequest)
        #expect(request.data.path == "/1/user/listener/playlists/createdfor")
        #expect(request.data.queryItems["count"] == ["5"])
        #expect(request.data.queryItems["offset"] == ["15"])
        #expect(request.data.statusErrors[404] == .notFound)
    }

    @Test("Collaborator playlist page preserves endpoint pagination")
    func userPlaylistsCollaboratorPage() async throws {
        let mock = MockAPIClient(result: .success(try playlistPageResponse(requestedCount: 25)))
        let page = try await LBCoreClient(mock).userPlaylistsCollaboratorPage(
            username: "listener", count: 25, offset: 40
        )

        #expect(page.requestedCount == 25)
        #expect(page.offset == 20)
        #expect(page.playlistCount == 42)
        let request = try #require(mock.request as? UserPlaylistsCollaboratorRequest)
        #expect(request.data.path == "/1/user/listener/playlists/collaborator")
        #expect(request.data.queryItems["count"] == ["25"])
        #expect(request.data.queryItems["offset"] == ["40"])
        #expect(request.data.statusErrors[404] == .notFound)
    }

    @Test("Playlist search metadata tolerates an absent last-modified timestamp")
    func playlistMetadataWithoutLastModifiedAt() throws {
        let data = Data(#"""
        {
          "playlists": [{"playlist": {
            "creator": "listener",
            "title": "Quiet records",
            "identifier": "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "date": "2026-09-17T12:00:00.000000+00:00",
            "extension": {
              "https://musicbrainz.org/doc/jspf#playlist": {"public": true}
            },
            "track": []
          }}],
          "playlist_count": 1,
          "count": 1,
          "offset": 0
        }
        """#.utf8)

        let response = try JSONDecoder.ListenBrainz.decode(RawPlaylistResponse.self, from: data)
        let playlist = try #require(response.playlists.first?.playlist)
        let metadata = LBPlaylistMetadata(raw: playlist)
        #expect(metadata.lastModifiedAt == nil)
    }

    @Test("Playlist metadata accepts server timestamps with and without fractional seconds")
    func playlistMetadataTimestampFormats() throws {
        let data = Data(#"""
        {
          "playlists": [{"playlist": {
            "creator": "listener",
            "title": "Quiet records",
            "identifier": "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "date": "2026-09-17T12:00:00.123456+00:00",
            "extension": {
              "https://musicbrainz.org/doc/jspf#playlist": {
                "public": true,
                "last_modified_at": "2026-09-17T13:00:00+00:00"
              }
            },
            "track": []
          }}]
        }
        """#.utf8)

        let response = try JSONDecoder.ListenBrainz.decode(RawPlaylistResponse.self, from: data)
        let playlist = try #require(response.playlists.first?.playlist)
        let metadata = LBPlaylistMetadata(raw: playlist)
        #expect(metadata.date != nil)
        #expect(metadata.lastModifiedAt != nil)
    }

    @Test("Generated playlist metadata exposes source and expiry")
    func generatedPlaylistMetadata() throws {
        let data = Data(#"""
        {
          "playlists": [{"playlist": {
            "creator": "troi-bot",
            "title": "Weekly Jams for listener",
            "identifier": "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "extension": {
              "https://musicbrainz.org/doc/jspf#playlist": {
                "public": true,
                "created_for": "listener",
                "additional_metadata": {
                  "algorithm_metadata": {"source_patch": "weekly-jams"},
                  "expires_at": "2026-09-24T12:00:00+00:00"
                }
              }
            },
            "track": []
          }}]
        }
        """#.utf8)

        let response = try JSONDecoder.ListenBrainz.decode(RawPlaylistResponse.self, from: data)
        let playlist = try #require(response.playlists.first?.playlist)
        let metadata = LBPlaylistMetadata(raw: playlist)

        #expect(metadata.createdFor == "listener")
        #expect(metadata.recommendationType == "weekly-jams")
        #expect(metadata.expiresAt != nil)
    }

    private func playlistPageResponse(requestedCount: Int) throws -> RawPlaylistResponse {
        try JSONDecoder.ListenBrainz.decode(
            RawPlaylistResponse.self,
            from: Data(#"""
            {
              "count": \#(requestedCount),
              "offset": 20,
              "playlist_count": 42,
              "playlists": [{"playlist": {
                "creator": "listener",
                "title": "Quiet records",
                "identifier": "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                "extension": {
                  "https://musicbrainz.org/doc/jspf#playlist": {"public": true}
                },
                "track": []
              }}]
            }
            """#.utf8)
        )
    }

    @Test("Delete listen posts its second-granular source identity")
    func deleteListen() async throws {
        let mock = MockAPIClient(result: .success(NoResult()))
        let listenedAt = Date(timeIntervalSince1970: 1_700_000_000.9)
        let msid = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        try await LBCoreClient(mock).deleteListen(listenedAt: listenedAt, recordingMsid: msid)

        let request = try #require(mock.request as? DeleteListenRequest)
        #expect(request.data.path == "/1/delete-listen")
        #expect(request.data.method == .post)
        #expect(request.data.headers["Content-Type"] == "application/json")
        #expect(request.data.statusErrors[400] == .invalidJSON)
        #expect(request.data.statusErrors[401] == .invalidAuth)
        #expect(request.data.body?.listenedAt == 1_700_000_000)
        #expect(request.data.body?.recordingMsid == msid)
    }

    @Test("Submit multiple listens")
    func submitListens() async throws {
        let date1 = Date.now.addingTimeInterval(-300)
        let submission1 = LBListenSubmission(meta: .init(artist: "Artist",
                                                         track: "Track",
                                                         release: "Release",
                                                         additionalInfo: .init(tracknumber: 12)),
                                             listenedAt: date1)

        let date2 = Date.now.addingTimeInterval(-600)
        let submission2 = LBListenSubmission(meta: .init(artist: "Another Artist",
                                                         track: "Track 2",
                                                         release: "Another Release",
                                                         additionalInfo: .init(tracknumber: 2)),
                                             listenedAt: date2)

        let client = LBCoreClient(MockAPIClient(result: .success(NoResult())))
        _ = try await client.submitListens([submission1, submission2])

        let request = try #require(((client.apiClient
                as? MockAPIClient)?.request
            as? SubmitListensRequest)?.data.body)

        #expect(request.listenType == "import")
        #expect(request.payload.count == 2)
        let firstPayload = try #require(request.payload.first)
        #expect(firstPayload.listenedAt == date1)
        #expect(firstPayload.trackMetadata == submission1.meta)
        let secondPayload = try #require(request.payload.last)
        #expect(secondPayload.listenedAt == date2)
        #expect(secondPayload.trackMetadata == submission2.meta)
    }

    @Test("Single listen is labeled as such")
    func submitSingleListen() async throws {
        let listenDate = Date.now.addingTimeInterval(-300)
        let listenMeta: LBTrackMetadata = .init(artist: "Artist",
                                                track: "Track",
                                                release: "Release",
                                                additionalInfo: .init(tracknumber: 12))
        let client = LBCoreClient(MockAPIClient(result: .success(NoResult())))
        _ = try await client.submitListen(meta: listenMeta, at: listenDate)

        let request = try #require(((client.apiClient
                as? MockAPIClient)?.request
            as? SubmitListensRequest)?.data.body)

        #expect(request.listenType == "single")
        #expect(request.payload.count == 1)
        let onlyPayload = try #require(request.payload.first)
        #expect(onlyPayload.listenedAt == listenDate)
        #expect(onlyPayload.trackMetadata == listenMeta)
    }

    @Test("Now playing submission is labeled as such")
    func submitNowPlaying() async throws {
        let listenMeta: LBTrackMetadata = .init(artist: "Artist",
                                                track: "Track",
                                                release: "Release",
                                                additionalInfo: .init(tracknumber: 12))
        let client = LBCoreClient(MockAPIClient(result: .success(NoResult())))
        _ = try await client.submitPlayingNow(meta: listenMeta)

        let request = try #require(((client.apiClient
                as? MockAPIClient)?.request
            as? SubmitListensRequest)?.data.body)

        #expect(request.listenType == "playing_now")
        #expect(request.payload.count == 1)
        let onlyPayload = try #require(request.payload.first)
        #expect(onlyPayload.listenedAt == nil)
        #expect(onlyPayload.trackMetadata == listenMeta)
    }

    @Test("radioRecordingsByArtist results")
    func radioByArtist() async throws {
        let artistMbid = UUID(uuidString: "38f59974-2f4d-4bfa-b2e3-d2696de1b675")!
        let recordingMbid = UUID(uuidString: "f7788ef4-641f-4303-a7d5-ea786b2258df")!
        let artistName = "Lille Mix"

        let mockRes = [artistMbid.uuidString:
            [RadioArtistRequest.RadioSimilarArtistResult(
                recordingMbid: recordingMbid,
                similarArtistMbid: artistMbid,
                similarArtistName: artistName, totalListenCount: 1234
            )]]
        let client = LBCoreClient(MockAPIClient(result: .success(mockRes)))

        let result = try await client
            .radioRecordingsFromArtist(artistMbid: artistMbid,
                                       mode: .easy, maxSimilarArtists: 1,
                                       maxRecordingsPerArtist: 2, pop: 12 ... 99)

        let onlyResult = try #require(result.first)
        #expect(onlyResult.artistMbid == artistMbid)
        #expect(onlyResult.artistName == artistName)
        let onlyRecording = try #require(onlyResult.recordings.first)
        #expect(onlyRecording.recordingMbid == recordingMbid)
        #expect(onlyRecording.totalListenCount == 1234)
    }

    @Test("radioRecordings popularity range")
    func radioPopRange() async throws {
        let mockRes = [String: RadioArtistRequest.RadioSimilarArtistResult]()
        let client = LBCoreClient(MockAPIClient(result: .success(mockRes)))

        let result = try await client
            .radioRecordingsFromArtist(artistMbid: UUID(uuidString: "38f59974-2f4d-4bfa-b2e3-d2696de1b675")!,
                                       mode: .hard, maxSimilarArtists: 123,
                                       maxRecordingsPerArtist: 345, pop: -323 ... 8462)
        #expect(result.isEmpty)

        let request = try #require((client.apiClient as? MockAPIClient)?.request as? RadioArtistRequest)
        #expect(request.data.queryItems["mode"] == ["hard"])
        #expect(request.data.queryItems["max_similar_artists"] == ["123"])
        #expect(request.data.queryItems["max_recordings_per_artist"] == ["345"])
        #expect(request.data.queryItems["pop_begin"] == ["0"])
        #expect(request.data.queryItems["pop_end"] == ["100"])
    }
}
