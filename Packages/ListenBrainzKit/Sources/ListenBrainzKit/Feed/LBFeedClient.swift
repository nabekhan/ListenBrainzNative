// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Access to an authenticated user's ListenBrainz social feed and its supported actions.
public struct LBFeedClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) { self.apiClient = client }

    /// Activity from the authenticated user's network, including recommendations,
    /// pins, follows, reviews, thanks, and notifications where available.
    public func events(
        username: String,
        count: Int = 25,
        maxTimestamp: Date? = nil,
        minTimestamp: Date? = nil
    ) async throws -> LBFeedPage {
        try await apiClient.execute(FeedEventsRequest(
            username: username,
            kind: .events,
            count: count,
            maxTimestamp: maxTimestamp,
            minTimestamp: minTimestamp
        )).payload
    }

    /// Recent listens from users followed by the authenticated user.
    public func followingListens(
        username: String,
        count: Int = 25,
        maxTimestamp: Date? = nil,
        minTimestamp: Date? = nil
    ) async throws -> LBFeedPage {
        try await page(
            username: username,
            kind: .following,
            count: count,
            maxTimestamp: maxTimestamp,
            minTimestamp: minTimestamp
        )
    }

    /// Recent listens from users ListenBrainz considers similar to the authenticated user.
    public func similarListens(
        username: String,
        count: Int = 25,
        maxTimestamp: Date? = nil,
        minTimestamp: Date? = nil
    ) async throws -> LBFeedPage {
        try await page(
            username: username,
            kind: .similar,
            count: count,
            maxTimestamp: maxTimestamp,
            minTimestamp: minTimestamp
        )
    }

    /// Recommends a recording to the authenticated user's followers.
    ///
    /// At least one stable ListenBrainz/MusicBrainz recording identifier is required.
    public func createRecordingRecommendation(
        username: String,
        recordingMBID: UUID? = nil,
        recordingMSID: UUID? = nil
    ) async throws -> LBFeedCreatedEvent {
        try validateRecordingIdentifier(recordingMBID: recordingMBID, recordingMSID: recordingMSID)
        return try await apiClient.execute(CreateRecordingRecommendationRequest(
            username: username,
            recordingMBID: recordingMBID,
            recordingMSID: recordingMSID
        ))
    }

    /// Recommends a recording directly to one or more followers.
    public func createPersonalRecordingRecommendation(
        username: String,
        recordingMBID: UUID? = nil,
        recordingMSID: UUID? = nil,
        users: [String],
        blurbContent: String? = nil
    ) async throws -> LBFeedCreatedEvent {
        try validateRecordingIdentifier(recordingMBID: recordingMBID, recordingMSID: recordingMSID)
        guard !users.isEmpty else { throw LBError.invalidParam }
        return try await apiClient.execute(CreatePersonalRecordingRecommendationRequest(
            username: username,
            recordingMBID: recordingMBID,
            recordingMSID: recordingMSID,
            users: users,
            blurbContent: blurbContent
        ))
    }

    /// Thanks the creator of a supported timeline event, optionally with a note.
    @discardableResult
    public func thank(
        username: String,
        originalEventType: String,
        originalEventID: Int,
        blurbContent: String? = nil
    ) async throws -> LBFeedStatusResponse {
        try validateEvent(eventType: originalEventType, eventID: originalEventID)
        return try await apiClient.execute(CreateThanksRequest(
            username: username,
            originalEventType: originalEventType,
            originalEventID: originalEventID,
            blurbContent: blurbContent
        ))
    }

    /// Hides an event from the authenticated user's feed.
    @discardableResult
    public func hideEvent(
        username: String,
        eventType: String,
        eventID: Int
    ) async throws -> LBFeedStatusResponse {
        try await mutateEvent(username: username, operation: .hide, eventType: eventType, eventID: eventID)
    }

    /// Restores a previously hidden event to the authenticated user's feed.
    @discardableResult
    public func unhideEvent(
        username: String,
        eventType: String,
        eventID: Int
    ) async throws -> LBFeedStatusResponse {
        try await mutateEvent(username: username, operation: .unhide, eventType: eventType, eventID: eventID)
    }

    /// Deletes an event owned by the authenticated user where ListenBrainz permits it.
    @discardableResult
    public func deleteEvent(
        username: String,
        eventType: String,
        eventID: Int
    ) async throws -> LBFeedStatusResponse {
        try await mutateEvent(username: username, operation: .delete, eventType: eventType, eventID: eventID)
    }

    private func page(
        username: String,
        kind: FeedEventsRequest.Kind,
        count: Int,
        maxTimestamp: Date?,
        minTimestamp: Date?
    ) async throws -> LBFeedPage {
        try await apiClient.execute(FeedEventsRequest(
            username: username,
            kind: kind,
            count: count,
            maxTimestamp: maxTimestamp,
            minTimestamp: minTimestamp
        )).payload
    }

    private func mutateEvent(
        username: String,
        operation: FeedEventStatusMutationRequest.Operation,
        eventType: String,
        eventID: Int
    ) async throws -> LBFeedStatusResponse {
        try validateEvent(eventType: eventType, eventID: eventID)
        return try await apiClient.execute(FeedEventStatusMutationRequest(
            username: username,
            operation: operation,
            eventType: eventType,
            eventID: eventID
        ))
    }

    private func validateRecordingIdentifier(recordingMBID: UUID?, recordingMSID: UUID?) throws {
        guard recordingMBID != nil || recordingMSID != nil else { throw LBError.invalidParam }
    }

    private func validateEvent(eventType: String, eventID: Int) throws {
        guard !eventType.isEmpty, eventID >= 0 else { throw LBError.invalidParam }
    }
}
