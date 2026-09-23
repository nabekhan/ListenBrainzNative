// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// ListenBrainz's annual listening retrospective for a user.
///
/// A successful response can still contain an empty `data` object while the
/// report is unavailable. Check ``isAvailable`` before presenting a report.
public struct LBYearInMusic: Decodable {
    public let userName: String?
    public let year: Int?
    public let data: Report

    /// Whether ListenBrainz supplied any report data.
    public var isAvailable: Bool { data.isAvailable }

    public struct Report: Decodable {
        /// Whether the API's `data` object contains any keys.
        public let isAvailable: Bool

        public let dayOfWeek: String?
        public let listensPerDay: [ListeningDay]
        public let mostListenedYear: [String: Int]
        public let artistEvolutionActivity: [ArtistEvolutionEntry]
        public let genreActivity: [GenreActivityEntry]
        public let mostProminentColor: String?
        public let newReleasesOfTopArtists: [Release]
        public let topDiscoveriesPlaylist: Playlist?
        public let topMissedRecordingsPlaylist: Playlist?
        public let topNewRecordingsPlaylist: Playlist?
        public let topRecordingsPlaylist: Playlist?
        public let similarUsers: [String: Double]
        public let topArtists: [Artist]
        public let topGenres: [Genre]
        public let topReleaseGroups: [ReleaseGroup]
        public let topReleases: [Release]
        public let topReleasesCoverArt: [String: String]
        public let topRecordings: [Recording]
        public let artistMap: [ArtistMapEntry]
        public let totalListenCount: Int?
        public let totalArtistsCount: Int?
        public let totalListeningTime: Double?
        public let totalNewArtistsDiscovered: Int?
        public let totalRecordingsCount: Int?
        public let totalReleaseGroupsCount: Int?
        public let totalReleasesCount: Int?

        public struct ListeningDay: Decodable {
            public let from: Date?
            public let to: Date?
            public let timeRange: String?
            public let listenCount: Int?
            public let artistName: String?
            public let artistMBIDs: [String]?

            enum CodingKeys: String, CodingKey {
                case from = "fromTs"
                case to = "toTs"
                case timeRange
                case listenCount
                case artistName
                case artistMBIDs = "artistMbids"
            }
        }

        public struct Artist: Decodable {
            public let mbid: String?
            public let mbids: [String]?
            public let name: String?
            public let listenCount: Int?

            enum CodingKeys: String, CodingKey {
                case mbid = "artistMbid"
                case mbids = "artistMbids"
                case name = "artistName"
                case listenCount
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                mbid = try values.decodeIfPresent(String.self, forKey: .mbid)
                mbids = try values.decodeIfPresent([String].self, forKey: .mbids)
                name = try values.decodeIfPresent(String.self, forKey: .name)
                listenCount = try values.decodeIfPresent(Int.self, forKey: .listenCount)
            }
        }

        public struct ArtistEvolutionEntry: Decodable {
            public let timeUnit: String?
            public let artistMBID: String?
            public let artistName: String?
            public let listenCount: Int?

            enum CodingKeys: String, CodingKey {
                case timeUnit
                case artistMBID = "artistMbid"
                case artistName
                case listenCount
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                if let string = try? values.decode(String.self, forKey: .timeUnit) {
                    timeUnit = string
                } else if let integer = try? values.decode(Int.self, forKey: .timeUnit) {
                    timeUnit = String(integer)
                } else {
                    timeUnit = nil
                }
                artistMBID = try values.decodeIfPresent(String.self, forKey: .artistMBID)
                artistName = try values.decodeIfPresent(String.self, forKey: .artistName)
                listenCount = try values.decodeIfPresent(Int.self, forKey: .listenCount)
            }
        }

        public struct GenreActivityEntry: Decodable {
            public let genre: String?
            public let hour: Int?
            public let listenCount: Int?
        }

        public struct Genre: Decodable {
            public let name: String?
            public let count: Int?
            public let countPercent: Double?

