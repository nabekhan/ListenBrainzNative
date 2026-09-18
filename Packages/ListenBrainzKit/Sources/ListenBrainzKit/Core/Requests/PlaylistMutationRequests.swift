// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct CreatePlaylistRequest: APIRequest {
    typealias Result = PlaylistCreateResponse

    let data: APIRequestData<PlaylistMutationBody>

    init(metadata: LBPlaylistMutationMetadata, recordingMBIDs: [UUID]) {
        data = .init(
            path: "/1/playlist/create",
            method: .post,
            body: .init(metadata: metadata, recordingMBIDs: recordingMBIDs),
            statusErrors: PlaylistMutationStatusErrors.create
        )
    }
}

struct EditPlaylistRequest: APIRequest {
    typealias Result = PlaylistMutationResponse

    let data: APIRequestData<PlaylistMutationBody>

    init(mbid: UUID, metadata: LBPlaylistMutationMetadata) {
        data = .init(
            path: "/1/playlist/edit/\(mbid.uuidString)",
            method: .post,
            body: .init(metadata: metadata, recordingMBIDs: []),
            statusErrors: PlaylistMutationStatusErrors.edit
        )
    }
}

struct AddPlaylistItemsRequest: APIRequest {
    typealias Result = PlaylistMutationResponse

    let data: APIRequestData<PlaylistAppendItemsBody>

    init(mbid: UUID, recordingMBIDs: [UUID]) {
        data = .init(
            path: "/1/playlist/\(mbid.uuidString)/item/add",
            method: .post,
            body: .init(recordingMBIDs: recordingMBIDs),
            statusErrors: PlaylistMutationStatusErrors.addItems
        )
    }
}

/// The strict JSPF subset accepted by ListenBrainz playlist create/edit APIs.
/// The server intentionally ignores non-identity track metadata during create,
/// so populated creates encode recording MBIDs only.
struct PlaylistMutationBody: Encodable {
    let metadata: LBPlaylistMutationMetadata
    let recordingMBIDs: [UUID]

    init(metadata: LBPlaylistMutationMetadata, recordingMBIDs: [UUID]) {
        self.metadata = metadata
        self.recordingMBIDs = recordingMBIDs
    }

    private enum RootKeys: String, CodingKey { case playlist }
    private enum PlaylistKeys: String, CodingKey {
        case title
        case annotation
        case extensionValue = "extension"
        case track
    }
    private enum PlaylistExtensionKeys: String, CodingKey {
        case listenBrainz = "https://musicbrainz.org/doc/jspf#playlist"
    }
    private enum ListenBrainzExtensionKeys: String, CodingKey {
        case isPublic = "public"
        case collaborators
    }
    private enum TrackKeys: String, CodingKey { case identifier }

    func encode(to encoder: any Encoder) throws {
        var root = encoder.container(keyedBy: RootKeys.self)
        var playlist = root.nestedContainer(keyedBy: PlaylistKeys.self, forKey: .playlist)
        try playlist.encode(metadata.title, forKey: .title)
        // Deliberately encode `null`: the edit endpoint uses it to clear an
        // existing annotation rather than retaining stale server state.
        try playlist.encode(metadata.annotation, forKey: .annotation)

        var extensions = playlist.nestedContainer(keyedBy: PlaylistExtensionKeys.self, forKey: .extensionValue)
        var listenBrainz = extensions.nestedContainer(
            keyedBy: ListenBrainzExtensionKeys.self,
            forKey: .listenBrainz
        )
        try listenBrainz.encode(metadata.isPublic, forKey: .isPublic)
        try listenBrainz.encode(metadata.collaborators, forKey: .collaborators)

        guard !recordingMBIDs.isEmpty else { return }
        var tracks = playlist.nestedUnkeyedContainer(forKey: .track)
        for recordingMBID in recordingMBIDs {
            var track = tracks.nestedContainer(keyedBy: TrackKeys.self)
            try track.encode(
                ["https://musicbrainz.org/recording/\(recordingMBID.uuidString)"],
                forKey: .identifier
            )
        }
    }
}

/// The append endpoint accepts a deliberately small JSPF document. It does
/// not take playlist metadata and preserves duplicate recording occurrences.
struct PlaylistAppendItemsBody: Encodable {
    let recordingMBIDs: [UUID]

    private enum RootKeys: String, CodingKey { case playlist }
    private enum PlaylistKeys: String, CodingKey { case track }
    private enum TrackKeys: String, CodingKey { case identifier }

    func encode(to encoder: any Encoder) throws {
        var root = encoder.container(keyedBy: RootKeys.self)
        var playlist = root.nestedContainer(keyedBy: PlaylistKeys.self, forKey: .playlist)
        var tracks = playlist.nestedUnkeyedContainer(forKey: .track)
        for recordingMBID in recordingMBIDs {
            var track = tracks.nestedContainer(keyedBy: TrackKeys.self)
            try track.encode(
                ["https://musicbrainz.org/recording/\(recordingMBID.uuidString)"],
                forKey: .identifier
            )
        }
    }
}

struct PlaylistCreateResponse: Decodable {
    let status: String
    let playlistMBID: UUID

    enum CodingKeys: String, CodingKey {
        case status
        // JSONDecoder.ListenBrainz uses convertFromSnakeCase, whose decoded
        // key is `playlistMbid` rather than the all-caps Swift spelling.
        case playlistMBID = "playlistMbid"
    }
}

struct PlaylistMutationResponse: Decodable {
    let status: String
}

private enum PlaylistMutationStatusErrors {
    static let create: [Int: LBError] = [
        400: .invalidJSON,
        401: .invalidAuth,
        403: .forbidden,
    ]

    static let edit: [Int: LBError] = [
        400: .invalidJSON,
        401: .invalidAuth,
        403: .forbidden,
        404: .notFound,
    ]

    static let addItems: [Int: LBError] = [
        400: .invalidJSON,
        401: .invalidAuth,
        403: .forbidden,
        404: .notFound,
    ]
}
