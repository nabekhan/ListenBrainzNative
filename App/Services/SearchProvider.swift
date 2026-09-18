import Foundation
import ListenBrainzKit

protocol SearchProviding: Sendable {
    func search(query: String, scope: SearchScope) async throws -> [SearchResult]
}

struct SearchProvider: SearchProviding {
    private let listenBrainz: LBClient
    private let musicBrainz: MusicBrainzSearchClient
    private let listenBrainzGate: RequestGate

    init(
        token: String,
        listenBrainzGate: RequestGate = .shared,
        musicBrainz: MusicBrainzSearchClient = .init()
    ) {
        self.listenBrainz = LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        self.listenBrainzGate = listenBrainzGate
        self.musicBrainz = musicBrainz
    }

    func search(query: String, scope: SearchScope) async throws -> [SearchResult] {
        switch scope {
        case .artists, .releaseGroups, .recordings:
            return try await musicBrainz.search(query: query, scope: scope)
        case .users:
            return try await performListenBrainz {
                try await listenBrainz.core.searchUser(term: query).map { .user(.init(username: $0)) }
            }
        case .playlists:
            guard query.count >= scope.minimumQueryLength else { return [] }
            return try await performListenBrainz {
                try await listenBrainz.core.searchPlaylists(query: query, count: 20).map {
                    .playlist(.init(
                        title: $0.title,
                        creator: $0.creator,
                        annotation: $0.annotation,
                        identifier: $0.identifier,
                        isPublic: $0.isPublic,
                        lastModifiedAt: $0.lastModifiedAt
                    ))
                }
            }
        }
    }

    private func performListenBrainz<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await listenBrainzGate.perform(operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }
}

enum MusicBrainzSearchError: LocalizedError, Sendable {
    case rateLimited(retryAfter: Int)
    case unavailable(retryAfter: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .rateLimited(seconds): "MusicBrainz is busy. Try again in about \(seconds) seconds."
        case let .unavailable(seconds): "MusicBrainz is temporarily unavailable. Try again in about \(seconds) seconds."
        case .invalidResponse: "MusicBrainz returned an unexpected response."
        }
    }
}

struct MusicBrainzSearchClient: Sendable {
    private static let root = URL(string: "https://musicbrainz.org/ws/2")!
    // MusicBrainz is a separate service with its own one-request-per-second
    // policy. Keep its scheduling independent from ListenBrainz, but shared
    // by every search sheet in this app process.
    private static let sharedGate = RequestGate()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private let gate: RequestGate
    private let userAgent: String

    init(
        gate: RequestGate? = nil,
        userAgent: String = "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
    ) {
        self.gate = gate ?? Self.sharedGate
        self.userAgent = userAgent
    }

