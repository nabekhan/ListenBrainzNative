// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A user's listens grouped by the original release year of each recording.
public struct LBEraActivity: Decodable {
    public let userID: String
    public let eraActivity: [Year]
    public let range: String
    public let from: Date
    public let to: Date
    public let lastUpdated: Int

    public struct Year: Decodable {
        public let year: Int
        public let listenCount: Int
    }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case eraActivity
        case range
        case from = "fromTs"
        case to = "toTs"
        case lastUpdated
    }
}
