// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

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

    /// Submits feedback for a recording recommendation as the authenticated user.
    @discardableResult
    public func submitFeedback(
        recordingMBID: UUID,
        rating: LBRecommendationFeedbackRating
    ) async throws -> LBRecommendationFeedbackStatus {
        try await apiClient.execute(SubmitRecommendationFeedbackRequest(
            recordingMBID: recordingMBID,
            rating: rating
        ))
    }

    /// Clears the authenticated user's feedback for a recording recommendation.
    @discardableResult
    public func deleteFeedback(
        recordingMBID: UUID
    ) async throws -> LBRecommendationFeedbackStatus {
        try await apiClient.execute(DeleteRecommendationFeedbackRequest(
            recordingMBID: recordingMBID
        ))
    }

    /// Clears the authenticated user's feedback for a recording recommendation.
    ///
    /// This is an alias for ``deleteFeedback(recordingMBID:)``.
    @discardableResult
    public func clearFeedback(
        recordingMBID: UUID
    ) async throws -> LBRecommendationFeedbackStatus {
        try await deleteFeedback(recordingMBID: recordingMBID)
    }

    /// Fetches a paginated user's recommendation feedback, optionally filtered by rating.
    public func feedback(
        user: String,
        rating: LBRecommendationFeedbackRating? = nil,
        count: Int = 25,
        offset: Int = 0
    ) async throws -> LBRecommendationFeedbackPage {
        try await apiClient.execute(UserRecommendationFeedbackRequest(
            username: user,
            rating: rating,
            count: count,
            offset: offset
        ))
    }

    /// Fetches a user's recommendation feedback for a batch of recording MBIDs.
    public func feedback(
        user: String,
        recordingMBIDs: [UUID]
    ) async throws -> LBRecommendationFeedbackBatch {
        guard !recordingMBIDs.isEmpty else { throw LBError.invalidParam }
        return try await apiClient.execute(BatchedRecommendationFeedbackRequest(
            username: user,
            recordingMBIDs: recordingMBIDs
        ))
    }
}
