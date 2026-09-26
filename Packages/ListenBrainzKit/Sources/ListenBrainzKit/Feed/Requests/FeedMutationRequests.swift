// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct CreateRecordingRecommendationRequest: APIRequest {
    typealias Result = LBFeedCreatedEvent
    let data: APIRequestData<Body>

    init(username: String, recordingMBID: UUID?, recordingMSID: UUID?) {
        data = .init(
            path: "/1/user/\(username)/timeline-event/create/recording",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(metadata: .init(recordingMBID: recordingMBID, recordingMSID: recordingMSID)),
            statusErrors: FeedMutationStatusErrors.all
        )
    }

    struct Body: Encodable {
        let metadata: Metadata
    }

    struct Metadata: Encodable {
        let recordingMBID: UUID?
        let recordingMSID: UUID?
    }
}

struct CreatePersonalRecordingRecommendationRequest: APIRequest {
    typealias Result = LBFeedCreatedEvent
    let data: APIRequestData<Body>

    init(
        username: String,
        recordingMBID: UUID?,
        recordingMSID: UUID?,
        users: [String],
        blurbContent: String?
    ) {
        data = .init(
            path: "/1/user/\(username)/timeline-event/create/recommend-personal",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(metadata: .init(
                recordingMBID: recordingMBID,
                recordingMSID: recordingMSID,
                users: users,
                blurbContent: blurbContent
            )),
            statusErrors: FeedMutationStatusErrors.all
        )
    }

    struct Body: Encodable {
        let metadata: Metadata
    }

    struct Metadata: Encodable {
        let recordingMBID: UUID?
        let recordingMSID: UUID?
        let users: [String]
        let blurbContent: String?
    }
}

struct CreateThanksRequest: APIRequest {
    typealias Result = LBFeedStatusResponse
    let data: APIRequestData<Body>

    init(username: String, originalEventType: String, originalEventID: Int, blurbContent: String?) {
        data = .init(
            path: "/1/user/\(username)/timeline-event/create/thanks",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(metadata: .init(
                originalEventType: originalEventType,
                originalEventID: originalEventID,
                blurbContent: blurbContent
            )),
            statusErrors: FeedMutationStatusErrors.all
        )
    }

    struct Body: Encodable {
        let metadata: Metadata
    }

    struct Metadata: Encodable {
        let originalEventType: String
        let originalEventID: Int
        let blurbContent: String?
    }
}

/// Creates a CritiqueBrainz review through ListenBrainz's authenticated proxy.
/// The server owns the CritiqueBrainz OAuth exchange and fixes the public
/// CC BY-SA 3.0 license; clients must never handle a CritiqueBrainz token.
struct CreateCritiqueBrainzReviewRequest: APIRequest {
    typealias Result = LBFeedCreatedEvent
    let data: APIRequestData<Body>

    init(username: String, entityName: String, entityID: UUID, entityType: String, text: String, language: String, rating: Int?) {
        // A username is one opaque path segment. Escape dot as well as
        // delimiters so values such as `..` can never become path traversal.
        let allowed = CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/?#%.")
        )
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: allowed) ?? username
        data = .init(
            path: "/1/user/\(encodedUsername)/timeline-event/create/review",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(metadata: .init(entityName: entityName, entityID: entityID, entityType: entityType, text: text, language: language, rating: rating)),
            statusErrors: FeedMutationStatusErrors.all,
            maximumResponseBytes: 64 * 1_024,
            maximumRequestBodyBytes: LBCritiqueBrainzReviewLimits.maximumEncodedRequestBytes,
            pathIsPercentEncoded: true
        )
    }

    struct Body: Encodable { let metadata: Metadata }
    struct Metadata: Encodable {
        let entityName: String
        let entityID: UUID
        let entityType: String
        let text: String
        let language: String
        let rating: Int?
    }
}

struct FeedEventStatusMutationRequest: APIRequest {
    enum Operation: String {
        case hide
        case unhide
        case delete
    }

    typealias Result = LBFeedStatusResponse
    let data: APIRequestData<Body>

    init(username: String, operation: Operation, eventType: String, eventID: Int) {
        data = .init(
            path: "/1/user/\(username)/feed/events/\(operation.rawValue)",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(eventType: eventType, eventID: eventID, usesDeleteKey: operation == .delete),
            statusErrors: FeedMutationStatusErrors.all
        )
    }

    struct Body: Encodable {
        let eventType: String
        let eventID: Int
        let usesDeleteKey: Bool

        enum CodingKeys: String, CodingKey {
            case eventType
            case eventID
            case id
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(eventType, forKey: .eventType)
            if usesDeleteKey {
                try container.encode(eventID, forKey: .id)
            } else {
                try container.encode(eventID, forKey: .eventID)
            }
        }
    }
}

private enum FeedMutationStatusErrors {
    static let all: [Int: LBError] = [
        400: .invalidJSON,
        401: .invalidAuth,
        403: .forbidden,
        404: .notFound,
    ]
}
