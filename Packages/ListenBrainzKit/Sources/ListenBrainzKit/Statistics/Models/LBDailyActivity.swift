// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A user's listening counts grouped by UTC weekday and hour.
public struct LBDailyActivity: Decodable {
    public let userID: String
    public let dailyActivity: [String: [Hour]]
    public let range: String
    public let from: Date
    public let to: Date
    public let lastUpdated: Int

    public struct Hour: Decodable {
        /// Hour of the day in UTC, from 0 through 23.
        public let hour: Int
        public let listenCount: Int
    }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case dailyActivity
        case range
        case from = "fromTs"
        case to = "toTs"
        case lastUpdated
    }

}
