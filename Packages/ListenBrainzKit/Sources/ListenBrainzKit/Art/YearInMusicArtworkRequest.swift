// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct YearInMusicArtworkRequest: APIRequest {
    static let maximumPayloadSize = ArtSVGResponseDecoder.maximumPayloadSize

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
        try ArtSVGResponseDecoder.artwork(from: data, response: response).map { LBYearInMusicArtwork(svg: $0.svg) }
    }
}
