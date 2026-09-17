// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBTopRecordings: Decodable {
    public let recordings: [Recording]
    /// Total recordings listened to beyond what's in .recordings. Only populated from user
    public let totalRecordingCount: Int?
    public let lastUpdated: Date
    public let from: Date
    public let to: Date

    public struct Recording: Decodable {
        public let artistMbids: [UUID]?
        public let artistName: String
        public let listenCount: Int
        public let recordingMbid: UUID?
        public let releaseMbid: UUID?
        public let releaseName: String
        public let trackName: String
    }

    enum CodingKeys: String, CodingKey {
        case recordings
        case totalRecordingCount
        case lastUpdated
        case from = "fromTs"
        case to = "toTs"
    }
}
