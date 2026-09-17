// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct RecordingRecommendationsResponse: Decodable {
    let payload: LBRecordingRecommendations
}

/// One page of ListenBrainz collaborative-filter recording recommendations.
public struct LBRecordingRecommendations: Decodable, Sendable {
    public let modelID: String?
    public let modelURL: URL?
    public let recommendations: [LBRecordingRecommendation]
    public let entity: String
    public let userName: String
    public let lastUpdated: Date
    public let count: Int
    public let totalCount: Int
    public let offset: Int

    enum CodingKeys: String, CodingKey {
        case modelID = "modelId"
        case modelURL = "modelUrl"
        case recommendations = "mbids"
        case entity
        case userName
        case lastUpdated
        case count
        case totalCount = "totalMbidCount"
        case offset
    }
}

/// A recommended MusicBrainz recording and its model score.
public struct LBRecordingRecommendation: Decodable, Sendable {
    public let recordingMBID: UUID
    public let score: Double
    public let latestListenedAt: Date?

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.recordingMBID = try container.decode(UUID.self, forKey: .recordingMBID)
        self.score = try container.decode(Double.self, forKey: .score)
        self.latestListenedAt = Self.parseDate(
            try container.decodeIfPresent(String.self, forKey: .latestListenedAt)
        )
    }

    enum CodingKeys: String, CodingKey {
        case recordingMBID = "recordingMbid"
        case score
        case latestListenedAt
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
