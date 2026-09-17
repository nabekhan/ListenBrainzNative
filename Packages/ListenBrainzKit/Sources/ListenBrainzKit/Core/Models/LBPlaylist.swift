// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A complete ListenBrainz playlist, including its JSPF track list.
public struct LBPlaylist: Sendable {
    public let mbid: UUID
    public let metadata: LBPlaylistMetadata
    public let tracks: [LBPlaylistTrack]

    init(raw: RawPlaylist, mbid: UUID) {
        self.mbid = mbid
        self.metadata = LBPlaylistMetadata(raw: raw)
        self.tracks = raw.track.map(LBPlaylistTrack.init)
    }
}

/// One track in a ListenBrainz JSPF playlist.
public struct LBPlaylistTrack: Sendable {
    public let title: String?
    public let artistCreditName: String?
    public let releaseName: String?
    public let durationMilliseconds: Int?
    public let recordingMBID: UUID?
    public let releaseMBID: UUID?
    public let artistMBIDs: [UUID]
    public let caaReleaseMBID: UUID?
    public let caaID: Int?
    public let addedAt: Date?
    public let addedBy: String?

    init(raw: RawPlaylistTrack) {
        let listenBrainz = raw.ext?.listenbrainz
        self.title = raw.title
        self.artistCreditName = raw.creator
        self.releaseName = raw.album
        self.durationMilliseconds = raw.duration
        self.recordingMBID = Self.musicBrainzID(in: raw.identifier, entity: "recording")
        self.releaseMBID = Self.musicBrainzID(
            in: listenBrainz?.releaseIdentifier.map { [$0] },
            entity: "release"
        )
        self.artistMBIDs = (listenBrainz?.artistIdentifiers ?? []).compactMap {
            Self.musicBrainzID(in: [$0], entity: "artist")
        }
        self.caaReleaseMBID = listenBrainz?.additionalMetadata?.caaReleaseMbid
            .flatMap(UUID.init(uuidString:))
        self.caaID = listenBrainz?.additionalMetadata?.caaId
        self.addedAt = parsePlaylistDate(listenBrainz?.addedAt)
        self.addedBy = listenBrainz?.addedBy
    }

    private static func musicBrainzID(in identifiers: [String]?, entity: String) -> UUID? {
        identifiers?.lazy.compactMap { identifier -> UUID? in
            guard let url = URL(string: identifier),
                  url.scheme?.lowercased() == "https",
                  url.host?.lowercased() == "musicbrainz.org",
                  url.user == nil,
                  url.password == nil,
                  url.port == nil || url.port == 443
            else { return nil }

            let components = url.pathComponents.filter { $0 != "/" }
            guard components.count == 2,
                  components[0].lowercased() == entity
            else { return nil }
            return UUID(uuidString: components[1])
        }.first
    }
}
