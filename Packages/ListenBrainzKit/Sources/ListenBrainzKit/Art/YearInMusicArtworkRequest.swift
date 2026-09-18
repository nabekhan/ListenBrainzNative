// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct YearInMusicArtworkRequest: APIRequest {
    static let maximumPayloadSize = 4 * 1_024 * 1_024

    let data: APIRequestData<NoBody>

    init(
        username: String,
        year: Int,
        variant: LBYearInMusicArtVariant,
        anonymous: Bool?
    ) {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: allowed) ?? username
        var queryItems = ["image": [variant.rawValue]]
        if let anonymous {
            queryItems["anonymous"] = [anonymous ? "true" : "false"]
        }
        data = .init(
            path: "/1/art/year-in-music/\(year)/\(encodedUsername)",
            method: .get,
            queryItems: queryItems,
            statusErrors: [400: .badRequest],
            pathIsPercentEncoded: true
        )
    }

    func decodeResponse(_ data: Data, response: HTTPURLResponse?) throws -> LBYearInMusicArtwork? {
        if response?.statusCode == 204 { return nil }
        guard data.count <= Self.maximumPayloadSize,
              !data.isEmpty,
              let svg = String(data: data, encoding: .utf8),
              isSVG(svg)
        else { throw LBError.invalidResponse }

        if let response {
            guard let contentType = response.value(forHTTPHeaderField: "Content-Type"),
                  contentType.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "image/svg+xml"
            else { throw LBError.invalidResponse }
        }
        return LBYearInMusicArtwork(svg: svg)
    }

    private func isSVG(_ value: String) -> Bool {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        if trimmed.range(of: "<svg", options: [.anchored, .caseInsensitive]) != nil {
            return true
        }

        guard trimmed.range(of: "<?xml", options: [.anchored, .caseInsensitive]) != nil,
              let declarationEnd = trimmed.range(of: "?>")?.upperBound
        else { return false }

        let root = trimmed[declarationEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
        return root.range(of: "<svg", options: [.anchored, .caseInsensitive]) != nil
    }
}