            enum CodingKeys: String, CodingKey {
                case name = "genre"
                case count = "genreCount"
                case countPercent = "genreCountPercent"
            }
        }

        public struct Release: Decodable {
            public let title: String?
            public let releaseMBID: String?
            public let listenCount: Int?
            public let artistName: String?
            public let artistMBIDs: [String]?
            public let releaseGroupMBID: String?
            public let coverArtArchiveID: Int?
            public let coverArtArchiveReleaseMBID: String?
            public let artistCreditMBIDs: [String]?
            public let artistCreditName: String?
            public let artists: [ArtistCredit]?

            enum CodingKeys: String, CodingKey {
                case title
                case releaseName
                case releaseMBID = "releaseMbid"
                case listenCount
                case artistName
                case artistMBIDs = "artistMbids"
                case releaseGroupMBID = "releaseGroupMbid"
                case coverArtArchiveID = "caaId"
                case coverArtArchiveReleaseMBID = "caaReleaseMbid"
                case artistCreditMBIDs = "artistCreditMbids"
                case artistCreditName
                case artists
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                title = try values.decodeIfPresent(String.self, forKey: .title)
                    ?? values.decodeIfPresent(String.self, forKey: .releaseName)
                releaseMBID = try values.decodeIfPresent(String.self, forKey: .releaseMBID)
                listenCount = try values.decodeIfPresent(Int.self, forKey: .listenCount)
                artistName = try values.decodeIfPresent(String.self, forKey: .artistName)
                artistMBIDs = try values.decodeIfPresent([String].self, forKey: .artistMBIDs)
                releaseGroupMBID = try values.decodeIfPresent(String.self, forKey: .releaseGroupMBID)
                coverArtArchiveID = try values.decodeIfPresent(Int.self, forKey: .coverArtArchiveID)
                coverArtArchiveReleaseMBID = try values.decodeIfPresent(String.self, forKey: .coverArtArchiveReleaseMBID)
                artistCreditMBIDs = try values.decodeIfPresent([String].self, forKey: .artistCreditMBIDs)
                artistCreditName = try values.decodeIfPresent(String.self, forKey: .artistCreditName)
                artists = try values.decodeIfPresent([ArtistCredit].self, forKey: .artists)
            }
        }

        public struct ArtistCredit: Decodable {
            public let name: String?
            public let mbid: String?
            public let joinPhrase: String?

            enum CodingKeys: String, CodingKey {
                case name = "artistCreditName"
                case mbid = "artistMbid"
                case joinPhrase
            }
        }

        public struct ReleaseGroup: Decodable {
            public let name: String?
            public let mbid: String?
            public let artistName: String?
            public let artistMBIDs: [String]?
            public let listenCount: Int?
            public let coverArtArchiveID: Int?
            public let coverArtArchiveReleaseMBID: String?
            public let artists: [ArtistCredit]?

            enum CodingKeys: String, CodingKey {
                case name = "releaseGroupName"
                case mbid = "releaseGroupMbid"
                case artistName
                case artistMBIDs = "artistMbids"
                case listenCount
                case coverArtArchiveID = "caaId"
                case coverArtArchiveReleaseMBID = "caaReleaseMbid"
                case artists
            }
        }

        public struct Recording: Decodable {
            public let trackName: String?
            public let artistName: String?
            public let listenCount: Int?
            public let recordingMBID: String?
            public let releaseName: String?
            public let releaseMBID: String?
            public let coverArtArchiveID: Int?
            public let coverArtArchiveReleaseMBID: String?
            public let artistMBIDs: [String]?
            public let artists: [ArtistCredit]?

            enum CodingKeys: String, CodingKey {
                case trackName
                case artistName
                case listenCount
                case recordingMBID = "recordingMbid"
                case releaseName
                case releaseMBID = "releaseMbid"
                case coverArtArchiveID = "caaId"
                case coverArtArchiveReleaseMBID = "caaReleaseMbid"
                case artistMBIDs = "artistMbids"
                case artists
            }
        }

