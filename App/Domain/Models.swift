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

struct PinnedRecording: Identifiable, Hashable, Sendable {
    let rowID: Int
    let created: Date
    let pinnedUntil: Date?
    let blurb: String?
    let username: String?
    let recording: Recording
    let isCurrent: Bool

    var id: Int { rowID }
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

struct UserProfileSnapshot: Sendable {
    var recentListens: [Listen]
    var playingNow: Listen?
    var listenCount: Int?
    var topArtists: [RankedArtist]
    var hasLoadedOverview: Bool
    var hasLoadedTopArtists: Bool
    var savedAt: Date

    static let empty = UserProfileSnapshot(
        recentListens: [],
        playingNow: nil,
        listenCount: nil,
        topArtists: [],
        hasLoadedOverview: false,
        hasLoadedTopArtists: false,
        savedAt: .distantPast
    )
}

enum RecordingFeedback: Int, Sendable {
    case hate = -1
    case none = 0
    case love = 1
}

enum ListeningActivityPeriod: String, CaseIterable, Identifiable, Sendable {
    case thisWeek
    case thisMonth
    case thisYear
    case lastWeek
    case lastMonth
    case lastYear
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .thisYear: "This Year"
        case .lastWeek: "Last Week"
        case .lastMonth: "Last Month"
        case .lastYear: "Last Year"
        case .allTime: "All Time"
        }
    }

    var accessibilityLabel: String { title }
}

struct ListeningActivity: Hashable, Sendable {
    let period: ListeningActivityPeriod
    let from: Date
    let to: Date
    let lastUpdated: Date
    let buckets: [Bucket]

    struct Bucket: Identifiable, Hashable, Sendable {
        let label: String
        let from: Date
        let to: Date
        let listenCount: Int

        var id: String {
            "\(from.timeIntervalSince1970):\(to.timeIntervalSince1970):\(label)"
        }
    }

    var totalListens: Int { buckets.reduce(into: 0) { $0 += $1.listenCount } }
    var busiestBucket: Bucket? { buckets.max { $0.listenCount < $1.listenCount } }
}

enum ListeningActivityLoadState: Equatable {
    case idle
    case loading
    case loaded(ListeningActivity)
    case failed(String)
}

struct FreshRelease: Identifiable, Hashable, Sendable {
    let releaseMBID: UUID?
    let releaseGroupMBID: UUID?
    let title: String
    let artistName: String
    let artistMBIDs: [UUID]
    let releaseDate: String?
    let primaryType: String?
    let secondaryType: String?
    let tags: [String]
    let confidence: Double?
    let listenCount: Int?
    let artworkReleaseMBID: UUID?
    let sourcePosition: Int

    var id: String {
        let identity: String
        if let releaseMBID {
            identity = "release:\(releaseMBID.uuidString)"
        } else if let releaseGroupMBID {
            identity = "release-group:\(releaseGroupMBID.uuidString)"
        } else {
            identity = "unmapped-release:\(artistName):\(title):\(releaseDate ?? "")"
        }
        return "\(identity):\(sourcePosition)"
    }

    var artworkURL: URL? {
        guard let artworkReleaseMBID else { return nil }
        return URL(string: "https://coverartarchive.org/release/\(artworkReleaseMBID.uuidString)/front-500")
    }

    var typeDescription: String? {
        [primaryType, secondaryType].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    var releaseDateValue: Date? {
        releaseDateValue(in: .autoupdatingCurrent)
    }

    func releaseDateValue(in timeZone: TimeZone) -> Date? {
        guard let releaseDate else { return nil }
        let components = releaseDate.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = timeZone
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        return dateComponents.date
    }

    var releaseDateDescription: String? {
        releaseDateValue?.formatted(.dateTime.month(.abbreviated).day().year()) ?? releaseDate
    }

    var isUpcoming: Bool {
        guard let releaseDateValue else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.compare(releaseDateValue, to: .now, toGranularity: .day) == .orderedDescending
    }

    var releaseMusicBrainzURL: URL? {
        guard let releaseMBID else { return nil }
        return URL(string: "https://musicbrainz.org/release/\(releaseMBID.uuidString)")
    }

    var releaseGroupMusicBrainzURL: URL? {
        guard let releaseGroupMBID else { return nil }
        return URL(string: "https://musicbrainz.org/release-group/\(releaseGroupMBID.uuidString)")
    }
}

enum FreshReleaseScope: String, CaseIterable, Identifiable, Sendable {
    case forYou
    case all

