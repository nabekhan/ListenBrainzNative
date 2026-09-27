import Foundation
import ListenBrainzKit

protocol SearchProviding: Sendable {
    func search(query: String, scope: SearchScope) async throws -> [SearchResult]
    func searchPage(
        query: String,
        scope: SearchScope,
        offset: Int,
        limit: Int
    ) async throws -> SearchPage
}

extension SearchProviding {
    /// Keeps focused fixtures and lightweight consumers source-compatible.
    /// Providers that expose real paging override this method.
    func searchPage(
        query: String,
        scope: SearchScope,
        offset: Int,
        limit _: Int
    ) async throws -> SearchPage {
        guard offset <= 0 else {
            return .init(
                results: [],
                offset: max(offset, 0),
                rawResultCount: 0,
                totalResultCount: nil,
                allowsPagination: false
            )
        }
        return .single(try await search(query: query, scope: scope))
    }
}

struct SearchProvider: SearchProviding {
    static let maximumPageSize = 25

    private let listenBrainz: LBClient
    private let musicBrainz: MusicBrainzSearchClient
    private let listenBrainzGate: RequestGate
    private let listenBrainzReadScope: RequestGate.ReadScope

    init(
        token _: String,
        listenBrainzGate: RequestGate = .shared,
        musicBrainz: MusicBrainzSearchClient = .init()
    ) {
        // Both ListenBrainz search endpoints are public. Deliberately omit the
        // viewer token so identical reads can share one anonymous gate scope.
        self.listenBrainz = LBClient(
            token: "",
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        self.listenBrainzGate = listenBrainzGate
        listenBrainzReadScope = .anonymous
        self.musicBrainz = musicBrainz
    }

    func search(query: String, scope: SearchScope) async throws -> [SearchResult] {
        try await searchPage(
            query: query,
            scope: scope,
            offset: 0,
            limit: Self.maximumPageSize
        ).results
    }

    func searchPage(
        query: String,
        scope: SearchScope,
        offset: Int,
        limit: Int
    ) async throws -> SearchPage {
        let effectiveQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveOffset = max(offset, 0)
        let effectiveLimit = min(max(limit, 1), Self.maximumPageSize)

        switch scope {
        case .artists, .releaseGroups, .recordings:
            return try await musicBrainz.searchPage(
                query: effectiveQuery,
                scope: scope,
                offset: effectiveOffset,
                limit: effectiveLimit
            )
        case .users:
            guard effectiveOffset == 0 else {
                return .init(
                    results: [],
                    offset: effectiveOffset,
                    rawResultCount: 0,
                    totalResultCount: nil,
                    allowsPagination: false
                )
            }
            let results: [SearchResult] = try await performListenBrainz(
                .searchUsers(listenBrainzReadScope, query: effectiveQuery)
            ) {
                try await listenBrainz.core.searchUser(term: effectiveQuery).map {
                    SearchResult.user(.init(username: $0))
                }
            }
            return .single(results)
        case .playlists:
            guard effectiveQuery.count >= scope.minimumQueryLength else { return .single([]) }
            let page = try await performListenBrainz(
                .searchPlaylists(
                    listenBrainzReadScope,
                    query: effectiveQuery,
                    offset: effectiveOffset,
                    count: effectiveLimit
                )
            ) {
                try await listenBrainz.core.searchPlaylistsPage(
                    query: effectiveQuery,
                    count: effectiveLimit,
                    offset: effectiveOffset
                )
            }
            if let serverOffset = page.offset, serverOffset != effectiveOffset {
                throw SearchProviderError.invalidResponse
            }
            if let requestedCount = page.requestedCount, requestedCount != effectiveLimit {
                throw SearchProviderError.invalidResponse
            }
            guard page.playlists.count <= effectiveLimit,
                  page.playlistCount.map({ $0 >= 0 }) != false
            else { throw SearchProviderError.invalidResponse }
            let results: [SearchResult] = page.playlists.map {
                    .playlist(.init(
                        title: $0.title,
                        creator: $0.creator,
                        annotation: $0.annotation,
                        identifier: $0.identifier,
                        isPublic: $0.isPublic,
                        lastModifiedAt: $0.lastModifiedAt
                    ))
            }
            return .init(
                results: results,
                offset: effectiveOffset,
                rawResultCount: page.playlists.count,
                totalResultCount: page.playlistCount,
                allowsPagination: page.offset != nil
                    && page.requestedCount != nil
                    && page.playlistCount != nil
            )
        }
    }

    private func performListenBrainz<Result: Sendable>(
        _ key: RequestGate.ReadKey,
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await listenBrainzGate.read(for: key, operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }
}

enum SearchProviderError: LocalizedError, Sendable {
    case invalidResponse

    var errorDescription: String? {
        String(localized: "Search results couldn’t load. Try again.")
    }
}

enum MusicBrainzSearchError: LocalizedError, Sendable {
    case rateLimited(retryAfter: Int)
    case unavailable(retryAfter: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .rateLimited(seconds): String(localized: "MusicBrainz is busy. Try again in about \(seconds) seconds.")
        case let .unavailable(seconds): String(localized: "MusicBrainz is temporarily unavailable. Try again in about \(seconds) seconds.")
        case .invalidResponse: String(localized: "MusicBrainz returned an unexpected response.")
        }
    }
}

struct MusicBrainzSearchClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let root = URL(string: "https://musicbrainz.org/ws/2")!
    // MusicBrainz is a separate service with its own one-request-per-second
    // policy. Keep its scheduling independent from ListenBrainz, but shared
    // by every search sheet in this app process.
    private static let sharedGate = makeRequestGate()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private let gate: RequestGate
    private let userAgent: String
    private let transport: Transport