        public struct ArtistMapEntry: Decodable {
            public let country: String?
            public let artistCount: Int?
            public let listenCount: Int?
            public let artists: [Artist]

            enum CodingKeys: String, CodingKey {
                case country
                case artistCount
                case listenCount
                case artists
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                country = try values.decodeIfPresent(String.self, forKey: .country)
                artistCount = try values.decodeIfPresent(Int.self, forKey: .artistCount)
                listenCount = try values.decodeIfPresent(Int.self, forKey: .listenCount)
                artists = try values.decodeIfPresent([Artist].self, forKey: .artists) ?? []
            }
        }

        public struct Playlist: Decodable {
            public let title: String?
            public let creator: String?
            /// JSPF date strings are ISO 8601, unlike ListenBrainz's usual epoch timestamps.
            public let date: String?
            public let identifier: String?
            /// The legacy Year in Music schema wrapped JSPF data and put the
            /// playlist MBID beside it. Current payloads use `identifier`.
            public let legacyMBID: String?
            public let annotation: String?
            public let tracks: [Track]

            private enum CodingKeys: String, CodingKey {
                case title
                case creator
                case date
                case identifier
                case annotation
                case tracks = "track"
            }

            private enum LegacyCodingKeys: String, CodingKey {
                case jspf
                case mbid
            }

            private struct LegacyEnvelope: Decodable {
                let playlist: Payload
            }

            private struct Payload: Decodable {
                let title: String?
                let creator: String?
                let date: String?
                let identifier: String?
                let annotation: String?
                let tracks: [Track]

                enum CodingKeys: String, CodingKey {
                    case title
                    case creator
                    case date
                    case identifier
                    case annotation
                    case tracks = "track"
                }

                init(from decoder: Decoder) throws {
                    let values = try decoder.container(keyedBy: CodingKeys.self)
                    title = try values.decodeIfPresent(String.self, forKey: .title)
                    creator = try values.decodeIfPresent(String.self, forKey: .creator)
                    date = try values.decodeIfPresent(String.self, forKey: .date)
                    identifier = try values.decodeIfPresent(String.self, forKey: .identifier)
                    annotation = try values.decodeIfPresent(String.self, forKey: .annotation)
                    tracks = try values.decodeIfPresent([Track].self, forKey: .tracks) ?? []
                }
            }

            public init(from decoder: Decoder) throws {
                let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
                legacyMBID = try? legacy.decodeIfPresent(String.self, forKey: .mbid)
                let payload: Payload
                if let envelope = try? legacy.decodeIfPresent(LegacyEnvelope.self, forKey: .jspf) {
                    payload = envelope.playlist
                } else {
                    payload = try Payload(from: decoder)
                }
                title = payload.title
                creator = payload.creator
                date = payload.date
                identifier = payload.identifier
                annotation = payload.annotation
                tracks = payload.tracks
            }
        }

        public struct Track: Decodable {
            public let title: String?
            public let creator: String?
            public let album: String?
            public let duration: Int?
            public let identifiers: [String]?

