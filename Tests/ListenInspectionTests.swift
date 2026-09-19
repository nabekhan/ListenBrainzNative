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
