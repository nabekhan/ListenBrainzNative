// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A pin returned by ListenBrainz, including the server-provided track metadata when available.
public struct LBPinnedRecording: Decodable, Equatable {
    public let rowID: Int
    public let created: Date
    public let pinnedUntil: Date?
    public let recordingMBID: UUID?
    public let recordingMSID: UUID?
    public let blurbContent: String?
    public let userName: String?
    public let trackMetadata: LBTrackMetadata?

    enum CodingKeys: String, CodingKey {
        case rowID = "rowId"
        case created
        case pinnedUntil = "pinnedUntil"
        case recordingMBID = "recordingMbid"
        case recordingMSID = "recordingMsid"
        case blurbContent = "blurbContent"
        case userName = "userName"
        case trackMetadata = "trackMetadata"
    }
}

/// One page of a user's complete pin history.
public struct LBPinnedRecordingPage: Decodable, Equatable {
    public let pinnedRecordings: [LBPinnedRecording]
    public let totalCount: Int
    public let count: Int
    public let offset: Int
    public let userName: String?

    enum CodingKeys: String, CodingKey {
        case pinnedRecordings = "pinnedRecordings"
        case totalCount = "totalCount"
        case count, offset
        case userName = "userName"
    }
}

struct CurrentPinResponse: Decodable {
    let pinnedRecording: LBPinnedRecording?
}

struct CreatePinResponse: Decodable {
    let pinnedRecording: LBPinnedRecording
}
