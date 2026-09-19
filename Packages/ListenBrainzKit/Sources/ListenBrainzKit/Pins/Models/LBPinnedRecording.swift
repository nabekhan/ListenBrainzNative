// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A pin returned by ListenBrainz, including the server-provided track metadata when available.
public struct LBPinnedRecording: Decodable, Equatable, Sendable {
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
public struct LBPinnedRecordingPage: Decodable, Equatable, Sendable {
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

/// One page of the active pins belonging to people a user follows.
///
/// Unlike a user's pin history, this endpoint deliberately does not include a
/// `total_count`; clients should stop after a short page.
public struct LBFollowingPinsPage: Decodable, Equatable, Sendable {
    public let pinnedRecordings: [LBPinnedRecording]
    public let count: Int
    public let offset: Int
    public let userName: String?

    enum CodingKeys: String, CodingKey {
        case pinnedRecordings = "pinnedRecordings"
        case count, offset
        case userName = "userName"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rows = (try? values.decode([LossyPinnedRecording].self, forKey: .pinnedRecordings)) ?? []
        pinnedRecordings = rows.compactMap(\.value)
        count = max(0, Self.integer(for: .count, in: values) ?? pinnedRecordings.count)
        offset = max(0, Self.integer(for: .offset, in: values) ?? 0)
        userName = try? values.decode(String.self, forKey: .userName)
    }

    private static func integer(
        for key: CodingKeys,
        in values: KeyedDecodingContainer<CodingKeys>
    ) -> Int? {
        if let value = try? values.decode(Int.self, forKey: key) { return value }
        guard let value = try? values.decode(String.self, forKey: key) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct LossyPinnedRecording: Decodable {
    let value: LBPinnedRecording?

    init(from decoder: any Decoder) throws {
        value = try? LBPinnedRecording(from: decoder)
    }
}

struct CurrentPinResponse: Decodable {
    let pinnedRecording: LBPinnedRecording?
}

struct CreatePinResponse: Decodable {
    let pinnedRecording: LBPinnedRecording
}
