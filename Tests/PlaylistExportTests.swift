import Foundation
import XCTest

@testable import Brainz

final class PlaylistExportTests: XCTestCase {
    func testExportIsDeterministicStandardsShapedJSPF() throws {
        let detail = playlistDetail()

        let first = try PlaylistJSPFEncoder.data(for: detail)
        let second = try PlaylistJSPFEncoder.data(for: detail)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.last, 0x0A)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: first) as? [String: Any]
        )
        let playlist = try XCTUnwrap(root["playlist"] as? [String: Any])
        XCTAssertEqual(playlist["title"] as? String, "Night / drive — favorites")
        XCTAssertEqual(playlist["creator"] as? String, "listener")
        XCTAssertEqual(playlist["annotation"] as? String, "One line\nTwo lines")
        XCTAssertEqual(
            playlist["identifier"] as? String,
            "https://listenbrainz.org/playlist/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        )
        XCTAssertEqual(playlist["date"] as? String, "2023-11-14T22:13:20.000Z")

        let extensions = try XCTUnwrap(playlist["extension"] as? [String: Any])
        let listenBrainz = try XCTUnwrap(
            extensions["https://musicbrainz.org/doc/jspf#playlist"] as? [String: Any]
        )
        XCTAssertEqual(listenBrainz["creator"] as? String, "listener")
        XCTAssertEqual(listenBrainz["public"] as? Bool, false)
        XCTAssertEqual(listenBrainz["created_for"] as? String, "listener")
        XCTAssertEqual(listenBrainz["collaborators"] as? [String], ["friend", "FRIEND"])
        XCTAssertEqual(
            listenBrainz["copied_from"] as? String,
            "https://listenbrainz.org/playlist/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        )
        XCTAssertEqual(
            listenBrainz["copied_from_mbid"] as? String,
            "https://listenbrainz.org/playlist/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        )
        XCTAssertEqual(
            listenBrainz["last_modified_at"] as? String,
            "2023-11-14T23:13:20.000Z"
        )
    }

    func testExportPreservesOrderAndDuplicateOccurrences() throws {
        let data = try PlaylistJSPFEncoder.data(for: playlistDetail())
        let tracks = try decodedTracks(from: data)

        XCTAssertEqual(tracks.count, 3)
        XCTAssertEqual(tracks.compactMap { $0["title"] as? String }, ["First", "First", "Unmapped"])

        let firstIdentifier = try XCTUnwrap(tracks[0]["identifier"] as? [String])
        let duplicateIdentifier = try XCTUnwrap(tracks[1]["identifier"] as? [String])
        XCTAssertEqual(firstIdentifier, duplicateIdentifier)
        XCTAssertEqual(
            firstIdentifier,
            ["https://musicbrainz.org/recording/cccccccc-cccc-4ccc-8ccc-cccccccccccc"]
        )
        XCTAssertNil(tracks[2]["identifier"])
        XCTAssertNil(tracks[2]["duration"])
        XCTAssertNil(tracks[2]["extension"])
    }

    func testTrackExportIncludesOnlyCanonicalKnownMetadata() throws {
        let tracks = try decodedTracks(from: PlaylistJSPFEncoder.data(for: playlistDetail()))
        let first = tracks[0]
        XCTAssertEqual(first["album"] as? String, "Release")
        XCTAssertEqual(first["creator"] as? String, "Artist")
        XCTAssertEqual(first["duration"] as? Int, 213_000)

        let extensions = try XCTUnwrap(first["extension"] as? [String: Any])
        let listenBrainz = try XCTUnwrap(
            extensions["https://musicbrainz.org/doc/jspf#track"] as? [String: Any]
        )
        XCTAssertEqual(
            listenBrainz["artist_identifiers"] as? [String],
            ["https://musicbrainz.org/artist/dddddddd-dddd-4ddd-8ddd-dddddddddddd"]
        )
        XCTAssertEqual(
            listenBrainz["release_identifier"] as? String,
            "https://musicbrainz.org/release/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        )
        XCTAssertEqual(listenBrainz["added_by"] as? String, "curator")
        XCTAssertEqual(listenBrainz["added_at"] as? String, "2023-11-14T22:30:00.000Z")
    }

    func testEmptyPlaylistExportsAnEmptyOrderedTrackArray() throws {
        let detail = playlistDetail(tracks: [])
        let tracks = try decodedTracks(from: PlaylistJSPFEncoder.data(for: detail))
        XCTAssertTrue(tracks.isEmpty)
    }

    func testInvalidCopiedFromValueIsNotExported() throws {
        let detail = playlistDetail(copiedFrom: "https://example.com/playlist/not-listenbrainz")
        let data = try PlaylistJSPFEncoder.data(for: detail)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let playlist = try XCTUnwrap(root["playlist"] as? [String: Any])
        let extensions = try XCTUnwrap(playlist["extension"] as? [String: Any])
        let listenBrainz = try XCTUnwrap(
            extensions["https://musicbrainz.org/doc/jspf#playlist"] as? [String: Any]
        )
        XCTAssertNil(listenBrainz["copied_from"])
        XCTAssertNil(listenBrainz["copied_from_mbid"])
    }

    func testShareFileNameIsBoundedAndCannotCreateAPath() {
        let title = String(repeating: "../Very long mix 🎧 ", count: 20)
        let item = PlaylistJSPFShareItem(detail: playlistDetail(title: title))

        XCTAssertTrue(item.fileName.hasSuffix(".jspf.json"))
        XCTAssertLessThanOrEqual(item.fileName.utf8.count, 190)
        XCTAssertFalse(item.fileName.contains("/"))
        XCTAssertFalse(item.fileName.contains(".."))
    }

    func testShareFileNameBoundsMultibyteLettersByUTF8Size() {
        let title = String(repeating: "界", count: 200)
        let item = PlaylistJSPFShareItem(detail: playlistDetail(title: title))

        XCTAssertTrue(item.fileName.hasSuffix(".jspf.json"))
        XCTAssertLessThanOrEqual(item.fileName.utf8.count, 190)
        XCTAssertTrue(item.fileName.hasPrefix("界"))
    }

    func testShareFileNameReadsOnlyABoundedPrefixOfAHostileTitle() {
        let title = String(repeating: "\u{0000}", count: 1_000_000)
        let item = PlaylistJSPFShareItem(detail: playlistDetail(title: title))

        XCTAssertEqual(item.fileName, "ListenBrainz-playlist.jspf.json")
        XCTAssertLessThanOrEqual(item.fileName.utf8.count, 190)
    }

    func testOversizedPlaylistFailsBeforeEncoding() {
        let repeated = track(position: 1, title: "Track", mapped: true)
        let detail = playlistDetail(
            tracks: Array(
                repeating: repeated,
                count: PlaylistJSPFEncoder.maximumTrackCount + 1
            )
        )

        XCTAssertThrowsError(try PlaylistJSPFEncoder.data(for: detail)) { error in
            XCTAssertEqual(error as? PlaylistExportError, .tooLarge)
        }
    }

    func testArtistIdentifierCardinalityIsIncludedInExportPreflight() {
        let artist = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
        let artists = Array(repeating: artist, count: 400_000)
        let oversizedTrack = track(
            position: 1,
            title: "Track",
            mapped: true,
            artistMBIDs: artists
        )

        XCTAssertThrowsError(try PlaylistJSPFEncoder.data(for: playlistDetail(tracks: [oversizedTrack]))) { error in
            XCTAssertEqual(error as? PlaylistExportError, .tooLarge)
        }
    }

    func testControlHeavyTextIsConservativelyRejectedBeforeEncoding() {
        let controlHeavyTitle = String(repeating: "\u{0000}\"\\\n", count: 1_200_000)

        XCTAssertThrowsError(
            try PlaylistJSPFEncoder.data(for: playlistDetail(title: controlHeavyTitle))
        ) { error in
            XCTAssertEqual(error as? PlaylistExportError, .tooLarge)
        }
    }

    func testStagingWritesProtectedJSONAndPrunesOnlyStaleDirectories() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "PlaylistExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let stale = root.appending(path: "stale", directoryHint: .isDirectory)
        let recent = root.appending(path: "recent", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stale, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: recent, withIntermediateDirectories: false)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-(25 * 60 * 60))],
            ofItemAtPath: stale.path
        )
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-(23 * 60 * 60))],
            ofItemAtPath: recent.path
        )

        let item = PlaylistJSPFShareItem(detail: playlistDetail())
        let staged = try PlaylistExportStaging.stage(
            item,
            in: root,
            now: now,
            fileManager: fileManager
        )

        XCTAssertTrue(fileManager.fileExists(atPath: staged.path))
        XCTAssertFalse(fileManager.fileExists(atPath: stale.path))
        XCTAssertTrue(fileManager.fileExists(atPath: recent.path))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: staged)))
    }

    private func decodedTracks(from data: Data) throws -> [[String: Any]] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let playlist = try XCTUnwrap(root["playlist"] as? [String: Any])
        return try XCTUnwrap(playlist["track"] as? [[String: Any]])
    }

    private func playlistDetail(
        title: String = "Night / drive — favorites",
        copiedFrom: String? = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        tracks: [PlaylistTrack]? = nil
    ) -> PlaylistDetail {
        PlaylistDetail(
            mbid: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            title: title,
            creator: "listener",
            annotation: "One line\nTwo lines",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastModifiedAt: Date(timeIntervalSince1970: 1_700_003_600),
            isPublic: false,
            createdFor: "listener",
            collaborators: [" friend ", "", "FRIEND"],
            copiedFrom: copiedFrom,
            tracks: tracks ?? [
                track(position: 1, title: "First", mapped: true),
                track(position: 2, title: "First", mapped: true),
                track(position: 3, title: "Unmapped", mapped: false),
            ]
        )
    }

    private func track(
        position: Int,
        title: String,
        mapped: Bool,
        artistMBIDs: [UUID]? = nil
    ) -> PlaylistTrack {
        PlaylistTrack(
            position: position,
            recording: Recording(
                identity: .init(
                    mbid: mapped
                        ? UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
                        : nil,
                    msid: nil
                ),
                title: title,
                artistName: mapped ? "Artist" : "Unknown artist",
                artistMBIDs: artistMBIDs ?? (mapped
                    ? [UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!]
                    : []),
                releaseTitle: mapped ? "Release" : "   ",
                releaseMBID: mapped
                    ? UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
                    : nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: mapped ? 213_000 : -1,
                source: nil
            ),
            addedAt: mapped ? Date(timeIntervalSince1970: 1_700_001_000) : nil,
            addedBy: mapped ? " curator " : "   "
        )
    }
}
