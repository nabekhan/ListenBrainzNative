// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBAdditionalInfo: Codable, Equatable {
    public var artistMbids: [UUID]?
    public var releaseGroupMbid: UUID?
    public var releaseMbid: UUID?
    public var recordingMbid: UUID?
    public var trackMbid: UUID?
    public var workMbids: [UUID]?
    public var tracknumber: Int?
    public var isrc: String?
    public var spotifyId: String?
    public var tags: [String]?
    public var mediaPlayer: String?
    public var mediaPlayerVersion: String?
    public var submissionClient: String?
    public var submissionClientVersion: String?
    public var musicService: String?
    public var musicServiceName: String?
    public var originUrl: String?
    public var durationMs: Int?
    public var duration: Int?

    public init(artistMbids: [UUID]? = nil,
                releaseGroupMbid: UUID? = nil,
                releaseMbid: UUID? = nil,
                recordingMbid: UUID? = nil,
                trackMbid: UUID? = nil,
                workMbids: [UUID]? = nil,
                tracknumber: Int? = nil,
                isrc: String? = nil,
                spotifyId: String? = nil,
                tags: [String]? = nil,
                mediaPlayer: String? = nil,
                mediaPlayerVersion: String? = nil,
                submissionClient: String? = nil,
                submissionClientVersion: String? = nil,
                musicService: String? = nil,
                musicServiceName: String? = nil,
                originUrl: String? = nil,
                durationMs: Int? = nil,
                duration: Int? = nil) {
        self.artistMbids = artistMbids
        self.releaseGroupMbid = releaseGroupMbid
        self.releaseMbid = releaseMbid
        self.recordingMbid = recordingMbid
        self.trackMbid = trackMbid
        self.workMbids = workMbids
        self.tracknumber = tracknumber
        self.isrc = isrc
        self.spotifyId = spotifyId
        self.tags = tags
        self.mediaPlayer = mediaPlayer
        self.mediaPlayerVersion = mediaPlayerVersion
        self.submissionClient = submissionClient
        self.submissionClientVersion = submissionClientVersion
        self.musicService = musicService
        self.musicServiceName = musicServiceName
        self.originUrl = originUrl
        self.durationMs = durationMs
        self.duration = duration
    }
}