            enum CodingKeys: String, CodingKey {
                case title
                case creator
                case album
                case duration
                case identifiers = "identifier"
            }

            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                title = try values.decodeIfPresent(String.self, forKey: .title)
                creator = try values.decodeIfPresent(String.self, forKey: .creator)
                album = try values.decodeIfPresent(String.self, forKey: .album)
                duration = try values.decodeIfPresent(Int.self, forKey: .duration)
                if let values = try? values.decode([String].self, forKey: .identifiers) {
                    identifiers = values
                } else if let value = try? values.decode(String.self, forKey: .identifiers) {
                    identifiers = [value]
                } else {
                    identifiers = nil
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case dayOfWeek
            case listensPerDay
            case mostListenedYear
            case artistEvolutionActivity
            case genreActivity
            case mostProminentColor
            case newReleasesOfTopArtists
            case topDiscoveriesPlaylist = "playlist-top-discoveries-for-year"
            case topMissedRecordingsPlaylist = "playlist-top-missed-recordings-for-year"
            case topNewRecordingsPlaylist = "playlist-top-new-recordings-for-year"
            case topRecordingsPlaylist = "playlist-top-recordings-for-year"
            case similarUsers
            case topArtists
            case topGenres
            case topReleaseGroups
            case topReleases
            case topReleasesCoverArt = "topReleasesCoverart"
            case topRecordings
            case artistMap
            case totalListenCount
            case totalArtistsCount
            case totalListeningTime
            case totalNewArtistsDiscovered
            case totalRecordingsCount
            case totalReleaseGroupsCount
            case totalReleasesCount
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let rawValues = try decoder.container(keyedBy: AnyCodingKey.self)
            isAvailable = !rawValues.allKeys.isEmpty

            dayOfWeek = try values.decodeIfPresent(String.self, forKey: .dayOfWeek)
            listensPerDay = try values.decodeIfPresent([ListeningDay].self, forKey: .listensPerDay) ?? []
            mostListenedYear = try values.decodeIfPresent([String: Int].self, forKey: .mostListenedYear) ?? [:]
            artistEvolutionActivity = try values.decodeIfPresent([ArtistEvolutionEntry].self, forKey: .artistEvolutionActivity) ?? []
            genreActivity = try values.decodeIfPresent([GenreActivityEntry].self, forKey: .genreActivity) ?? []
            mostProminentColor = try values.decodeIfPresent(String.self, forKey: .mostProminentColor)
            newReleasesOfTopArtists = try values.decodeIfPresent([Release].self, forKey: .newReleasesOfTopArtists) ?? []
            topDiscoveriesPlaylist = try values.decodeIfPresent(Playlist.self, forKey: .topDiscoveriesPlaylist)
            topMissedRecordingsPlaylist = try values.decodeIfPresent(Playlist.self, forKey: .topMissedRecordingsPlaylist)
            topNewRecordingsPlaylist = try values.decodeIfPresent(Playlist.self, forKey: .topNewRecordingsPlaylist)
            topRecordingsPlaylist = try values.decodeIfPresent(Playlist.self, forKey: .topRecordingsPlaylist)
            similarUsers = try values.decodeIfPresent([String: Double].self, forKey: .similarUsers) ?? [:]
            topArtists = try values.decodeIfPresent([Artist].self, forKey: .topArtists) ?? []
            topGenres = try values.decodeIfPresent([Genre].self, forKey: .topGenres) ?? []
            topReleaseGroups = try values.decodeIfPresent([ReleaseGroup].self, forKey: .topReleaseGroups) ?? []
            topReleases = try values.decodeIfPresent([Release].self, forKey: .topReleases) ?? []
            topReleasesCoverArt = (try? values.decode([String: String].self, forKey: .topReleasesCoverArt)) ?? [:]
            topRecordings = try values.decodeIfPresent([Recording].self, forKey: .topRecordings) ?? []
            artistMap = try values.decodeIfPresent([ArtistMapEntry].self, forKey: .artistMap) ?? []
            totalListenCount = try values.decodeIfPresent(Int.self, forKey: .totalListenCount)
            totalArtistsCount = try values.decodeIfPresent(Int.self, forKey: .totalArtistsCount)
            totalListeningTime = try values.decodeIfPresent(Double.self, forKey: .totalListeningTime)
            totalNewArtistsDiscovered = try values.decodeIfPresent(Int.self, forKey: .totalNewArtistsDiscovered)
            totalRecordingsCount = try values.decodeIfPresent(Int.self, forKey: .totalRecordingsCount)
            totalReleaseGroupsCount = try values.decodeIfPresent(Int.self, forKey: .totalReleaseGroupsCount)
            totalReleasesCount = try values.decodeIfPresent(Int.self, forKey: .totalReleasesCount)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case userName
        case year
        case data
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