    var id: Self { self }
    var title: String { self == .forYou ? "For You" : "All" }
}

enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case users
    case artists
    case releaseGroups
    case recordings
    case playlists

    var id: Self { self }
    var title: String {
        switch self {
        case .users: "Users"
        case .artists: "Artists"
        case .releaseGroups: "Albums"
        case .recordings: "Tracks"
        case .playlists: "Playlists"
        }
    }

    var minimumQueryLength: Int { self == .playlists ? 3 : 1 }
}

struct SearchReleaseGroup: Identifiable, Hashable, Sendable {
    let mbid: UUID
    let title: String
    let artistName: String
    let primaryType: String?
    let firstReleaseDate: String?

    var id: UUID { mbid }
    var musicBrainzURL: URL { URL(string: "https://musicbrainz.org/release-group/\(mbid.uuidString)")! }
}

struct SearchUser: Identifiable, Hashable, Sendable {
    let username: String
    var id: String { username.lowercased() }
    var listenBrainzURL: URL? {
        URL(string: "https://listenbrainz.org")?
            .appending(path: "user")
            .appending(path: username)
    }
}

struct SearchPlaylist: Identifiable, Hashable, Sendable {
    let title: String
    let creator: String
    let annotation: String?
    let identifier: String
    let isPublic: Bool
    let lastModifiedAt: Date?

    var id: String { identifier }
    var listenBrainzURL: URL? {
        guard let source = URL(string: identifier),
              source.scheme?.lowercased() == "https",
              source.host?.lowercased() == "listenbrainz.org",
              source.user == nil,
              source.password == nil,
              source.port == nil || source.port == 443,
              source.pathComponents.dropFirst().first == "playlist"
        else { return nil }
        return source
    }
}

enum SearchResult: Identifiable, Hashable, Sendable {
    case user(SearchUser)
    case artist(RankedArtist)
    case releaseGroup(SearchReleaseGroup)
    case recording(Recording)
    case playlist(SearchPlaylist)

    var id: String {
        switch self {
        case let .user(value): "user:\(value.id)"
        case let .artist(value): "artist:\(value.id)"
        case let .releaseGroup(value): "release-group:\(value.id.uuidString)"
        case let .recording(value): "recording:\(value.id)"
        case let .playlist(value): "playlist:\(value.id)"
        }
    }

    var title: String {
        switch self {
        case let .user(value): value.username
        case let .artist(value): value.name
        case let .releaseGroup(value): value.title
        case let .recording(value): value.title
        case let .playlist(value): value.title
        }
    }

    var subtitle: String? {
        switch self {
        case .user: "ListenBrainz user"
        case let .artist(value): value.listenCount > 0 ? "\(value.listenCount.formatted()) of your listens" : "MusicBrainz artist"
        case let .releaseGroup(value): [value.artistName.nilIfEmpty, value.firstReleaseDate, value.primaryType]
                .compactMap { $0 }
                .joined(separator: " · ")
        case let .recording(value): [value.artistName.nilIfEmpty, value.releaseTitle]
                .compactMap { $0 }
                .joined(separator: " · ")
        case let .playlist(value): "By \(value.creator)"
        }
    }
}

enum SearchLoadState: Equatable {
    case idle
    case waiting
    case loading
    case loaded
    case failed(String)
}

enum FreshReleasesLoadState: Equatable {
    case idle
    case loading
    case loaded([FreshRelease])
    case failed(String)
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
