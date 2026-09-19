import Foundation

protocol SimilarArtistsProviding: Sendable {
    func similarArtists(to artistMBID: UUID) async throws -> SimilarArtists?
}

protocol ArtistHighlightsProviding: Sendable {
    func highlights(for artistMBID: UUID, forceRefresh: Bool) async throws -> ArtistHighlights?
}

protocol ArtistPageContextProviding: Sendable {
    func context(for artistMBID: UUID, forceRefresh: Bool) async throws -> ArtistPageContext?
}

enum SimilarArtistsProviderError: LocalizedError, Sendable {
    case invalidResponse
    case responseTooLarge
    case rateLimited(retryAfter: Int)
    case unavailable(retryAfter: Int)
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "ListenBrainz sent an unreadable artist response."
        case .responseTooLarge: "ListenBrainz returned too much artist data."
        case let .rateLimited(seconds): "ListenBrainz is busy. Try again in about \(seconds) seconds."
        case let .unavailable(seconds): "ListenBrainz is temporarily unavailable. Try again in about \(seconds) seconds."
        case .server: "ListenBrainz couldn’t load these artist details."
        }
    }
}

/// A narrow adapter around the public artist-page response used by the current
/// ListenBrainz website and official Android client. This is intentionally kept
/// separate from the documented API layer so it can be replaced if that page
/// contract changes.
enum SimilarArtistsTransport {
    enum ResponseDisposition: Equatable {
        case readBody
        case unavailable
    }

    static let maximumResponseBytes = 4 * 1_024 * 1_024
    static let maximumRetryAfterSeconds = 3_600
    private static let redirectDelegate = SameOriginRedirectDelegate()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
    }()

    static func request(for artistMBID: UUID) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "listenbrainz.org"
        components.path = "/artist/\(artistMBID.uuidString.lowercased())/"

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    static func load(artistMBID: UUID) async throws -> Data? {
        let request = request(for: artistMBID)
        let (bytes, response) = try await session.bytes(for: request)
        guard try responseDisposition(response) == .readBody else { return nil }

        var data = Data()
        data.reserveCapacity(min(maximumResponseBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            if data.count > maximumResponseBytes {
                throw SimilarArtistsProviderError.responseTooLarge
            }
        }
        return data
    }

    static func responseDisposition(_ response: URLResponse) throws -> ResponseDisposition {
        guard let http = response as? HTTPURLResponse,
              http.url?.scheme?.lowercased() == "https",
              http.url?.host?.lowercased() == "listenbrainz.org",
              http.url?.user == nil,
              http.url?.password == nil,
              http.url?.port == nil || http.url?.port == 443
        else { throw SimilarArtistsProviderError.invalidResponse }

        switch http.statusCode {
        case 200...299: break
        case 400, 404: return .unavailable
        case 429: throw SimilarArtistsProviderError.rateLimited(retryAfter: retryAfter(http))
        case 503: throw SimilarArtistsProviderError.unavailable(retryAfter: retryAfter(http))
        default: throw SimilarArtistsProviderError.server(status: http.statusCode)
        }

        guard let mimeType = http.mimeType?.lowercased(),
              mimeType == "application/json" || mimeType.hasSuffix("+json")
        else { throw SimilarArtistsProviderError.invalidResponse }
        if http.expectedContentLength > Int64(maximumResponseBytes) {
            throw SimilarArtistsProviderError.responseTooLarge
        }
        return .readBody
    }

    static func allowsRedirect(to url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "listenbrainz.org",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443
        else { return false }
        return true
    }

    static func retryAfter(_ response: HTTPURLResponse, now: Date = .now) -> Int {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return 1 }
        if let seconds = Int(value) {
            return min(max(seconds, 1), maximumRetryAfterSeconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return 1 }
        return min(max(Int(ceil(date.timeIntervalSince(now))), 1), maximumRetryAfterSeconds)
    }

    private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(SimilarArtistsTransport.allowsRedirect(to: request.url) ? request : nil)
        }
    }
}

struct ListenBrainzArtistPageContextProvider: ArtistPageContextProviding {
    private let gate: RequestGate
    private let cache: EntityDetailCache<UUID, ArtistPageContext?>
    private let transport: @Sendable (UUID) async throws -> Data?

    init(
        gate: RequestGate = .shared,
        cache: EntityDetailCache<UUID, ArtistPageContext?> = ArtistPageContextCaches.values
    ) {
        self.gate = gate
        self.cache = cache
        transport = SimilarArtistsTransport.load
    }

    init(
        gate: RequestGate,
        cache: EntityDetailCache<UUID, ArtistPageContext?> = .init(timeToLive: 2 * 60),
        transport: @escaping @Sendable (UUID) async throws -> Data?
    ) {
        self.gate = gate
        self.cache = cache
        self.transport = transport
    }

