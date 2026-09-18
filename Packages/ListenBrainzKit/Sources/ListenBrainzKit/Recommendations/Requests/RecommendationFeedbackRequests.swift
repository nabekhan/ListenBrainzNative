// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct SubmitRecommendationFeedbackRequest: APIRequest {
    typealias Result = LBRecommendationFeedbackStatus

    let data: APIRequestData<Body>

    init(recordingMBID: UUID, rating: LBRecommendationFeedbackRating) {
        data = .init(
            path: "/1/recommendation/feedback/submit",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(recordingMBID: recordingMBID, rating: rating),
            statusErrors: [400: .invalidJSON, 401: .invalidAuth]
        )
    }

    struct Body: Encodable {
        let recordingMBID: UUID
        let rating: LBRecommendationFeedbackRating
    }
}

struct DeleteRecommendationFeedbackRequest: APIRequest {
    typealias Result = LBRecommendationFeedbackStatus

    let data: APIRequestData<Body>

    init(recordingMBID: UUID) {
        data = .init(
            path: "/1/recommendation/feedback/delete",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(recordingMBID: recordingMBID),
            statusErrors: [400: .invalidJSON, 401: .invalidAuth]
        )
    }

    struct Body: Encodable {
        let recordingMBID: UUID
    }
}

struct UserRecommendationFeedbackRequest: APIRequest {
    typealias Result = LBRecommendationFeedbackPage

    let data: APIRequestData<NoBody>

    init(
        username: String,
        rating: LBRecommendationFeedbackRating?,
        count: Int,
        offset: Int
    ) {
        var queryItems = [
            "count": [String(min(max(count, 0), 1_000))],
            "offset": [String(max(offset, 0))],
        ]
        if let rating {
            queryItems["rating"] = [rating.rawValue]
        }

        data = .init(
            path: "/1/recommendation/feedback/user/\(username)",
            method: .get,
            queryItems: queryItems,
            statusErrors: [400: .badRequest, 404: .notFound]
        )
    }
}

struct BatchedRecommendationFeedbackRequest: APIRequest {
    typealias Result = LBRecommendationFeedbackBatch

    let data: APIRequestData<NoBody>

    init(username: String, recordingMBIDs: [UUID]) {
        data = .init(
            path: "/1/recommendation/feedback/user/\(username)/recordings",
            method: .get,
            queryItems: ["mbids": [recordingMBIDs.map(\.uuidString).joined(separator: ",")]],
            statusErrors: [400: .badRequest, 404: .notFound]
        )
    }
}
