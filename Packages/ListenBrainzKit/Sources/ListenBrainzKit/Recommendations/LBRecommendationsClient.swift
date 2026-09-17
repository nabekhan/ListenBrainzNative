// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Personalized recommendations generated from ListenBrainz listening data.
public struct LBRecommendationsClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) {
        self.apiClient = client
    }

    /// Fetch a page of recording recommendations. `nil` means ListenBrainz has
    /// not generated recommendations for this user yet (HTTP 204).
    public func recordings(
        user: String,
        count: Int = 25,
        offset: Int = 0
    ) async throws -> LBRecordingRecommendations? {
        do {
            return try await apiClient.execute(RecordingRecommendationsRequest(
                username: user,
                count: count,
                offset: offset
            )).payload
        } catch LBError.noContent {
            return nil
        }
    }
}
