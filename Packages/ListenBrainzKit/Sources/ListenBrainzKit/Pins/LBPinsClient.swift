// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Access to ListenBrainz's pinned-recording API.
public struct LBPinsClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) { self.apiClient = client }

    /// The active pin for a user, or `nil` when they do not currently have one.
    public func current(user: String) async throws -> LBPinnedRecording? {
        try await apiClient.execute(CurrentPinRequest(user: user)).pinnedRecording
    }

    /// A descending, paginated pin history. This contains inactive and expired pins.
    public func history(user: String, count: Int = 20, offset: Int = 0) async throws -> LBPinnedRecordingPage {
        try await apiClient.execute(PinHistoryRequest(user: user, count: count, offset: offset))
    }

    /// Current pins from people a user follows. This public endpoint has no
    /// total count; use the returned page count to determine pagination.
    public func following(user: String, count: Int = 25, offset: Int = 0) async throws -> LBFollowingPinsPage {
        try await apiClient.execute(FollowingPinsRequest(user: user, count: count, offset: offset))
    }

    /// Creates a current pin. Omitting `pinnedUntil` deliberately retains the server's default lifetime.
    @discardableResult
    public func create(
        recordingMBID: UUID? = nil,
        recordingMSID: UUID? = nil,
        blurb: String? = nil,
        pinnedUntil: Date? = nil
    ) async throws -> LBPinnedRecording {
        guard recordingMBID != nil || recordingMSID != nil, blurb.map(\.count) ?? 0 <= 280 else { throw LBError.invalidParam }
        return try await apiClient.execute(CreatePinRequest(
            recordingMBID: recordingMBID,
            recordingMSID: recordingMSID,
            blurb: blurb,
            pinnedUntil: pinnedUntil
        )).pinnedRecording
    }

    /// Deactivates the current pin while preserving it in history.
    public func unpin() async throws {
        _ = try await apiClient.execute(UnpinRequest())
    }

    /// Permanently removes an owned historical pin.
    public func delete(rowID: Int) async throws {
        _ = try await apiClient.execute(DeletePinRequest(rowID: rowID))
    }

    /// Changes only an owned pin's comment/blurb.
    public func updateBlurb(rowID: Int, blurb: String) async throws {
        guard blurb.count <= 280 else { throw LBError.invalidParam }
        let response = try await apiClient.execute(UpdatePinBlurbRequest(rowID: rowID, blurb: blurb))
        guard response.status else { throw LBError.notFound }
    }
}
