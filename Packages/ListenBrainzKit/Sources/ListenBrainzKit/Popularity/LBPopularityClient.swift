// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBPopularityClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) {
        apiClient = client
    }

    /// Gets daily-rebuilt global popularity for canonical artist MBIDs.
    public func artists(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await fetch(.artist, mbids: mbids)
    }

    /// Gets daily-rebuilt global popularity for canonical recording MBIDs.
    public func recordings(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await fetch(.recording, mbids: mbids)
    }

    /// Gets daily-rebuilt global popularity for canonical concrete release MBIDs.
    public func releases(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await fetch(.release, mbids: mbids)
    }

    /// Gets daily-rebuilt global popularity for canonical release-group MBIDs.
    public func releaseGroups(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await fetch(.releaseGroup, mbids: mbids)
    }

    private func fetch(_ kind: PopularityEntityKind, mbids: [UUID]) async throws -> [LBPopularity] {
        try await apiClient.execute(PopularityBatchRequest(kind: kind, mbids: mbids))
    }
}
