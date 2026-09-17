// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum LBFreshReleaseSort: String, CaseIterable, Sendable {
    case releaseDate = "release_date"
    case artistCreditName = "artist_credit_name"
    case releaseName = "release_name"
    case confidence
}

/// Sorts accepted by the sitewide Fresh Releases endpoint. Confidence is a
/// personalized signal and is deliberately unavailable here.
public enum LBSitewideFreshReleaseSort: String, CaseIterable, Sendable {
    case releaseDate = "release_date"
    case artistCreditName = "artist_credit_name"
    case releaseName = "release_name"
}

/// A deliberately tolerant representation of ListenBrainz Fresh Releases.
/// IDs and dates remain strings because the API can omit values and emit dates
/// that are not ISO-8601 padded.
public struct LBFreshReleases: Decodable, Sendable {
    public let userID: String?
    public let releases: [Release]
    public let totalCount: Int?

    public struct Release: Decodable, Sendable {
        public let releaseName: String
        public let releaseMBID: String?
        public let releaseGroupMBID: String?
        public let artistCreditName: String
        public let artistMBIDs: [String]
        public let releaseDate: String?
        public let primaryType: String?
        public let secondaryType: String?
        public let tags: [String]
        public let confidence: Double?
        public let listenCount: Int?
        public let caaID: String?
        public let caaReleaseMBID: String?

        enum CodingKeys: String, CodingKey {
            case releaseName
            case releaseMBID = "releaseMbid"
            case releaseGroupMBID = "releaseGroupMbid"
            case artistCreditName
            case artistMBIDs = "artistMbids"
            case releaseDate
            case primaryType = "releaseGroupPrimaryType"
            case secondaryType = "releaseGroupSecondaryType"
            case tags = "releaseTags"
            case confidence
            case listenCount
            case caaID = "caaId"
            case caaReleaseMBID = "caaReleaseMbid"
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            releaseName = try values.decodeIfPresent(String.self, forKey: .releaseName) ?? "Untitled release"
            releaseMBID = try values.decodeLossyString(forKey: .releaseMBID)
            releaseGroupMBID = try values.decodeLossyString(forKey: .releaseGroupMBID)
            artistCreditName = try values.decodeIfPresent(String.self, forKey: .artistCreditName) ?? "Unknown artist"
            artistMBIDs = try values.decodeIfPresent([String].self, forKey: .artistMBIDs) ?? []
            releaseDate = try values.decodeLossyString(forKey: .releaseDate)
            primaryType = try values.decodeIfPresent(String.self, forKey: .primaryType)
            secondaryType = try values.decodeIfPresent(String.self, forKey: .secondaryType)
            tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
            confidence = try values.decodeIfPresent(Double.self, forKey: .confidence)
            listenCount = try values.decodeIfPresent(Int.self, forKey: .listenCount)
            caaID = try values.decodeLossyString(forKey: .caaID)
            caaReleaseMBID = try values.decodeLossyString(forKey: .caaReleaseMBID)
        }
    }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case releases
        case totalCount
    }
}

struct FreshReleasesResponse: Decodable {
    let payload: LBFreshReleases
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) throws -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) { return string }
        if let integer = try? decodeIfPresent(Int.self, forKey: key) { return String(integer) }
        if let double = try? decodeIfPresent(Double.self, forKey: key) { return String(double) }
        return nil
    }
}
