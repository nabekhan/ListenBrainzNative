// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBReleaseGroupMeta: Decodable, Sendable {
    /// Cover art file ID in the Cover Art Archive
    public let caaId: Int?
    /// Release's MBID on Cover Art Archive
    public let caaReleaseMbid: UUID?

    public let name: String
    /// MusicBrainz date text, preserving partial-date precision when present.
    public let dateString: String?
    public let date: Date?
    public let type: ReleaseType?
    // Note: I can't find examples of releases that have rels populated so I haven't included it here
    // let rels: [[String: String]]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.caaId = try container.decodeIfPresent(Int.self, forKey: .caaId)
        self.caaReleaseMbid = try container.decodeIfPresent(UUID.self, forKey: .caaReleaseMbid)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decodeIfPresent(ReleaseType.self, forKey: .type)

        self.dateString = try container.decodeIfPresent(String.self, forKey: .date)
        self.date = Self.parseMusicBrainzDate(dateString)
    }

    enum CodingKeys: String, CodingKey {
        case caaId
        case caaReleaseMbid
        case name
        case date
        case type
    }

    public enum ReleaseType: String, Decodable, Sendable {
        case album = "Album"
        case single = "Single"
        case ep = "EP"
        case broadcast = "Broadcast"
        case other = "Other"
    }

    private static func parseMusicBrainzDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(parts.count),
              let year = Int(parts[0])
        else { return nil }

        let month = parts.count > 1 ? Int(parts[1]) : 1
        let day = parts.count > 2 ? Int(parts[2]) : 1
        guard let month, let day else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))
    }
}