    func search(query: String, scope: SearchScope, limit: Int = 20) async throws -> [SearchResult] {
        guard scope == .artists || scope == .releaseGroups || scope == .recordings else { return [] }
        return try await gate.perform {
            let request = try Self.makeRequest(query: query, scope: scope, limit: limit, userAgent: userAgent)
            let (data, response) = try await Self.session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw MusicBrainzSearchError.invalidResponse }
            switch response.statusCode {
            case 200 ... 299: break
            case 429: throw MusicBrainzSearchError.rateLimited(retryAfter: Self.retryAfter(response))
            case 503: throw MusicBrainzSearchError.unavailable(retryAfter: Self.retryAfter(response))
            default: throw MusicBrainzSearchError.invalidResponse
            }
            return try Self.decode(data: data, scope: scope)
        } deferralForError: { error in
            switch error {
            case let .rateLimited(seconds) as MusicBrainzSearchError: .seconds(max(seconds, 1))
            case let .unavailable(seconds) as MusicBrainzSearchError: .seconds(max(seconds, 1))
            default: nil
            }
        }
    }

    /// Loads one concrete MusicBrainz release and its complete ordered media
    /// list. This is intentionally a single request; callers must never look
    /// up individual tracks to render a release page.
    func release(mbid: UUID, context: ReleaseSeed) async throws -> ReleaseDetail {
        try await gate.perform {
            let request = try Self.makeReleaseRequest(mbid: mbid, userAgent: userAgent)
            let (data, response) = try await Self.session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw MusicBrainzSearchError.invalidResponse }
            switch response.statusCode {
            case 200 ... 299: break
            case 429: throw MusicBrainzSearchError.rateLimited(retryAfter: Self.retryAfter(response))
            case 503: throw MusicBrainzSearchError.unavailable(retryAfter: Self.retryAfter(response))
            default: throw MusicBrainzSearchError.invalidResponse
            }
            return try Self.decodeRelease(data: data, mbid: mbid, context: context)
        } deferralForError: { error in
            switch error {
            case let .rateLimited(seconds) as MusicBrainzSearchError: .seconds(max(seconds, 1))
            case let .unavailable(seconds) as MusicBrainzSearchError: .seconds(max(seconds, 1))
            default: nil
            }
        }
    }

    static func makeRequest(query: String, scope: SearchScope, limit: Int, userAgent: String) throws -> URLRequest {
        let path: String = switch scope {
        case .artists: "artist"
        case .releaseGroups: "release-group"
        case .recordings: "recording"
        default: throw MusicBrainzSearchError.invalidResponse
        }
        var components = URLComponents(url: root.appending(path: path), resolvingAgainstBaseURL: false)!
        components.path += "/"
        components.queryItems = [
            .init(name: "query", value: escapeLuceneLiteral(query)),
            .init(name: "fmt", value: "json"),
            .init(name: "limit", value: String(min(max(limit, 1), 25))),
            .init(name: "offset", value: "0"),
        ]
        guard let url = components.url else { throw MusicBrainzSearchError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func makeReleaseRequest(mbid: UUID, userAgent: String) throws -> URLRequest {
        var components = URLComponents(url: root.appending(path: "release/\(mbid.uuidString.lowercased())"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "inc", value: "artist-credits+recordings+media+release-groups+labels"),
            .init(name: "fmt", value: "json"),
        ]
        guard let url = components.url else { throw MusicBrainzSearchError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func escapeLuceneLiteral(_ value: String) -> String {
        let special = CharacterSet(charactersIn: "+-&|!(){}[]^\"~*?:\\/")
        let escaped = value.unicodeScalars.reduce(into: "") { result, scalar in
            if special.contains(scalar) { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
        // An enclosing phrase also neutralizes Lucene's word operators
        // (AND, OR, NOT), keeping arbitrary user input a literal query.
        return "\"\(escaped)\""
    }

    static func retryAfter(_ response: HTTPURLResponse, now: Date = .now) -> Int {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return 1 }
        if let seconds = Int(value) { return max(seconds, 1) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return 1 }
        return max(Int(ceil(date.timeIntervalSince(now))), 1)
    }

    static func decode(data: Data, scope: SearchScope) throws -> [SearchResult] {
        let decoder = JSONDecoder()
        switch scope {
        case .artists:
            return try decoder.decode(ArtistEnvelope.self, from: data).artists.compactMap {
                guard let id = UUID(uuidString: $0.id) else { return nil }
                return .artist(.init(mbid: id, name: $0.name, listenCount: 0))
            }
        case .releaseGroups:
            return try decoder.decode(ReleaseGroupEnvelope.self, from: data).releaseGroups.compactMap {
                guard let id = UUID(uuidString: $0.id) else { return nil }
                return .releaseGroup(.init(
                    mbid: id, title: $0.title,
                    artistName: creditName($0.artistCredit ?? []),
                    primaryType: $0.primaryType, firstReleaseDate: $0.firstReleaseDate
                ))
            }
        case .recordings:
            return try decoder.decode(RecordingEnvelope.self, from: data).recordings.compactMap {
                guard let id = UUID(uuidString: $0.id) else { return nil }
                let credits = $0.artistCredit ?? []
                let release = $0.releases?.first
                return .recording(.init(
                    identity: .init(mbid: id, msid: nil), title: $0.title,
                    artistName: creditName(credits),
                    artistMBIDs: credits.compactMap { credit in
                        credit.artist.flatMap { UUID(uuidString: $0.id) }
                    },
                    releaseTitle: release?.title, releaseMBID: release?.id.flatMap(UUID.init(uuidString:)),
                    releaseGroupMBID: release?.releaseGroup?.id.flatMap(UUID.init(uuidString:)),
                    artworkReleaseMBID: release?.id.flatMap(UUID.init(uuidString:)),
                    durationMilliseconds: $0.length, source: nil
                ))
            }
        default: return []
        }
    }

    static func decodeRelease(data: Data, mbid: UUID, context: ReleaseSeed) throws -> ReleaseDetail {
        let value = try JSONDecoder().decode(ReleaseLookup.self, from: data)
        let creditedArtistName = creditName(value.artistCredit ?? [])
        let artistName = creditedArtistName.isEmpty ? context.artistName : creditedArtistName
        let releaseGroupMBID = value.releaseGroup?.id.flatMap(UUID.init(uuidString:)) ?? context.releaseGroupMBID
        let sourceMedia: [Medium] = value.media ?? []
        let orderedMedia = sourceMedia.enumerated().sorted { lhs, rhs in
            let leftPosition = lhs.element.position ?? lhs.offset + 1
            let rightPosition = rhs.element.position ?? rhs.offset + 1
            return leftPosition == rightPosition
                ? lhs.offset < rhs.offset
                : leftPosition < rightPosition
        }
        let media = orderedMedia.map { mediumIndex, medium in
            let sourceTracks: [Track] = medium.tracks ?? []
            let orderedTracks = sourceTracks.enumerated().sorted { lhs, rhs in
                let leftPosition = lhs.element.position ?? lhs.offset + 1
                let rightPosition = rhs.element.position ?? rhs.offset + 1
                return leftPosition == rightPosition
                    ? lhs.offset < rhs.offset
                    : leftPosition < rightPosition
            }
            let tracks = orderedTracks.map { trackIndex, track in
                let credits = track.artistCredit ?? value.artistCredit ?? []
                let creditedTrackArtist = creditName(credits)
                let trackArtist = creditedTrackArtist.isEmpty ? artistName : creditedTrackArtist
                let recordingID = track.recording?.id.flatMap(UUID.init(uuidString:))
                let recording = Recording(
                    identity: .init(mbid: recordingID, msid: nil),
                    title: track.recording?.title ?? track.title,
                    artistName: trackArtist,
                    artistMBIDs: credits.compactMap { credit in
                        guard let id = credit.artist?.id else { return nil }
                        return UUID(uuidString: id)
                    },
                    releaseTitle: value.title,
                    releaseMBID: mbid,
                    releaseGroupMBID: releaseGroupMBID,
                    artworkReleaseMBID: mbid,
                    durationMilliseconds: track.length ?? track.recording?.length,
                    source: nil
                )
                return ReleaseTrack(
                    position: track.position ?? trackIndex + 1,
                    number: track.number,
                    recording: recording
                )
            }
            return ReleaseMedium(
                position: medium.position ?? mediumIndex + 1,
                format: medium.format,
                title: medium.title,
                tracks: tracks
            )
        }
        return ReleaseDetail(
            mbid: mbid,
            title: value.title,
            artistCreditName: artistName,
            releaseDate: value.date ?? context.releaseDate,
            country: value.country,
            status: value.status,
            barcode: value.barcode,
            packaging: value.packaging,
            labels: (value.labelInfo ?? []).compactMap { $0.label?.name }.uniquePreservingOrder(),
            releaseGroupMBID: releaseGroupMBID,
            releaseGroupPrimaryType: value.releaseGroup?.primaryType ?? context.primaryType,
            media: media
        )
    }

    private static func creditName(_ credits: [Credit]) -> String {
        credits.map { $0.name + ($0.joinPhrase ?? "") }.joined()
    }

    private struct ArtistEnvelope: Decodable { let artists: [Artist] }
    private struct Artist: Decodable { let id: String; let name: String }
    private struct ReleaseGroupEnvelope: Decodable {
        let releaseGroups: [ReleaseGroup]
        enum CodingKeys: String, CodingKey { case releaseGroups = "release-groups" }
    }
    private struct ReleaseGroup: Decodable {
        let id: String; let title: String; let artistCredit: [Credit]?; let primaryType: String?; let firstReleaseDate: String?
        enum CodingKeys: String, CodingKey { case id, title, artistCredit = "artist-credit", primaryType = "primary-type", firstReleaseDate = "first-release-date" }
    }
    private struct RecordingEnvelope: Decodable { let recordings: [MBRecording] }
    private struct MBRecording: Decodable {
        let id: String; let title: String; let artistCredit: [Credit]?; let releases: [MBRelease]?; let length: Int?
        enum CodingKeys: String, CodingKey { case id, title, artistCredit = "artist-credit", releases, length }
    }
    private struct Credit: Decodable {
        let name: String
        let artist: Artist?
        let joinPhrase: String?
        enum CodingKeys: String, CodingKey { case name, artist, joinPhrase = "joinphrase" }
    }
    private struct MBRelease: Decodable {
        let id: String?; let title: String?; let releaseGroup: MBReleaseGroup?
        enum CodingKeys: String, CodingKey { case id, title, releaseGroup = "release-group" }
    }
    private struct MBReleaseGroup: Decodable { let id: String? }
    private struct ReleaseLookup: Decodable {
        let title: String
        let artistCredit: [Credit]?
        let date: String?
        let country: String?
        let status: String?
        let barcode: String?
        let packaging: String?
        let labelInfo: [LabelInfo]?
        let releaseGroup: LookupReleaseGroup?
        let media: [Medium]?
        enum CodingKeys: String, CodingKey {
            case title, date, country, status, barcode, packaging, media
            case artistCredit = "artist-credit"
            case labelInfo = "label-info"
            case releaseGroup = "release-group"
        }
    }
    private struct LabelInfo: Decodable { let label: Label? }
    private struct Label: Decodable { let name: String? }
    private struct LookupReleaseGroup: Decodable {
        let id: String?
        let primaryType: String?
        enum CodingKeys: String, CodingKey {
            case id
            case primaryType = "primary-type"
        }
    }
    private struct Medium: Decodable {
        let position: Int?
        let format: String?
        let title: String?
        let tracks: [Track]?
    }
    private struct Track: Decodable {
        let position: Int?
        let number: String?
        let title: String
        let length: Int?
        let artistCredit: [Credit]?
        let recording: LookupRecording?
        enum CodingKeys: String, CodingKey {
            case position, number, title, length, recording
            case artistCredit = "artist-credit"
        }
    }
    private struct LookupRecording: Decodable { let id: String?; let title: String?; let length: Int? }
}

private extension Array where Element == String {
    func uniquePreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
