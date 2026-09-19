// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBPlaylistMutationTests {
    private let playlistMBID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let firstRecordingMBID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let secondRecordingMBID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!

    @Test("Playlist creation encodes empty and MBID-populated JSPF bodies")
    func createRequestBody() async throws {
        let metadata = LBPlaylistMutationMetadata(
            title: "A careful mix",
            annotation: "Kept in full",
            isPublic: false,
            collaborators: ["alice", "bob"]
        )
        let response = PlaylistCreateResponse(status: "ok", playlistMBID: playlistMBID)

        let emptyMock = MockAPIClient(result: .success(response))
        let emptyID = try await LBCoreClient(emptyMock).createPlaylist(metadata: metadata)
        #expect(emptyID == playlistMBID)
        let emptyRequest = try #require(emptyMock.request as? CreatePlaylistRequest)
        #expect(emptyRequest.data.path == "/1/playlist/create")
        #expect(emptyRequest.data.method == .post)
        #expect(emptyRequest.data.statusErrors == createStatusErrors)
        let emptyPlaylist = try playlistJSON(emptyRequest.data.body)
        #expect(emptyPlaylist["title"] as? String == "A careful mix")
        #expect(emptyPlaylist["annotation"] as? String == "Kept in full")
        #expect(emptyPlaylist["track"] == nil)
        #expect(playlistExtension(emptyPlaylist)["public"] as? Bool == false)
        #expect(playlistExtension(emptyPlaylist)["collaborators"] as? [String] == ["alice", "bob"])

        let populatedMock = MockAPIClient(result: .success(response))
        _ = try await LBCoreClient(populatedMock).createPlaylist(
            metadata: metadata,
            recordingMBIDs: [firstRecordingMBID, secondRecordingMBID]
        )
        let populatedRequest = try #require(populatedMock.request as? CreatePlaylistRequest)
        let populatedPlaylist = try playlistJSON(populatedRequest.data.body)
        let tracks = try #require(populatedPlaylist["track"] as? [[String: [String]]])
        #expect(tracks.map { $0["identifier"] } == [
            ["https://musicbrainz.org/recording/\(firstRecordingMBID.uuidString)"],
            ["https://musicbrainz.org/recording/\(secondRecordingMBID.uuidString)"],
        ])
    }

    @Test("Playlist edits encode the complete snapshot and safely clear annotation")
    func editRequestBody() async throws {
        let metadata = LBPlaylistMutationMetadata(
            title: "Retitled mix",
            annotation: nil,
            isPublic: true,
            collaborators: []
        )
        let mock = MockAPIClient(result: .success(PlaylistMutationResponse(status: "ok")))

        try await LBCoreClient(mock).editPlaylist(mbid: playlistMBID, metadata: metadata)

        let request = try #require(mock.request as? EditPlaylistRequest)
        #expect(request.data.path == "/1/playlist/edit/\(playlistMBID.uuidString)")
        #expect(request.data.method == .post)
        #expect(request.data.statusErrors == editStatusErrors)
        let playlist = try playlistJSON(request.data.body)
        #expect(playlist["title"] as? String == "Retitled mix")
        #expect(playlist["annotation"] is NSNull)
        #expect(playlistExtension(playlist)["public"] as? Bool == true)
        #expect(playlistExtension(playlist)["collaborators"] as? [String] == [])
        #expect(playlist["track"] == nil)
    }

    @Test("Playlist mutation maps server results and rejects unexpected success payloads")
    func resultHandling() async throws {
        let metadata = LBPlaylistMutationMetadata(title: "A mix", isPublic: true)
        let decodedCreate = try JSONDecoder.ListenBrainz.decode(
            PlaylistCreateResponse.self,
            from: Data(#"{"status":"ok","playlist_mbid":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#.utf8)
        )
        #expect(decodedCreate.status == "ok")
        #expect(decodedCreate.playlistMBID == playlistMBID)

        let invalidCreate = MockAPIClient(result: .success(
            PlaylistCreateResponse(status: "queued", playlistMBID: playlistMBID)
        ))
        await #expect(throws: LBError.invalidResponse) {
            _ = try await LBCoreClient(invalidCreate).createPlaylist(metadata: metadata)
        }

        let invalidEdit = MockAPIClient(result: .success(PlaylistMutationResponse(status: "queued")))
        await #expect(throws: LBError.invalidResponse) {
            try await LBCoreClient(invalidEdit).editPlaylist(mbid: playlistMBID, metadata: metadata)
        }
    }

    @Test("Playlist mutations reject server-invalid local metadata before transport")
    func localValidation() async {
        let emptyTitle = LBPlaylistMutationMetadata(title: " \n ", isPublic: true)
        let invalidCollaborator = LBPlaylistMutationMetadata(
            title: "Valid", isPublic: true, collaborators: ["listener", "  "]
        )
        let mock = MockAPIClient(result: .failure(.unknownError))

        await #expect(throws: LBError.invalidParam) {
            _ = try await LBCoreClient(mock).createPlaylist(metadata: emptyTitle)
        }
        #expect(mock.request == nil)
        await #expect(throws: LBError.invalidParam) {
            try await LBCoreClient(mock).editPlaylist(mbid: playlistMBID, metadata: invalidCollaborator)
        }
        #expect(mock.request == nil)
    }

    @Test("Playlist append uses its exact JSPF endpoint and validates item limits")
    func appendRequestBody() async throws {
        let mock = MockAPIClient(result: .success(PlaylistMutationResponse(status: "ok")))
        try await LBCoreClient(mock).addPlaylistItems(
            mbid: playlistMBID,
            recordingMBIDs: [firstRecordingMBID, secondRecordingMBID]
        )
        let request = try #require(mock.request as? AddPlaylistItemsRequest)
        #expect(request.data.path == "/1/playlist/\(playlistMBID.uuidString)/item/add")
        #expect(request.data.method == .post)
        #expect(request.data.statusErrors == addStatusErrors)
        let body = try #require(request.data.body)
        let data = try JSONEncoder.ListenBrainz.encode(body)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let playlist = try #require(root["playlist"] as? [String: Any])
        let tracks = try #require(playlist["track"] as? [[String: [String]]])
        #expect(tracks.map { $0["identifier"] } == [
            ["https://musicbrainz.org/recording/\(firstRecordingMBID.uuidString)"],
            ["https://musicbrainz.org/recording/\(secondRecordingMBID.uuidString)"],
        ])

        let invalid = MockAPIClient(result: .failure(.unknownError))
        await #expect(throws: LBError.invalidParam) {
            try await LBCoreClient(invalid).addPlaylistItems(mbid: playlistMBID, recordingMBIDs: [])
        }
        #expect(invalid.request == nil)
        await #expect(throws: LBError.invalidParam) {
            try await LBCoreClient(invalid).addPlaylistItems(
                mbid: playlistMBID,
                recordingMBIDs: Array(repeating: firstRecordingMBID, count: 101)
            )
        }
        #expect(invalid.request == nil)

        let unexpectedStatus = MockAPIClient(result: .success(
            PlaylistMutationResponse(status: "queued")
        ))
        await #expect(throws: LBError.invalidResponse) {
            try await LBCoreClient(unexpectedStatus).addPlaylistItems(
                mbid: playlistMBID,
                recordingMBIDs: [firstRecordingMBID]
            )
        }
    }

    @Test("Playlist copy uses an empty one-shot POST and returns the new MBID")
    func copyRequest() async throws {
        let copiedMBID = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
        let decoded = try JSONDecoder.ListenBrainz.decode(
            PlaylistCopyResponse.self,
            from: Data(#"{"status":"ok","playlist_mbid":"dddddddd-dddd-4ddd-8ddd-dddddddddddd"}"#.utf8)
        )
        #expect(decoded.playlistMBID == copiedMBID)

        let mock = MockAPIClient(result: .success(decoded))
        let result = try await LBCoreClient(mock).copyPlaylist(mbid: playlistMBID)

        #expect(result == copiedMBID)
        let request = try #require(mock.request as? CopyPlaylistRequest)
        #expect(request.data.path == "/1/playlist/\(playlistMBID.uuidString)/copy")
        #expect(request.data.method == .post)
        #expect(request.data.body == nil)
        #expect(request.data.statusErrors == copyStatusErrors)

        let unexpectedStatus = MockAPIClient(result: .success(
            PlaylistCopyResponse(status: "queued", playlistMBID: copiedMBID)
        ))
        await #expect(throws: LBError.invalidResponse) {
            _ = try await LBCoreClient(unexpectedStatus).copyPlaylist(mbid: playlistMBID)
        }
    }

    private func playlistJSON(_ body: PlaylistMutationBody?) throws -> [String: Any] {
        let body = try #require(body)
        let data = try JSONEncoder.ListenBrainz.encode(body)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["playlist"] as? [String: Any])
    }

    private func playlistExtension(_ playlist: [String: Any]) -> [String: Any] {
        let extensions = playlist["extension"] as? [String: Any]
        return extensions?["https://musicbrainz.org/doc/jspf#playlist"] as? [String: Any] ?? [:]
    }

    private let createStatusErrors: [Int: LBError] = [
        400: .invalidJSON,
        401: .invalidAuth,
        403: .forbidden,
    ]
    private let editStatusErrors: [Int: LBError] = [
        400: .invalidJSON,
        401: .invalidAuth,
        403: .forbidden,
        404: .notFound,
    ]
    private let addStatusErrors: [Int: LBError] = [
        400: .invalidJSON,
        401: .invalidAuth,
        403: .forbidden,
        404: .notFound,
    ]
    private let copyStatusErrors: [Int: LBError] = [
        400: .badRequest,
        401: .invalidAuth,
        403: .forbidden,
        404: .notFound,
    ]
}
