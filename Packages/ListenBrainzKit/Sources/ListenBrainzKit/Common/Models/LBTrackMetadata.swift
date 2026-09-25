// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBTrackMetadata: Codable, Equatable, Sendable {
    public var artist: String
    public var track: String
    public var release: String?
    public var additionalInfo: LBAdditionalInfo?
    public var mbidMapping: MbidMapping?

    init(artist: String, track: String,
         release: String? = nil, additionalInfo: LBAdditionalInfo? = nil) {
        self.artist = artist
        self.track = track
        self.release = release
        self.additionalInfo = additionalInfo
        self.mbidMapping = nil
    }

    public init(artist: String, track: String,
                release: String? = nil,
                tracknumber: Int? = nil,
                tags: [String]? = nil,
                durationMs: Int? = nil,
                duration: Int? = nil,
                artistMbids: [UUID]? = nil,
                releaseGroupMbid: UUID? = nil,
                releaseMbid: UUID? = nil,
                recordingMbid: UUID? = nil,
                trackMbid: UUID? = nil,
                workMbids: [UUID]? = nil,
                isrc: String? = nil,
                mediaPlayer: String? = nil,
                mediaPlayerVersion: String? = nil,
                submissionClient: String? = nil,
                submissionClientVersion: String? = nil,
                musicService: String? = nil,
                musicServiceName: String? = nil,
                spotifyId: String? = nil,
                originUrl: String? = nil) {
        self.init(artist: artist,
                  track: track,
                  release: release,
                  additionalInfo: .init(artistMbids: artistMbids,
                                        releaseGroupMbid: releaseGroupMbid,
                                        releaseMbid: releaseMbid,
                                        recordingMbid: recordingMbid,
                                        trackMbid: trackMbid,
                                        workMbids: workMbids,
                                        tracknumber: tracknumber,
                                        isrc: isrc,
                                        spotifyId: spotifyId,
                                        tags: tags,
                                        mediaPlayer: mediaPlayer,
                                        mediaPlayerVersion: mediaPlayerVersion,
                                        submissionClient: submissionClient,
                                        submissionClientVersion: submissionClientVersion,
                                        musicService: musicService,
                                        musicServiceName: musicServiceName,
                                        originUrl: originUrl,
                                        durationMs: durationMs,
                                        duration: duration))
    }

    enum CodingKeys: String, CodingKey {
        case artist = "artistName"
        case track = "trackName"
        case release = "releaseName"
        case additionalInfo
        case mbidMapping
    }

    public struct MbidMapping: Codable, Equatable, Sendable {
        public let artistMbids: [UUID]?
        public let artists: [MbidMappingArtist]?
        public let recordingMbid: UUID?
        public let releaseMbid: UUID?
        public let releaseGroupMbid: UUID?
        public let recordingName: String?
        public let caaId: Int?
        public let caaReleaseMbid: UUID?
        /// Canonical external relationships resolved by ListenBrainz. These
        /// are optional enrichment, so malformed individual values must not
        /// make an otherwise usable listen undecodable.
        public let urlRels: [URLRelationship]

        enum CodingKeys: String, CodingKey {
            case artistMbids
            case artists
            case recordingMbid
            case releaseMbid
            case releaseGroupMbid
            case recordingName
            case caaId
            case caaReleaseMbid
            case urlRels
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            artistMbids = try container.decodeIfPresent([UUID].self, forKey: .artistMbids)
            artists = try container.decodeIfPresent([MbidMappingArtist].self, forKey: .artists)
            recordingMbid = try container.decodeIfPresent(UUID.self, forKey: .recordingMbid)
            releaseMbid = try container.decodeIfPresent(UUID.self, forKey: .releaseMbid)
            releaseGroupMbid = try container.decodeIfPresent(UUID.self, forKey: .releaseGroupMbid)
            recordingName = try container.decodeIfPresent(String.self, forKey: .recordingName)
            caaId = try container.decodeIfPresent(Int.self, forKey: .caaId)
            caaReleaseMbid = try container.decodeIfPresent(UUID.self, forKey: .caaReleaseMbid)
            urlRels = (try? container.decode(BoundedURLRelationships.self, forKey: .urlRels))?.values ?? []
        }
    }

    /// A ListenBrainz/MusicBrainz URL relationship. The server may add new
    /// relationship types over time, so both fields remain optional and
    /// consumers must decide which values they can safely support.
    public struct URLRelationship: Codable, Equatable, Sendable {
        public let type: String?
        public let url: String?

        enum CodingKeys: String, CodingKey {
            case type
            case url
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try? container.decode(String.self, forKey: .type)
            url = try? container.decode(String.self, forKey: .url)
        }
    }

    private struct BoundedURLRelationships: Decodable {
        let values: [URLRelationship]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var values: [URLRelationship] = []
            values.reserveCapacity(min(container.count ?? 0, 32))

            var inspectedCount = 0
            while !container.isAtEnd, inspectedCount < 32 {
                let element = try container.superDecoder()
                if let relationship = try? URLRelationship(from: element) {
                    values.append(relationship)
                }
                inspectedCount += 1
            }
            self.values = values
        }
    }

    public struct MbidMappingArtist: Codable, Equatable, Sendable {
        public let name: String
        public let mbid: UUID?
        public let joinPhrase: String

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case name = "artistCreditName"
            case mbid = "artistMbid"
            case joinPhrase
        }
    }
}