    func context(for artistMBID: UUID, forceRefresh: Bool = false) async throws -> ArtistPageContext? {
        if forceRefresh {
            await cache.removeValue(for: artistMBID)
        } else if let cached = await cache.value(for: artistMBID), cached.isFresh {
            return cached.value
        }

        let stale = forceRefresh ? nil : await cache.value(for: artistMBID)?.value
        do {
            let data: Data? = try await gate.read(
                for: .artistPageContext(.anonymous, artistMBID: artistMBID)
            ) {
                try await transport(artistMBID)
            } deferralForError: { error in
                switch error {
                case let SimilarArtistsProviderError.rateLimited(seconds): .seconds(max(seconds, 1))
                case let SimilarArtistsProviderError.unavailable(seconds): .seconds(max(seconds, 1))
                default: nil
                }
            }

            let value = try data.map {
                try ArtistPageContextDecoder.decode($0, sourceArtistMBID: artistMBID)
            }
            await cache.save(value, for: artistMBID)
            return value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A brief shared negative cache prevents independently mounted
            // artist sections from amplifying the same failing page request.
            await cache.save(stale, for: artistMBID)
            if let stale { return stale }
            throw error
        }
    }
}

struct ListenBrainzSimilarArtistsProvider: SimilarArtistsProviding {
    private let contextProvider: any ArtistPageContextProviding

    init(gate: RequestGate = .shared) {
        contextProvider = ListenBrainzArtistPageContextProvider(gate: gate)
    }

    init(
        gate: RequestGate,
        transport: @escaping @Sendable (UUID) async throws -> Data?
    ) {
        contextProvider = ListenBrainzArtistPageContextProvider(
            gate: gate,
            transport: transport
        )
    }

    init(contextProvider: some ArtistPageContextProviding) {
        self.contextProvider = contextProvider
    }

    func similarArtists(to artistMBID: UUID) async throws -> SimilarArtists? {
        try await contextProvider.context(for: artistMBID, forceRefresh: false)?.similarArtists
    }
}

struct ListenBrainzArtistHighlightsProvider: ArtistHighlightsProviding {
    private let contextProvider: any ArtistPageContextProviding

    init(gate: RequestGate = .shared) {
        contextProvider = ListenBrainzArtistPageContextProvider(gate: gate)
    }

    init(contextProvider: some ArtistPageContextProviding) {
        self.contextProvider = contextProvider
    }

    func highlights(for artistMBID: UUID, forceRefresh: Bool = false) async throws -> ArtistHighlights? {
        let highlights = try await contextProvider.context(
            for: artistMBID,
            forceRefresh: forceRefresh
        )?.highlights
        return highlights?.hasVisibleContent == true ? highlights : nil
    }
}

enum ArtistPageContextDecoder {
    static func decode(_ data: Data, sourceArtistMBID: UUID) throws -> ArtistPageContext {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimilarArtistsProviderError.invalidResponse
        }

        if let echoedIdentifier = (root["artist"] as? [String: Any])?["artist_mbid"] {
            guard uuid(echoedIdentifier) == sourceArtistMBID else {
                throw SimilarArtistsProviderError.invalidResponse
            }
        }

        let rootArtistName = ((root["artist"] as? [String: Any])?["name"] as? String)
            .flatMap(displayText)
        let recordings = decodeRecordings(
            root["popularRecordings"],
            sourceArtistMBID: sourceArtistMBID,
            fallbackArtistName: rootArtistName
        )
        let releaseGroups = decodeReleaseGroups(
            root["releaseGroups"],
            fallbackArtistName: rootArtistName
        )
        let similarArtists = decodeSimilarArtists(
            root["similarArtists"],
            sourceArtistMBID: sourceArtistMBID
        )

