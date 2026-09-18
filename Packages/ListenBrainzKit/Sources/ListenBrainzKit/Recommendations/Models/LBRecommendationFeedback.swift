// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A rating the user can apply to a ListenBrainz recording recommendation.
public enum LBRecommendationFeedbackRating: String, Codable, CaseIterable, Sendable {
    case like
    case love
    case dislike
    case hate
    case badRecommendation = "bad_recommendation"
}

/// Feedback the user submitted for one recording recommendation.
public struct LBRecommendationFeedback: Decodable, Equatable, Sendable {
    public let created: Date
    public let recordingMBID: UUID
    public let rating: LBRecommendationFeedbackRating

    enum CodingKeys: String, CodingKey {
        case created
        case recordingMBID = "recordingMbid"
        case rating
    }
}

/// A paginated page of a user's recommendation feedback.
public struct LBRecommendationFeedbackPage: Decodable, Equatable, Sendable {
    public let feedback: [LBRecommendationFeedback]
    public let count: Int
    public let totalCount: Int
    public let offset: Int
    public let userName: String
}

/// Recommendation feedback for an explicitly requested set of recording MBIDs.
public struct LBRecommendationFeedbackBatch: Decodable, Equatable, Sendable {
    public let feedback: [LBRecommendationFeedback]
    public let userName: String
}

/// The status object returned after recommendation-feedback mutations.
public struct LBRecommendationFeedbackStatus: Decodable, Equatable, Sendable {
    public let status: String
}
