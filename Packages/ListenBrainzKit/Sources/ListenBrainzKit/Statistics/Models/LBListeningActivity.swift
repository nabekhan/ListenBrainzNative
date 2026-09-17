// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBListeningActivity: Decodable {
    public let range: String
    public let from: Date
    public let to: Date
    public let lastUpdated: Int
    public let activity: [Chunk]

    public struct Chunk: Codable {
        /// Human-readable description of this chunk's range
        public let timeRange: String
        public let from: Date
        public let to: Date

        public let listenCount: Int

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case timeRange
            case from = "fromTs"
            case to = "toTs"
            case listenCount
        }
    }

    enum CodingKeys: String, CodingKey {
        case range
        case from = "fromTs"
        case to = "toTs"
        case lastUpdated
        case activity = "listeningActivity"
    }
}
