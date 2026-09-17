// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBPlaylistTests {
    private let playlistMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

    @Test("Playlist detail decodes JSPF metadata and tracks")
    func playlistDetail() async throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            RawSinglePlaylistResponse.self,
            from: Data(Self.completeFixture.utf8)
        )
        let mock = MockAPIClient(result: .success(response))
        let playlist = try await LBCoreClient(mock).playlist(mbid: playlistMBID)

        #expect(playlist.mbid == playlistMBID)
        #expect(playlist.metadata.title == "Night drive")
        #expect(playlist.metadata.creator == "listener")
        #expect(playlist.metadata.isPublic)
        #expect(playlist.metadata.date != nil)
        #expect(playlist.metadata.lastModifiedAt != nil)
        #expect(playlist.metadata.copiedFrom == "https://listenbrainz.org/playlist/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        #expect(playlist.tracks.count == 1)

        let track = try #require(playlist.tracks.first)
        #expect(track.title == "A track")
        #expect(track.artistCreditName == "An Artist")
        #expect(track.releaseName == "An Album")
        #expect(track.durationMilliseconds == 213_000)
        #expect(track.recordingMBID == UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
        #expect(track.releaseMBID == UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd"))
        #expect(track.artistMBIDs == [UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!])
        #expect(track.caaReleaseMBID == UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff"))
        #expect(track.caaID == 42)
        #expect(track.addedAt != nil)
        #expect(track.addedBy == "curator")

        let request = try #require(mock.request as? PlaylistRequest)
        #expect(request.data.path == "/1/playlist/\(playlistMBID.uuidString)")
        #expect(request.data.method == .get)
        #expect(request.data.queryItems["fetch_metadata"] == ["true"])
        #expect(request.data.statusErrors[401] == .invalidAuth)
        #expect(request.data.statusErrors[404] == .notFound)
    }

    @Test("Playlist detail can explicitly skip server metadata lookup")
    func playlistWithoutMetadata() async throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            RawSinglePlaylistResponse.self,
            from: Data(Self.unmappedFixture.utf8)
        )
        let mock = MockAPIClient(result: .success(response))
        let playlist = try await LBCoreClient(mock).playlist(
            mbid: playlistMBID,
            fetchMetadata: false
        )

        let track = try #require(playlist.tracks.first)
        #expect(track.title == nil)
        #expect(track.artistCreditName == nil)
        #expect(track.recordingMBID == UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
        let request = try #require(mock.request as? PlaylistRequest)
        #expect(request.data.queryItems["fetch_metadata"] == ["false"])
    }

    @Test("Playlist track identity ignores noncanonical MusicBrainz URLs")
    func rejectsNoncanonicalTrackIdentity() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            RawSinglePlaylistResponse.self,
            from: Data(Self.noncanonicalFixture.utf8)
        )
        let track = try #require(response.playlist.track.first)
        let mapped = LBPlaylistTrack(raw: track)

        #expect(mapped.recordingMBID == nil)
        #expect(mapped.releaseMBID == nil)
        #expect(mapped.artistMBIDs.isEmpty)
    }

    private static let completeFixture = #"""
    {
      "playlist": {
        "creator": "listener",
        "title": "Night drive",
        "annotation": "After-dark favorites",
        "identifier": "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "date": "2026-09-17T12:00:00.123456+00:00",
        "extension": {
          "https://musicbrainz.org/doc/jspf#playlist": {
            "public": true,
            "creator": "listener",
            "last_modified_at": "2026-09-17T13:00:00+00:00",
            "copied_from_mbid": "https://listenbrainz.org/playlist/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
          }
        },
        "track": [{
          "title": "A track",
          "creator": "An Artist",
          "album": "An Album",
          "duration": 213000,
          "identifier": ["https://musicbrainz.org/recording/cccccccc-cccc-4ccc-8ccc-cccccccccccc"],
          "extension": {
            "https://musicbrainz.org/doc/jspf#track": {
              "artist_identifiers": ["https://musicbrainz.org/artist/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"],
              "release_identifier": "https://musicbrainz.org/release/dddddddd-dddd-4ddd-8ddd-dddddddddddd",
              "added_at": "2026-09-17T12:30:00.000000+00:00",
              "added_by": "curator",
              "additional_metadata": {
                "caa_release_mbid": "ffffffff-ffff-4fff-8fff-ffffffffffff",
                "caa_id": 42
              }
            }
          }
        }]
      }
    }
    """#

    private static let unmappedFixture = #"""
    {
      "playlist": {
        "creator": "listener",
        "title": "Unmapped",
        "identifier": "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "extension": {
          "https://musicbrainz.org/doc/jspf#playlist": {"public": true}
        },
        "track": [{
          "identifier": ["https://musicbrainz.org/recording/cccccccc-cccc-4ccc-8ccc-cccccccccccc"]
        }]
      }
    }
    """#

    private static let noncanonicalFixture = #"""
    {
      "playlist": {
        "creator": "listener",
        "title": "Unsafe identifiers",
        "identifier": "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "extension": {
          "https://musicbrainz.org/doc/jspf#playlist": {"public": true}
        },
        "track": [{
          "identifier": ["https://example.com/recording/cccccccc-cccc-4ccc-8ccc-cccccccccccc"],
          "extension": {
            "https://musicbrainz.org/doc/jspf#track": {
              "artist_identifiers": ["https://musicbrainz.org/artist/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee/extra"],
              "release_identifier": "http://musicbrainz.org/release/dddddddd-dddd-4ddd-8ddd-dddddddddddd"
            }
          }
        }]
      }
    }
    """#
}
