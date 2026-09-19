// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

private func encodedYearInMusicUser(_ user: String) -> String {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
    var encoded = user.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    if encoded == "." { encoded = "%2E" }
    if encoded == ".." { encoded = "%2E%2E" }
    return encoded
}

public struct StatsYearInMusicRequest: APIRequest {
    let data: APIRequestData<NoBody>

    init(user: String, year: Int?) {
        let yearPath = year.map { "/\($0)" } ?? ""
        self.data = .init(
            path: "/1/stats/user/\(encodedYearInMusicUser(user))/year-in-music\(yearPath)",
            method: .get,
            queryItems: [:],
            headers: [:],
            body: nil,
            statusErrors: [
                400: .badRequest,
                404: .notFound,
                204: .noContent,
            ],
            pathIsPercentEncoded: true
        )
    }

    struct Result: Decodable {
        let payload: LBYearInMusic
    }
}

/// Frozen historical Year in Music reports. The endpoint intentionally only
/// exposes the four archival reports produced by the old pipeline.
public struct StatsLegacyYearInMusicRequest: APIRequest {
    /// Legacy responses can include embedded JSPF playlists and artwork maps.
    /// Keep the cap deliberately generous enough for a real archive, while
    /// refusing a malformed response before JSON decoding can consume it.
    public static let maximumPayloadSize = 16 * 1_024 * 1_024

    let data: APIRequestData<NoBody>

    init(user: String, year: Int) throws {
        guard (2021 ... 2024).contains(year) else { throw LBError.invalidParam }
        let encodedUser = encodedYearInMusicUser(user)
        data = .init(
            path: "/1/stats/user/\(encodedUser)/year-in-music/legacy/\(year)",
            method: .get,
            statusErrors: [400: .badRequest, 404: .notFound, 204: .noContent],
            maximumResponseBytes: Self.maximumPayloadSize,
            pathIsPercentEncoded: true
        )
    }

    struct Result: Decodable { let payload: LBYearInMusic }

    func decodeResponse(_ data: Data, response: HTTPURLResponse?) throws -> Result {
        guard data.count <= Self.maximumPayloadSize else { throw LBError.invalidResponse }
        return try JSONDecoder.ListenBrainz.decode(Result.self, from: data)
    }
}
