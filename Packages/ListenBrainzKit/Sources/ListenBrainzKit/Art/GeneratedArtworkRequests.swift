// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

enum ArtSVGResponseDecoder {
    static let maximumPayloadSize = 4 * 1_024 * 1_024

    static func artwork(
        from data: Data,
        response: HTTPURLResponse?
    ) throws -> LBGeneratedArtwork? {
        if response?.statusCode == 204 { return nil }

        guard data.count <= maximumPayloadSize,
              !data.isEmpty,
              let svg = String(data: data, encoding: .utf8),
              isSVG(svg)
        else {
            throw LBError.invalidResponse
        }

        if let response {
            guard let contentType = response.value(forHTTPHeaderField: "Content-Type"),
                  contentType
                    .split(separator: ";", maxSplits: 1)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "image/svg+xml"
            else {
                throw LBError.invalidResponse
            }
        }

        return LBGeneratedArtwork(svg: svg)
    }

    private static func isSVG(_ value: String) -> Bool {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))

        if trimmed.range(of: "<svg", options: [.anchored, .caseInsensitive]) != nil {
            return true
        }

        guard trimmed.range(of: "<?xml", options: [.anchored, .caseInsensitive]) != nil,
              let declarationEnd = trimmed.range(of: "?>")?.upperBound
        else {
            return false
        }

        return trimmed[declarationEnd...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: "<svg", options: [.anchored, .caseInsensitive]) != nil
    }
}

private func artPathComponent(_ value: String) -> String {
    let allowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/?#%"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func validateGrid(
    dimension: Int,
    layout: LBArtGridLayout,
    imageSize: Int? = nil
) throws {
    guard (1 ... 5).contains(dimension),
          layout.isValid(for: dimension),
          imageSize.map({ (128 ... 1_024).contains($0) }) ?? true
    else {
        throw LBError.invalidParam
    }
}

private func gridQuery(
    _ options: LBArtGridOptions,
    includesStatistics: Bool
) -> [String: [String]] {
    var query = [
        "caption": [String(options.captions)],
        "skip-missing": [String(options.skipMissing)],
    ]

    if includesStatistics {
        query["show-rank"] = [String(options.showRank)]
        query["show-listen-count"] = [String(options.showListenCount)]
        query["show-release"] = [String(options.showRelease)]
        query["show-artist"] = [String(options.showArtist)]
    }

    return query
}

struct StatisticsGridArtworkRequest: APIRequest {
    let data: APIRequestData<NoBody>

    init(
        username: String,
        range: LBStatsArtRange,
        dimension: Int,
        layout: LBArtGridLayout,
        imageSize: Int,
        options: LBArtGridOptions
    ) throws {
        try validateGrid(
            dimension: dimension,
            layout: layout,
            imageSize: imageSize
        )
        data = .init(
            path: "/1/art/grid-stats/\(artPathComponent(username))/\(range.rawValue)/\(dimension)/\(layout.rawValue)/\(imageSize)",
            method: .get,
            queryItems: gridQuery(options, includesStatistics: true),
            statusErrors: [400: .badRequest, 404: .notFound],
            pathIsPercentEncoded: true
        )
    }

    func decodeResponse(
        _ data: Data,
        response: HTTPURLResponse?
    ) throws -> LBGeneratedArtwork? {
        try ArtSVGResponseDecoder.artwork(from: data, response: response)
    }
}

struct ArtistGridArtworkRequest: APIRequest {
    let data: APIRequestData<NoBody>

    init(
        artistMBID: UUID,
        dimension: Int,
        layout: LBArtGridLayout,
        imageSize: Int,
        options: LBArtGridOptions
    ) throws {
        try validateGrid(
            dimension: dimension,
            layout: layout,
            imageSize: imageSize
        )
        data = .init(
            path: "/1/art/artist-grid/\(artistMBID.uuidString.lowercased())/\(dimension)/\(layout.rawValue)/\(imageSize)",
            method: .get,
            queryItems: gridQuery(options, includesStatistics: false),
            statusErrors: [400: .badRequest, 404: .notFound]
        )
    }

    func decodeResponse(
        _ data: Data,
        response: HTTPURLResponse?
    ) throws -> LBGeneratedArtwork? {
        try ArtSVGResponseDecoder.artwork(from: data, response: response)
    }
}

struct PlaylistArtworkRequest: APIRequest {
    let data: APIRequestData<NoBody>

    init(
        playlistMBID: UUID,
        dimension: Int,
        layout: LBArtGridLayout
    ) throws {
        try validateGrid(dimension: dimension, layout: layout)
        data = .init(
            path: "/1/art/playlist/\(playlistMBID.uuidString.lowercased())/\(dimension)/\(layout.rawValue)",
            method: .post,
            statusErrors: [
                400: .badRequest,
                401: .invalidAuth,
                404: .notFound,
            ]
        )
    }

    func decodeResponse(
        _ data: Data,
        response: HTTPURLResponse?
    ) throws -> LBGeneratedArtwork? {
        try ArtSVGResponseDecoder.artwork(from: data, response: response)
    }
}
