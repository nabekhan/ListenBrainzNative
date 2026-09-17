// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBFeedback: Decodable {
    /// When the feedback was given. Not populated by getFeedbackFor()
    public let created: Date?
    public let recordingMbid: UUID
    public let recordingMsid: UUID?
    /// Love, Hate, or No Score
    public let score: LBScore
    /// If populated, contains basic artist/track/release data and
    /// mbidMapping but not additionalInfo
    public let trackMetadata: LBTrackMetadata?
    /// Name of user who gave this feedback
    public let user: String

    enum CodingKeys: String, CodingKey {
        case created
        case recordingMbid
        case recordingMsid
        case score
        case trackMetadata
        case user = "userId"
    }
}
