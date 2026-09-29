// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Access to ListenBrainz' do-not-recommend preferences.
///
/// These entries record a user's preference for a canonical MusicBrainz
/// entity. Callers should avoid claiming how or when ListenBrainz applies the
/// preference to recommendation generation.
public struct LBDoNotRecommendClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) { self.apiClient = client }

    /// Fetches one oldest-first page of active preferences for a user.
    public func entries(
        user: String,
        count: Int = 25,
        offset: Int = 0
    ) async throws -> LBDoNotRecommendPage {
        try await apiClient.execute(DoNotRecommendEntriesRequest(
            username: user,
            count: count,
            offset: offset
        ))
    }

    /// Creates or updates a do-not-recommend preference for one entity.
    @discardableResult
    public func add(
        entity: LBDoNotRecommendEntity,
        entityMBID: UUID,
        until: Date? = nil
    ) async throws -> LBDoNotRecommendStatus {
        let untilSeconds: Int?
        if let until {
            let seconds = until.timeIntervalSince1970.rounded(.down)
            guard seconds.isFinite,
                  seconds > 0,
                  let exactSeconds = Int(exactly: seconds)
            else { throw LBError.invalidParam }
            untilSeconds = exactSeconds
        } else {
            untilSeconds = nil
        }
        return try await apiClient.execute(AddDoNotRecommendRequest(
            entity: entity,
            entityMBID: entityMBID,
            until: untilSeconds
        ))
    }

    /// Removes a do-not-recommend preference. ListenBrainz treats this as
    /// idempotent: removing an absent entry still succeeds.
    @discardableResult
    public func remove(
        entity: LBDoNotRecommendEntity,
        entityMBID: UUID
    ) async throws -> LBDoNotRecommendStatus {
        try await apiClient.execute(RemoveDoNotRecommendRequest(
            entity: entity,
            entityMBID: entityMBID
        ))
    }
}
