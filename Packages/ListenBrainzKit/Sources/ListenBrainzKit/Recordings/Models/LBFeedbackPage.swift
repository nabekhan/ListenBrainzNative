// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A paginated page of recording feedback submitted by one ListenBrainz user.
public struct LBFeedbackPage: Decodable, Equatable, Sendable {
    /// Number of feedback entries returned in this page.
    public let count: Int
    /// Feedback entries returned for the requested page.
    public let feedback: [LBFeedback]
    /// Number of entries skipped before this page.
    public let offset: Int
    /// Total number of matching feedback entries available to the user.
    public let totalCount: Int
}