        return ArtistPageContext(
            artistMBID: sourceArtistMBID,
            highlights: ArtistHighlights(
                artistMBID: sourceArtistMBID,
                recordings: recordings,
                releaseGroups: releaseGroups
            ),
            similarArtists: similarArtists
        )
    }

    private static func decodeRecordings(
        _ value: Any?,
        sourceArtistMBID: UUID,
        fallbackArtistName: String?
    ) -> [ArtistPopularRecording] {
        guard let rows = value as? [Any] else { return [] }
        var seen: Set<UUID> = []
        var result: [ArtistPopularRecording] = []
        result.reserveCapacity(min(rows.count, ArtistHighlights.maximumRecordingCount))
        for raw in rows {
            guard result.count < ArtistHighlights.maximumRecordingCount else { break }
            guard let row = raw as? [String: Any],
                  let recordingMBID = uuid(row["recording_mbid"]),
                  let title = displayText(row["recording_name"]),
                  let artistName = displayText(row["artist_name"]) ?? fallbackArtistName
            else { continue }
            guard seen.insert(recordingMBID).inserted else { continue }

            let listedArtistMBIDs = uuids(row["artist_mbids"])
            let artistMBIDs = listedArtistMBIDs.isEmpty ? [sourceArtistMBID] : listedArtistMBIDs
            let releaseMBID = uuid(row["release_mbid"])
            result.append(ArtistPopularRecording(
                recordingMBID: recordingMBID,
                title: title,
                artistName: artistName,
                artistMBIDs: artistMBIDs,
                releaseTitle: displayText(row["release_name"]),
                releaseMBID: releaseMBID,
                artworkReleaseMBID: uuid(row["caa_release_mbid"]) ?? releaseMBID,
                durationMilliseconds: nonnegativeInteger(row["length"]),
                totalListenCount: nonnegativeInteger(row["total_listen_count"]),
                totalUserCount: nonnegativeInteger(row["total_user_count"])
            ))
        }
        return result
    }

    private static func decodeReleaseGroups(
        _ value: Any?,
        fallbackArtistName: String?
    ) -> [ArtistPopularReleaseGroup] {
        guard let rows = value as? [Any] else { return [] }
        var seen: Set<UUID> = []
        var result: [ArtistPopularReleaseGroup] = []
        result.reserveCapacity(min(rows.count, ArtistHighlights.maximumReleaseGroupCount))
        for raw in rows {
            guard result.count < ArtistHighlights.maximumReleaseGroupCount else { break }
            guard let row = raw as? [String: Any],
                  let mbid = uuid(row["mbid"]),
                  let title = displayText(row["name"]),
                  let artistName = displayText(row["artist_credit_name"]) ?? fallbackArtistName
            else { continue }
            guard seen.insert(mbid).inserted else { continue }

            result.append(ArtistPopularReleaseGroup(
                mbid: mbid,
                title: title,
                artistName: artistName,
                primaryType: displayText(row["type"]),
                firstReleaseDate: displayText(row["date"]),
                artworkReleaseMBID: uuid(row["caa_release_mbid"]),
                totalListenCount: nonnegativeInteger(row["total_listen_count"]),
                totalUserCount: nonnegativeInteger(row["total_user_count"])
            ))
        }
        return result
    }

    private static func decodeSimilarArtists(
        _ value: Any?,
        sourceArtistMBID: UUID
    ) -> SimilarArtists? {
        guard let container = value as? [String: Any],
              let rawArtists = container["artists"] as? [Any]
        else { return nil }

        var seen: Set<UUID> = [sourceArtistMBID]
        var artists: [SimilarArtist] = []
        artists.reserveCapacity(min(rawArtists.count, SimilarArtists.maximumCount))
        for raw in rawArtists {
            guard artists.count < SimilarArtists.maximumCount else { break }
            guard let row = raw as? [String: Any],
                  let mbid = uuid(row["artist_mbid"]),
                  let name = displayText(row["name"])
            else { continue }
            guard seen.insert(mbid).inserted else { continue }
            artists.append(SimilarArtist(mbid: mbid, name: name, score: number(row["score"])))
        }
        let value = SimilarArtists(sourceArtistMBID: sourceArtistMBID, artists: artists)
        return value.hasVisibleContent ? value : nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard !(value is Bool) else { return nil }
        if let value = value as? NSNumber { return Double(value.stringValue) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func nonnegativeInteger(_ value: Any?) -> Int? {
        guard !(value is Bool) else { return nil }
        let result: Int?
        if let value = value as? NSNumber {
            result = Int(value.stringValue)
        } else if let value = value as? String {
            result = Int(value)
        } else {
            result = nil
        }
        return result.flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func uuid(_ value: Any?) -> UUID? {
        guard let value = value as? String else { return nil }
        return UUID(uuidString: value)
    }

    private static func uuids(_ value: Any?) -> [UUID] {
        guard let values = value as? [Any] else { return [] }
        var seen: Set<UUID> = []
        var result: [UUID] = []
        for raw in values {
            guard result.count < 20 else { break }
            guard let value = uuid(raw), seen.insert(value).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func displayText(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(500))
    }
}

enum SimilarArtistsDecoder {
    static func decode(_ data: Data, sourceArtistMBID: UUID) throws -> SimilarArtists? {
        try ArtistPageContextDecoder.decode(data, sourceArtistMBID: sourceArtistMBID).similarArtists
    }
}

enum SimilarArtistsCaches {
    /// Mirrors the public artist page's current `s-maxage=120` cache policy.
    static let values = EntityDetailCache<SimilarArtistsCacheKey, SimilarArtists>(
        timeToLive: 2 * 60,
        maximumEntryCount: 100
    )
}

enum ArtistPageContextCaches {
    /// Mirrors the public artist page's current `s-maxage=120` cache policy.
    /// Optional values also form a brief negative cache for missing/failed
    /// responses, preventing independently mounted sections from retrying.
    static let values = EntityDetailCache<UUID, ArtistPageContext?>(
        timeToLive: 2 * 60,
        maximumEntryCount: 100
    )
}
