// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBTag: Decodable, Sendable {
    /// Name of the tag
    public let tag: String
    /// Number of votes on MusicBrainz
    public let voteCount: Int
    let genreMbid: UUID?

    enum CodingKeys: String, CodingKey {
        case tag
        case genreMbid
        case voteCount = "count"
    }
}
