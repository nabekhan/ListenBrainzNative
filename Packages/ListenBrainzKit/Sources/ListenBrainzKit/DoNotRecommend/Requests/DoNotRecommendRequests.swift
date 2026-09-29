// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct DoNotRecommendEntriesRequest: APIRequest {
    typealias Result = LBDoNotRecommendPage
    let data: APIRequestData<NoBody>

    init(username: String, count: Int, offset: Int) {
        // A ListenBrainz username is one opaque path segment. Escape dot as
        // well as delimiters so values such as `..` cannot alter the path.
        let allowed = CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/?#%.")
        )
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: allowed) ?? username
        data = .init(
            path: "/1/user/\(encodedUsername)/do-not-recommend",
            method: .get,
            queryItems: [
                "count": [String(min(max(count, 0), 1_000))],
                "offset": [String(max(offset, 0))],
            ],
            statusErrors: [404: .notFound],
            maximumResponseBytes: 1 * 1_024 * 1_024,
            pathIsPercentEncoded: true
        )
    }
}

struct AddDoNotRecommendRequest: APIRequest {
    typealias Result = LBDoNotRecommendStatus
    let data: APIRequestData<Body>

    init(entity: LBDoNotRecommendEntity, entityMBID: UUID, until: Int?) {
        data = .init(
            path: "/1/do-not-recommend/add",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(
                entity: entity,
                entityMBID: entityMBID,
                until: until
            ),
            statusErrors: [400: .invalidJSON, 401: .invalidAuth],
            maximumResponseBytes: 64 * 1_024,
            maximumRequestBodyBytes: 64 * 1_024
        )
    }

    struct Body: Encodable {
        let entity: LBDoNotRecommendEntity
        let entityMBID: UUID
        let until: Int?
    }
}

struct RemoveDoNotRecommendRequest: APIRequest {
    typealias Result = LBDoNotRecommendStatus
    let data: APIRequestData<Body>

    init(entity: LBDoNotRecommendEntity, entityMBID: UUID) {
        data = .init(
            path: "/1/do-not-recommend/remove",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: .init(entity: entity, entityMBID: entityMBID),
            statusErrors: [400: .invalidJSON, 401: .invalidAuth],
            maximumResponseBytes: 64 * 1_024,
            maximumRequestBodyBytes: 64 * 1_024
        )
    }

    struct Body: Encodable {
        let entity: LBDoNotRecommendEntity
        let entityMBID: UUID
    }
}
