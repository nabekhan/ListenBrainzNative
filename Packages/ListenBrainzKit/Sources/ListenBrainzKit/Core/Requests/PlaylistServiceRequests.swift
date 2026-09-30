// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct ExportPlaylistToServiceRequest: APIRequest {
    typealias Result = PlaylistServiceExportResponse

    let data: APIRequestData<NoBody>

    init(mbid: UUID, service: LBPlaylistService, isPublic: Bool) {
        data = .init(
            path: "/1/playlist/\(mbid.uuidString)/export/\(service.rawValue)",
            method: .post,
            queryItems: ["is_public": [String(isPublic)]],
            statusErrors: [
                400: .badRequest,
                401: .invalidAuth,
                403: .forbidden,
                404: .notFound,
            ],
            maximumResponseBytes: 64 * 1_024
        )
    }
}

struct PlaylistServiceExportResponse: Decodable {
    let externalUrl: String
}

/// Lists Spotify playlists available to import. ListenBrainz returns the
/// complete upstream array without pagination, so the response is bounded in
/// bytes and only a bounded number of summaries is materialized.
struct SpotifyPlaylistImportListRequest: APIRequest {
    typealias Result = LBSpotifyPlaylistImportList

    static let maximumResponseBytes = 2 * 1_024 * 1_024
    static let maximumSummaryCount = 100

    let data: APIRequestData<NoBody>

    init() {
        data = .init(
            path: "/1/playlist/import/spotify",
            method: .get,
            statusErrors: [
                400: .badRequest,
                401: .invalidAuth,
                403: .forbidden,
                404: .notFound,
            ],
            maximumResponseBytes: Self.maximumResponseBytes
        )
    }

    func decodeResponse(_ data: Data, response: HTTPURLResponse?) throws -> LBSpotifyPlaylistImportList {
        try JSONDecoder.ListenBrainz.decode(
            SpotifyPlaylistImportListResponse.self,
            from: data
        ).value
    }
}

/// Despite using GET, this endpoint imports Spotify tracks and creates a
/// ListenBrainz playlist. It must be dispatched exactly once by a caller that
/// can reconcile an ambiguous result without automatic replay.
struct ImportSpotifyPlaylistTracksRequest: APIRequest {
    typealias Result = SpotifyPlaylistImportResponse

    /// The server returns the entire generated JSPF even though the client
    /// needs only its top-level identifier. Troi follows every Spotify page
    /// and the route declares no track-count limit, so keep a generous but
    /// finite ceiling rather than treating this as a tiny mutation envelope.
    static let maximumResponseBytes = 32 * 1_024 * 1_024

    let data: APIRequestData<NoBody>

    init(spotifyPlaylistID: String) throws {
        guard SpotifyPlaylistIdentifier.isValid(spotifyPlaylistID) else { throw LBError.invalidParam }
        data = .init(
            path: "/1/playlist/spotify/\(spotifyPlaylistID)/tracks",
            method: .get,
            statusErrors: [
                400: .badRequest,
                401: .invalidAuth,
                403: .forbidden,
                404: .notFound,
            ],
            maximumResponseBytes: Self.maximumResponseBytes,
            allowsRedirects: false
        )
    }
}

struct SpotifyPlaylistImportResponse: Decodable {
    let identifier: UUID
}

private struct SpotifyPlaylistImportListResponse: Decodable {
    let value: LBSpotifyPlaylistImportList

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        var playlists: [LBSpotifyPlaylistSummary] = []
        var isTruncated = false
        playlists.reserveCapacity(min(values.count ?? 0, SpotifyPlaylistImportListRequest.maximumSummaryCount))

        while !values.isAtEnd {
            if playlists.count < SpotifyPlaylistImportListRequest.maximumSummaryCount {
                playlists.append(try LBSpotifyPlaylistSummary(raw: values.decode(LBSpotifyPlaylistSummary.Raw.self)))
            } else {
                isTruncated = true
                _ = try values.decode(DiscardedSpotifyJSON.self)
            }
        }
        value = LBSpotifyPlaylistImportList(
            playlists: playlists,
            isTruncated: isTruncated
        )
    }
}

/// Consumes unreturned rows without retaining a second typed playlist model.
private struct DiscardedSpotifyJSON: Decodable {
    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            return
        } else if (try? single.decode(Bool.self)) != nil {
            return
        } else if (try? single.decode(Double.self)) != nil {
            return
        } else if (try? single.decode(String.self)) != nil {
            return
        } else if var array = try? decoder.unkeyedContainer() {
            while !array.isAtEnd { _ = try array.decode(DiscardedSpotifyJSON.self) }
        } else {
            let object = try decoder.container(keyedBy: AnyCodingKey.self)
            for key in object.allKeys {
                _ = try object.decode(DiscardedSpotifyJSON.self, forKey: key)
            }
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}
