// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A listen which has no MusicBrainz mapping yet.
public struct LBMissingMusicBrainzListen: Decodable, Sendable, Hashable {
    public let artistName: String
    public let recordingName: String
    public let releaseName: String?
    public let recordingMsid: UUID
    public let listenedAt: Date

    public init(
        artistName: String,
        recordingName: String,
        releaseName: String?,
        recordingMsid: UUID,
        listenedAt: Date
    ) {
        self.artistName = artistName
        self.recordingName = recordingName
        self.releaseName = releaseName
        self.recordingMsid = recordingMsid
        self.listenedAt = listenedAt
    }

    private enum CodingKeys: String, CodingKey {
        case artistName
        case recordingName
        // The public endpoint returns `recording_name`; its older inline
        // documentation called the same field `track_name`.
        case trackName
        case releaseName
        case recordingMsid
        case listenedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artistName = try container.decode(String.self, forKey: .artistName)
        if let value = try container.decodeIfPresent(String.self, forKey: .recordingName) {
            recordingName = value
        } else {
            recordingName = try container.decode(String.self, forKey: .trackName)
        }
        releaseName = try container.decodeIfPresent(String.self, forKey: .releaseName)
        recordingMsid = try container.decode(UUID.self, forKey: .recordingMsid)

        let value = try container.decode(String.self, forKey: .listenedAt)
        guard let parsed = Self.parseISO8601(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: .listenedAt,
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp"
            )
        }
        listenedAt = parsed
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

public struct LBMissingMusicBrainzPage: Decodable, Sendable, Hashable {
    public let userName: String
    public let lastUpdated: Date?
    public let count: Int
    public let totalDataCount: Int
    public let offset: Int
    public let data: [LBMissingMusicBrainzListen]

    public init(
        userName: String,
        lastUpdated: Date?,
        count: Int,
        totalDataCount: Int,
        offset: Int,
        data: [LBMissingMusicBrainzListen]
    ) {
        self.userName = userName
        self.lastUpdated = lastUpdated
        self.count = count
        self.totalDataCount = totalDataCount
        self.offset = offset
        self.data = data
    }
}

public struct LBMissingMusicBrainzClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) { apiClient = client }

    /// Fetches one explicitly bounded page from the public endpoint.
    public func listens(username: String, offset: Int = 0, count: Int = 1_000) async throws -> LBMissingMusicBrainzPage {
        try await apiClient.execute(MissingMusicBrainzRequest(username: username, offset: offset, count: count))
    }
}

struct MissingMusicBrainzRequest: APIRequest {
    typealias Result = LBMissingMusicBrainzPage
    static let maximumResponseBytes = 1 * 1_024 * 1_024
    let data: APIRequestData<NoBody>
    private let requestedUsername: String
    private let requestedOffset: Int

    init(username: String, offset: Int, count: Int) {
        // The username is one opaque segment; encode dots too so `..` cannot
        // be normalized into a different route by URLComponents.
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%."))
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        requestedUsername = username
        requestedOffset = max(offset, 0)
        self.data = .init(
            path: "/1/missing/musicbrainz/user/\(encodedUsername)/",
            method: .get,
            queryItems: [
                "offset": [String(requestedOffset)],
                "count": [String(min(max(count, 1), 1_000))],
            ],
            statusErrors: [400: .badRequest, 404: .notFound],
            preservesTrailingSlash: true,
            maximumResponseBytes: Self.maximumResponseBytes,
            pathIsPercentEncoded: true
        )
    }

    func decodeResponse(_ data: Data, response: HTTPURLResponse?) throws -> LBMissingMusicBrainzPage {
        if response?.statusCode == 204 {
            return .init(
                userName: requestedUsername,
                lastUpdated: nil,
                count: 0,
                totalDataCount: 0,
                offset: requestedOffset,
                data: []
            )
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Response.self, from: data).payload
    }

    private struct Response: Decodable {
        let payload: LBMissingMusicBrainzPage
    }
}
