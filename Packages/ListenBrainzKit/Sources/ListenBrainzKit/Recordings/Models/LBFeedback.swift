// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBFeedback: Decodable, Equatable, Sendable {
    /// When the feedback was given. Not populated by getFeedbackFor()
    public let created: Date?
    /// MusicBrainz ID of the recording, when ListenBrainz has mapped it.
    ///
    /// Feedback submitted for an MSID is valid even when it has no recording
    /// MBID mapping yet, so callers must handle the absent value.
    public let recordingMbid: UUID?
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
