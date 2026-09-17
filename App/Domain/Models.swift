import Foundation

struct Account: Hashable, Sendable {
    let username: String
    let token: String

    var isAuthenticated: Bool { !token.isEmpty }
}
struct RecordingIdentity: Hashable, Codable, Sendable {
    let mbid: UUID?
    let msid: UUID?
}

struct Recording: Identifiable, Hashable, Codable, Sendable {
    let identity: RecordingIdentity
    let title: String
    let artistName: String
    let artistMBIDs: [UUID]
    let releaseTitle: String?
    let releaseMBID: UUID?
    let releaseGroupMBID: UUID?
    let artworkReleaseMBID: UUID?
    let durationMilliseconds: Int?
    let source: String?

    var id: String {
        if let mbid = identity.mbid { return "mbid:\(mbid.uuidString)" }
        if let msid = identity.msid { return "msid:\(msid.uuidString)" }
        return "unmapped:\(artistName):\(title):\(releaseTitle ?? "")"
    }

    var artworkURL: URL? {
        guard let id = artworkReleaseMBID ?? releaseMBID else { return nil }
        return URL(string: "https://coverartarchive.org/release/\(id.uuidString)/front-500")
    }
}

struct Listen: Identifiable, Hashable, Codable, Sendable {
    let recording: Recording
    let listenedAt: Date
    let insertedAt: Date?
    let isPlayingNow: Bool

    var id: String { "\(recording.id):\(listenedAt.timeIntervalSince1970):\(isPlayingNow)" }
}

struct RankedArtist: Identifiable, Hashable, Codable, Sendable {
    let mbid: UUID?
    let name: String
    let listenCount: Int

    var id: String { mbid?.uuidString ?? "artist:\(name)" }
}

struct RankedRelease: Identifiable, Hashable, Codable, Sendable {
    let mbid: UUID?
    let name: String
    let artistName: String
    let artistMBIDs: [UUID]
    let listenCount: Int

    var id: String { mbid?.uuidString ?? "release:\(artistName):\(name)" }
    var artworkURL: URL? {
        guard let mbid else { return nil }
        return URL(string: "https://coverartarchive.org/release/\(mbid.uuidString)/front-500")
    }
}

struct RankedRecording: Identifiable, Hashable, Codable, Sendable {
    let mbid: UUID?
    let releaseMBID: UUID?
    let title: String
    let artistName: String
    let artistMBIDs: [UUID]
    let releaseTitle: String?
    let listenCount: Int

    var id: String { mbid?.uuidString ?? "recording:\(artistName):\(title)" }
    var recording: Recording {
        Recording(
            identity: .init(mbid: mbid, msid: nil),
            title: title,
            artistName: artistName,
            artistMBIDs: artistMBIDs,
            releaseTitle: releaseTitle,
            releaseMBID: releaseMBID,
            releaseGroupMBID: nil,
            artworkReleaseMBID: releaseMBID,
            durationMilliseconds: nil,
            source: nil
        )
    }
}

struct ListeningSnapshot: Codable, Sendable {
    var recentListens: [Listen]
    var playingNow: Listen?
    var listenCount: Int?
    var topArtists: [RankedArtist]
    var topReleases: [RankedRelease]
    var topRecordings: [RankedRecording]
    var savedAt: Date

    static let empty = ListeningSnapshot(
        recentListens: [],
        playingNow: nil,
        listenCount: nil,
        topArtists: [],
        topReleases: [],
        topRecordings: [],
        savedAt: .distantPast
    )
}

enum RecordingFeedback: Int, Sendable {
    case hate = -1
    case none = 0
    case love = 1
}