    init(
        gate: RequestGate? = nil,
        userAgent: String = "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)",
        transport: Transport? = nil
    ) {
        self.gate = gate ?? Self.sharedGate
        self.userAgent = userAgent
        self.transport = transport ?? { request in
            try await MusicBrainzSearchClient.session.data(for: request)
        }
    }

    /// MusicBrainz requires clients to average no more than one request per
    /// second. Search pages and release lookups share this single paced lane;
    /// exact concurrent reads still coalesce instead of duplicating traffic.
    static func makeRequestGate(
        minimumInterval: Duration = .seconds(1)
    ) -> RequestGate {
        RequestGate(
            minimumInterval: minimumInterval,
            maximumConcurrentReads: 1,
            pacesReadStarts: true
        )
    }

    func search(query: String, scope: SearchScope, limit: Int = 20) async throws -> [SearchResult] {
        try await searchPage(query: query, scope: scope, offset: 0, limit: limit).results
    }

    func searchPage(
        query: String,
        scope: SearchScope,
        offset: Int,
        limit: Int = 20
    ) async throws -> SearchPage {
        guard scope == .artists || scope == .releaseGroups || scope == .recordings else {
            return .single([])
        }
        let effectiveQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveOffset = max(offset, 0)
        let effectiveLimit = min(max(limit, 1), SearchProvider.maximumPageSize)
        guard !effectiveQuery.isEmpty else { return .single([]) }
        return try await gate.read(
            for: .musicBrainzSearch(
                scope: scope.rawValue,
                query: effectiveQuery,
                offset: effectiveOffset,
                count: effectiveLimit
            )
        ) {
            let request = try Self.makeRequest(
                query: effectiveQuery,
                scope: scope,
                limit: effectiveLimit,
                offset: effectiveOffset,
                userAgent: userAgent
            )
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else { throw MusicBrainzSearchError.invalidResponse }
            switch response.statusCode {
            case 200 ... 299: break
            case 429: throw MusicBrainzSearchError.rateLimited(retryAfter: Self.retryAfter(response))
            case 503: throw MusicBrainzSearchError.unavailable(retryAfter: Self.retryAfter(response))
            default: throw MusicBrainzSearchError.invalidResponse
            }
            return try Self.decodePage(
                data: data,
                scope: scope,
                requestedOffset: effectiveOffset,
                requestedLimit: effectiveLimit
            )
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
        // Coalesce only the context-free wire response. Different native
        // entry points can carry different sparse fallback metadata for the
        // same canonical release and must each apply their own seed.
        let data: Data = try await gate.read(for: .musicBrainzRelease(mbid: mbid)) {
            let request = try Self.makeReleaseRequest(mbid: mbid, userAgent: userAgent)
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else { throw MusicBrainzSearchError.invalidResponse }
            switch response.statusCode {
            case 200 ... 299: break
            case 429: throw MusicBrainzSearchError.rateLimited(retryAfter: Self.retryAfter(response))
            case 503: throw MusicBrainzSearchError.unavailable(retryAfter: Self.retryAfter(response))
            default: throw MusicBrainzSearchError.invalidResponse
            }
            return data
        } deferralForError: { error in
            switch error {
            case let .rateLimited(seconds) as MusicBrainzSearchError: .seconds(max(seconds, 1))
            case let .unavailable(seconds) as MusicBrainzSearchError: .seconds(max(seconds, 1))
            default: nil
            }
        }
        try Task.checkCancellation()
        return try Self.decodeRelease(data: data, mbid: mbid, context: context)
    }

    static func makeRequest(
        query: String,
        scope: SearchScope,
        limit: Int,
        offset: Int = 0,
        userAgent: String
    ) throws -> URLRequest {
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
            .init(name: "offset", value: String(max(offset, 0))),
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
        try decodePayload(data: data, scope: scope).results
    }

    static func decodePage(
        data: Data,
        scope: SearchScope,
        requestedOffset: Int,
        requestedLimit: Int
    ) throws -> SearchPage {
        let payload = try decodePayload(data: data, scope: scope)
        let effectiveOffset = max(requestedOffset, 0)
        let effectiveLimit = min(max(requestedLimit, 1), SearchProvider.maximumPageSize)
        guard payload.rawResultCount <= effectiveLimit,
              payload.totalResultCount.map({ $0 >= 0 }) != false,
              payload.responseOffset.map({ $0 >= 0 && $0 == effectiveOffset }) != false
        else { throw MusicBrainzSearchError.invalidResponse }

        return SearchPage(
            results: payload.results,
            offset: effectiveOffset,
            rawResultCount: payload.rawResultCount,
            totalResultCount: payload.totalResultCount,
            allowsPagination: payload.responseOffset != nil
                && payload.totalResultCount != nil
        )
    }

    private static func decodePayload(data: Data, scope: SearchScope) throws -> DecodedSearchPayload {
        let decoder = JSONDecoder()
        switch scope {
        case .artists:
            let envelope = try decoder.decode(ArtistEnvelope.self, from: data)
            let results: [SearchResult] = envelope.artists.compactMap {
                guard let id = UUID(uuidString: $0.id) else { return nil }
                return .artist(.init(mbid: id, name: $0.name, listenCount: 0))
            }
            return .init(
                results: results,
                rawResultCount: envelope.artists.count,
                totalResultCount: envelope.count,
                responseOffset: envelope.offset
            )
        case .releaseGroups:
            let envelope = try decoder.decode(ReleaseGroupEnvelope.self, from: data)
            let results: [SearchResult] = envelope.releaseGroups.compactMap {
                guard let id = UUID(uuidString: $0.id) else { return nil }
                return .releaseGroup(.init(
                    mbid: id, title: $0.title,
                    artistName: creditName($0.artistCredit ?? []),
                    primaryType: $0.primaryType, firstReleaseDate: $0.firstReleaseDate
                ))
            }
            return .init(
                results: results,
                rawResultCount: envelope.releaseGroups.count,
                totalResultCount: envelope.count,
                responseOffset: envelope.offset
            )
        case .recordings:
            let envelope = try decoder.decode(RecordingEnvelope.self, from: data)
            let results: [SearchResult] = envelope.recordings.compactMap {
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
            return .init(
                results: results,
                rawResultCount: envelope.recordings.count,
                totalResultCount: envelope.count,
                responseOffset: envelope.offset
            )
        default:
            throw MusicBrainzSearchError.invalidResponse
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

    private struct DecodedSearchPayload {
        let results: [SearchResult]
        let rawResultCount: Int
        let totalResultCount: Int?
        let responseOffset: Int?
    }

    private struct ArtistEnvelope: Decodable {
        let count: Int?
        let offset: Int?
        let artists: [Artist]
    }
    private struct Artist: Decodable { let id: String; let name: String }
    private struct ReleaseGroupEnvelope: Decodable {
        let count: Int?
        let offset: Int?
        let releaseGroups: [ReleaseGroup]
        enum CodingKeys: String, CodingKey {
            case count, offset
            case releaseGroups = "release-groups"
        }
    }
    private struct ReleaseGroup: Decodable {
        let id: String; let title: String; let artistCredit: [Credit]?; let primaryType: String?; let firstReleaseDate: String?
        enum CodingKeys: String, CodingKey { case id, title, artistCredit = "artist-credit", primaryType = "primary-type", firstReleaseDate = "first-release-date" }
    }
    private struct RecordingEnvelope: Decodable {
        let count: Int?
        let offset: Int?
        let recordings: [MBRecording]
    }
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
