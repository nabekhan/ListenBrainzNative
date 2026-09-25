import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class ListenInspectionTests: XCTestCase {
    func testInspectionKeepsSubmittedAndResolvedMetadataSeparate() throws {
        let metadata = try decodeMetadata("""
        {
          "artist_name": "Submitted Artist", "track_name": "Submitted Track", "release_name": "Submitted Release",
          "additional_info": {
            "artist_mbids": ["934c97a5-3d4d-4c8b-a4ea-7bde1bd6f4cc"],
            "recording_mbid": "4262dc8a-97b3-4db7-8ea0-e4fbba9264bb",
            "release_mbid": "1390f1b7-7851-48ae-983d-eb8a48f78048",
            "track_mbid": "1f0b238b-5d0d-4013-821b-eb2f2bf177df",
            "work_mbids": ["fa3af0ab-84f3-4f0b-a3eb-b31bdf790710"],
            "tracknumber": 2, "isrc": "USXXX2600001", "spotify_id": "spotify-id",
            "tags": ["indie pop"], "media_player": "Player", "media_player_version": "2.0",
            "submission_client": "Client", "submission_client_version": "3.0",
            "music_service": "service", "music_service_name": "Service", "duration_ms": 243000,
            "origin_url": "https://user:password@untrusted.example/path?access_token=secret#private"
          },
          "mbid_mapping": {
            "artist_mbids": ["a1d4c987-9c07-4c71-8f75-6505e2e8f554"],
            "recording_mbid": "5d7c0d1c-31bd-4e4f-8ad0-8ddfa5652d58",
            "release_mbid": "3dcdd28d-d8dc-4c55-9c48-fd45cd3ad911",
            "release_group_mbid": "d4903ef0-2195-4644-bf8e-08d20d981617",
            "recording_name": "Resolved Track"
          }
        }
        """)
        let msid = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!

        let inspection = ListenBrainzProvider.inspection(metadata, msid: msid)

        XCTAssertEqual(inspection.submittedArtist, "Submitted Artist")
        XCTAssertEqual(inspection.submittedTrack, "Submitted Track")
        XCTAssertEqual(inspection.submittedRecordingMBID?.uuidString, "4262DC8A-97B3-4DB7-8EA0-E4FBBA9264BB")
        XCTAssertEqual(inspection.resolvedRecordingName, "Resolved Track")
        XCTAssertEqual(inspection.resolvedRecordingMBID?.uuidString, "5D7C0D1C-31BD-4E4F-8AD0-8DDFA5652D58")
        XCTAssertEqual(inspection.recordingMSID, msid)
        XCTAssertEqual(inspection.mappingStatus, .matchedByListenBrainz)
        XCTAssertEqual(inspection.originURL, "https://untrusted.example/path")
        XCTAssertEqual(inspection.durationMilliseconds, 243_000)
    }

    func testSubmittedMappingStatusOnlyReportsIDsWereSubmitted() {
        let inspection = inspection(resolvedRecordingMBID: nil, submittedRecordingMBID: UUID())
        XCTAssertEqual(inspection.mappingStatus, .musicBrainzIDsSubmitted)
        XCTAssertEqual(inspection.mappingStatus.title, "MusicBrainz IDs in submitted metadata")
    }

    func testSubmittedTrackIDCountsAsSubmittedMusicBrainzMetadata() {
        let inspection = inspection(
            resolvedRecordingMBID: nil,
            submittedRecordingMBID: nil,
            submittedTrackMBID: UUID()
        )
        XCTAssertEqual(inspection.mappingStatus, .musicBrainzIDsSubmitted)
    }

    func testResolvedArtistIDsIncludeArtistCreditShape() throws {
        let metadata = try decodeMetadata("""
        {
          "artist_name": "Submitted Artist", "track_name": "Submitted Track",
          "mbid_mapping": {
            "artists": [{
              "artist_credit_name": "Resolved Artist",
              "artist_mbid": "a1d4c987-9c07-4c71-8f75-6505e2e8f554",
              "join_phrase": ""
            }]
          }
        }
        """)

        let inspection = ListenBrainzProvider.inspection(metadata, msid: nil)

        XCTAssertEqual(
            inspection.resolvedArtistMBIDs,
            [UUID(uuidString: "a1d4c987-9c07-4c71-8f75-6505e2e8f554")!]
        )
        XCTAssertEqual(inspection.mappingStatus, .matchedByListenBrainz)
    }

    func testNonWebOriginIsNotRetained() {
        let metadata = LBTrackMetadata(
            artist: "Artist",
            track: "Track",
            originUrl: "file:///private/var/mobile/secret"
        )

        XCTAssertNil(ListenBrainzProvider.inspection(metadata, msid: nil).originURL)
    }

    func testPlayingNowKeepsSubmittedMSIDSeparateFromListenIdentity() throws {
        let metadata = try decodeMetadata("""
        {
          "artist_name": "Artist", "track_name": "Track",
          "additional_info": {
            "recording_msid": "70000000-0000-0000-0000-000000000001"
          }
        }
        """)

        let inspection = ListenBrainzProvider.inspection(metadata, msid: nil)

        XCTAssertNil(inspection.recordingMSID)
        XCTAssertEqual(
            inspection.submittedRecordingMSID,
            UUID(uuidString: "70000000-0000-0000-0000-000000000001")
        )
    }

    func testOldCachedListenWithoutInspectionDecodes() throws {
        let json = """
        {"recording":{"identity":{"mbid":null,"msid":"70000000-0000-0000-0000-000000000001"},"title":"Track","artistName":"Artist","artistMBIDs":[],"releaseTitle":null,"releaseMBID":null,"releaseGroupMBID":null,"artworkReleaseMBID":null,"durationMilliseconds":null,"source":null},"listenedAt":0,"insertedAt":null,"isPlayingNow":false}
        """
        let listen = try JSONDecoder().decode(Listen.self, from: Data(json.utf8))
        XCTAssertNil(listen.inspection)
        XCTAssertEqual(listen.recording.title, "Track")
    }

    func testSpotifyIDWinsOverOriginAndNormalizesToHTTPS() {
        let link = ExternalMediaLink.resolve(
            spotifyID: "spotify:track:4uLU6hMCjMI75M1A2tKUQC",
            originURL: "https://youtu.be/dQw4w9WgXcQ?tracking=discarded"
        )

        XCTAssertEqual(link?.service, .spotify)
        XCTAssertEqual(link?.url.absoluteString, "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(link?.actionTitle, "Open in Spotify")
    }

    func testRecognizedOriginsNormalizeIdentityCriticalValuesOnly() {
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&utm_source=ignored#fragment")?.url.absoluteString,
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://music.apple.com/us/album/example/123456789?i=987654321&utm=ignored")?.url.absoluteString,
            "https://music.apple.com/us/album/example/123456789?i=987654321"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://www.soundcloud.com/artist/track?si=secret")?.url.absoluteString,
            "https://soundcloud.com/artist/track"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://archive.org/details/example_item?ref=ignored")?.url.absoluteString,
            "https://archive.org/details/example_item"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://artist.bandcamp.com/track/example-track?from=discover")?.url.absoluteString,
            "https://artist.bandcamp.com/track/example-track"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=discarded")?.url.absoluteString,
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://m.soundcloud.com/%E3%82%A2%E3%83%BC%E3%83%86%E3%82%A3%E3%82%B9%E3%83%88/%E6%9B%B2?si=discarded")?.url.absoluteString,
            "https://soundcloud.com/%E3%82%A2%E3%83%BC%E3%83%86%E3%82%A3%E3%82%B9%E3%83%88/%E6%9B%B2"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://on.soundcloud.com/public-share?si=discarded")?.url.absoluteString,
            "https://on.soundcloud.com/public-share"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: "https://open.spotify.com/intl-de/track/4uLU6hMCjMI75M1A2tKUQC?si=discarded", originURL: nil)?.url.absoluteString,
            "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
        )
        XCTAssertEqual(
            ExternalMediaLink.resolve(spotifyID: nil, originURL: "https://open%2espotify.com/track/4uLU6hMCjMI75M1A2tKUQC")?.url.absoluteString,
            "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
        )
    }

    func testExternalLinksRejectArbitraryAndUnsafeOrigins() {
        let rejected = [
            "http://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC",
            "https://user:password@open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC",
            "https://open.spotify.com:444/track/4uLU6hMCjMI75M1A2tKUQC",
            "https://open.spotify.com.evil.example/track/4uLU6hMCjMI75M1A2tKUQC",
            "https://open.spotify.com%2eevil.example/track/4uLU6hMCjMI75M1A2tKUQC",
            "https://youtu.be.evil.example/dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&v=aaaaaaaaaaa",
            "https://example.org/music.mp3",
            "https://bandcamp.com/track/not-a-subdomain",
            "https://.artist.bandcamp.com/track/example",
            "https://artist..bandcamp.com/track/example",
            "https://-artist.bandcamp.com/track/example",
            "https://artist.bandcamp.com/settings/profile",
            "https://artist.bandcamp.com/%2Ftrack%2Fexample",
            "https://soundcloud.com/artist/../track",
            "https://music.apple.com/us/album/example/123456789?i=111&i=222",
        ]

        for origin in rejected {
            XCTAssertNil(ExternalMediaLink.resolve(spotifyID: nil, originURL: origin), origin)
        }
        XCTAssertNil(ExternalMediaLink.resolve(spotifyID: String(repeating: "a", count: 2_049), originURL: nil))
    }

    func testProviderMapsSameResolvedLinkToRecordingAndInspection() throws {
        let metadata = try decodeMetadata("""
        {"artist_name":"Artist","track_name":"Track","additional_info":{"spotify_id":"4uLU6hMCjMI75M1A2tKUQC","origin_url":"https://youtu.be/dQw4w9WgXcQ"}}
        """)

        let recording = ListenBrainzProvider.map(metadata, msid: nil)
        let inspection = ListenBrainzProvider.inspection(metadata, msid: nil)

        XCTAssertEqual(recording.externalLink?.url, URL(string: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"))
        XCTAssertEqual(inspection.spotifyID, "4uLU6hMCjMI75M1A2tKUQC")
    }

    func testServerStreamingRelationshipsComeFirstAndFallbacksAreDeduplicated() throws {
        let metadata = try decodeMetadata("""
        {
          "artist_name":"Artist", "track_name":"Track",
          "additional_info": {
            "spotify_id":"4uLU6hMCjMI75M1A2tKUQC",
            "origin_url":"https://youtu.be/dQw4w9WgXcQ"
          },
          "mbid_mapping": {
            "url_rels": [
              {"type":"purchase for download", "url":"https://artist.bandcamp.com/track/deferred"},
              {"type":"free streaming", "url":"https://www.deezer.com/track/3135556?utm=ignored"},
              {"type":"streaming", "url":"https://tidal.com/track/123456?tracking=ignored"},
              {"type":"streaming", "url":"https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"},
              {"type":"streaming", "url":"https://unknown.example/track/1"},
              {"type":42, "url":false}
            ]
          }
        }
        """)

        let recording = ListenBrainzProvider.map(metadata, msid: nil)
        let inspection = ListenBrainzProvider.inspection(metadata, msid: nil)
        let expected = [
            "https://www.deezer.com/track/3135556",
            "https://tidal.com/track/123456",
            "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        ]

        XCTAssertEqual(recording.externalMediaLinks.map(\.url.absoluteString), expected)
        XCTAssertEqual(inspection.spotifyID, "4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(recording.externalLink?.url.absoluteString, expected.first)
        XCTAssertEqual(recording.externalMediaLinks.map(\.service), [.deezer, .tidal, .spotify, .youTube])
    }

    func testServerRelationshipWinsWhenSubmittedFallbackConflictsForSameService() throws {
        let metadata = try decodeMetadata("""
        {
          "artist_name":"Artist", "track_name":"Track",
          "additional_info":{"spotify_id":"4uLU6hMCjMI75M1A2tKUQC"},
          "mbid_mapping":{"url_rels":[
            {"type":"streaming","url":"https://open.spotify.com/track/7H7RaiZoTNPwjNLygV4fXQ"}
          ]}
        }
        """)

        let links = ListenBrainzProvider.map(metadata, msid: nil).externalMediaLinks

        XCTAssertEqual(links.map(\.service), [.spotify])
        XCTAssertEqual(links.first?.url.absoluteString, "https://open.spotify.com/track/7H7RaiZoTNPwjNLygV4fXQ")
    }

    func testExternalRelationshipsRejectUnsafeURLsAndNonListeningTypes() throws {
        let metadata = try decodeMetadata("""
        {
          "artist_name":"Artist", "track_name":"Track",
          "mbid_mapping": {
            "url_rels": [
              {"type":"streaming", "url":"http://www.deezer.com/track/3135556"},
              {"type":"streaming", "url":"https://user:password@tidal.com/track/123456"},
              {"type":"streaming", "url":"https://www.deezer.com/track/not-an-id"},
              {"type":"streaming", "url":"https://tidal.com/album/123456"},
              {"type":"purchase for download", "url":"https://www.deezer.com/track/3135556"}
            ]
          }
        }
        """)

        XCTAssertTrue(ListenBrainzProvider.map(metadata, msid: nil).externalMediaLinks.isEmpty)
    }

    func testExternalRelationshipsBoundServerWorkAndVisibleDestinations() {
        let relationships = [
            ExternalMediaRelationship(type: "streaming", url: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"),
            ExternalMediaRelationship(type: "streaming", url: "https://youtu.be/dQw4w9WgXcQ"),
            ExternalMediaRelationship(type: "streaming", url: "https://soundcloud.com/artist/track"),
            ExternalMediaRelationship(type: "streaming", url: "https://music.apple.com/us/album/example/123456789?i=111"),
            ExternalMediaRelationship(type: "streaming", url: "https://archive.org/details/example"),
            ExternalMediaRelationship(type: "streaming", url: "https://artist.bandcamp.com/track/example"),
            ExternalMediaRelationship(type: "streaming", url: "https://www.deezer.com/track/3135556"),
            ExternalMediaRelationship(type: "streaming", url: "https://tidal.com/track/123456"),
        ] + (1 ... 32).map {
            ExternalMediaRelationship(type: "streaming", url: "https://www.deezer.com/track/\($0)")
        }

        let links = ExternalMediaLink.resolve(
            urlRelationships: relationships,
            spotifyID: nil,
            originURL: nil
        )

        XCTAssertEqual(links.count, 8)
        XCTAssertEqual(links.first?.service, .spotify)
        XCTAssertEqual(links.last?.service, .tidal)
    }

    func testExternalRelationshipsIgnoreRowsBeyondInspectionBound() {
        let relationships = (1 ... 32).map {
            ExternalMediaRelationship(type: "streaming", url: "https://www.deezer.com/track/\($0)")
        } + [
            ExternalMediaRelationship(
                type: "streaming",
                url: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
            ),
        ]

        let links = ExternalMediaLink.resolve(
            urlRelationships: relationships,
            spotifyID: nil,
            originURL: nil
        )

        XCTAssertEqual(links.map(\.service), [.deezer])
        XCTAssertEqual(links.first?.url.absoluteString, "https://www.deezer.com/track/1")
    }

    func testOlderCachedRecordingAndInspectionDecodeWithoutExternalLink() throws {
        let recordingJSON = """
        {"identity":{"mbid":null,"msid":null},"title":"Track","artistName":"Artist","artistMBIDs":[],"releaseTitle":null,"releaseMBID":null,"releaseGroupMBID":null,"artworkReleaseMBID":null,"durationMilliseconds":null,"source":null}
        """
        let inspectionJSON = """
        {"submittedArtist":"Artist","submittedTrack":"Track","submittedRelease":null,"recordingMSID":null,"submittedRecordingMSID":null,"submittedArtistMBIDs":[],"submittedRecordingMBID":null,"submittedReleaseMBID":null,"submittedReleaseGroupMBID":null,"submittedTrackMBID":null,"submittedWorkMBIDs":[],"resolvedArtistMBIDs":[],"resolvedRecordingMBID":null,"resolvedReleaseMBID":null,"resolvedReleaseGroupMBID":null,"resolvedRecordingName":null,"trackNumber":null,"isrc":null,"spotifyID":null,"tags":[],"mediaPlayer":null,"mediaPlayerVersion":null,"submissionClient":null,"submissionClientVersion":null,"musicService":null,"musicServiceName":null,"originURL":null,"durationMilliseconds":null}
        """

        XCTAssertNil(try JSONDecoder().decode(Recording.self, from: Data(recordingJSON.utf8)).externalLink)
        XCTAssertNoThrow(try JSONDecoder().decode(ListenInspection.self, from: Data(inspectionJSON.utf8)))
    }

    func testNewExternalLinksCacheKeepsLegacySingleLinkCompatible() throws {
        let recordingJSON = """
        {"identity":{"mbid":null,"msid":null},"title":"Track","artistName":"Artist","artistMBIDs":[],"releaseTitle":null,"releaseMBID":null,"releaseGroupMBID":null,"artworkReleaseMBID":null,"durationMilliseconds":null,"source":null,"externalLink":{"service":"spotify","url":"https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"},"externalLinks":[{"service":"spotify","url":"https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"},{"service":"deezer","url":"https://www.deezer.com/track/3135556"}]}
        """
        let recording = try JSONDecoder().decode(Recording.self, from: Data(recordingJSON.utf8))

        XCTAssertEqual(recording.externalLink?.service, .spotify)
        XCTAssertEqual(recording.externalMediaLinks.map(\.service), [.spotify, .deezer])
    }

    func testCanonicalExternalLinksOverrideConflictingLegacyCacheField() throws {
        let recordingJSON = """
        {"identity":{"mbid":null,"msid":null},"title":"Track","artistName":"Artist","artistMBIDs":[],"releaseTitle":null,"releaseMBID":null,"releaseGroupMBID":null,"artworkReleaseMBID":null,"durationMilliseconds":null,"source":null,"externalLink":{"service":"spotify","url":"https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"},"externalLinks":[{"service":"deezer","url":"https://www.deezer.com/track/3135556"}]}
        """

        let recording = try JSONDecoder().decode(Recording.self, from: Data(recordingJSON.utf8))

        XCTAssertEqual(recording.externalMediaLinks.map(\.service), [.deezer])
        XCTAssertEqual(recording.externalLink?.service, .deezer)
    }

    func testRecordingCacheRoundTripPersistsOnlyCanonicalExternalLinks() throws {
        let links = ExternalMediaLink.resolve(
            urlRelationships: [
                ExternalMediaRelationship(
                    type: "streaming",
                    url: "https://www.deezer.com/track/3135556"
                ),
                ExternalMediaRelationship(
                    type: "streaming",
                    url: "https://tidal.com/track/123456"
                ),
            ],
            spotifyID: nil,
            originURL: nil
        )
        let recording = Recording(
            identity: RecordingIdentity(mbid: nil, msid: nil),
            title: "Track",
            artistName: "Artist",
            artistMBIDs: [],
            releaseTitle: nil,
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: nil,
            source: nil,
            externalLinks: links
        )

        let encoded = try JSONEncoder().encode(recording)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(Recording.self, from: encoded)

        XCTAssertNil(object["externalLink"])
        XCTAssertNotNil(object["externalLinks"])
        XCTAssertEqual(decoded, recording)
    }

    func testCachedExternalLinkMustStillBeCanonicalAndMatchItsService() throws {
        let valid = """
        {"service":"spotify","url":"https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"}
        """
        let mismatched = """
        {"service":"spotify","url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ"}
        """
        let arbitrary = """
        {"service":"soundCloud","url":"https://example.org/track"}
        """

        XCTAssertEqual(
            try JSONDecoder().decode(ExternalMediaLink.self, from: Data(valid.utf8)).actionTitle,
            "Open in Spotify"
        )
        XCTAssertThrowsError(try JSONDecoder().decode(ExternalMediaLink.self, from: Data(mismatched.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ExternalMediaLink.self, from: Data(arbitrary.utf8)))
    }

    private func decodeMetadata(_ json: String) throws -> LBTrackMetadata {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LBTrackMetadata.self, from: Data(json.utf8))
    }

    private func inspection(
        resolvedRecordingMBID: UUID?,
        submittedRecordingMBID: UUID?,
        submittedTrackMBID: UUID? = nil
    ) -> ListenInspection {
        ListenInspection(
            submittedArtist: "Artist", submittedTrack: "Track", submittedRelease: nil,
            recordingMSID: nil, submittedRecordingMSID: nil, submittedArtistMBIDs: [], submittedRecordingMBID: submittedRecordingMBID,
            submittedReleaseMBID: nil, submittedReleaseGroupMBID: nil, submittedTrackMBID: submittedTrackMBID,
            submittedWorkMBIDs: [], resolvedArtistMBIDs: [], resolvedRecordingMBID: resolvedRecordingMBID,
            resolvedReleaseMBID: nil, resolvedReleaseGroupMBID: nil, resolvedRecordingName: nil,
            trackNumber: nil, isrc: nil, spotifyID: nil, tags: [], mediaPlayer: nil,
            mediaPlayerVersion: nil, submissionClient: nil, submissionClientVersion: nil,
            musicService: nil, musicServiceName: nil, originURL: nil, durationMilliseconds: nil
        )
    }
}
