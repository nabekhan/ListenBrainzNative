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

enum ArtistPageContextCacheValue: Sendable {
    case response(ArtistPageContext?)
    case failure(SimilarArtistsProviderError)
}

/// Artist Detail already needs the broad public artist-page response for its
/// highlights. These adapters project its community fields into the existing
/// reusable components without adding authenticated fallback requests.
struct ArtistPageContextPopularityProvider: PopularityProviding {
    private let contextProvider: any ArtistPageContextProviding

    init(contextProvider: some ArtistPageContextProviding) {
        self.contextProvider = contextProvider
    }

    func popularity(for entity: PopularityEntity) async throws -> GlobalPopularity {
        guard entity.kind == .artist else {
            return GlobalPopularity(entity: entity, totalListenCount: nil, totalUserCount: nil)
        }
        do {
            return try await contextProvider.context(
                for: entity.mbid,
                forceRefresh: false
            )?.popularity ?? GlobalPopularity(
                entity: entity,
                totalListenCount: nil,
                totalUserCount: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Artist Detail owns the page-level retry UI. A transport failure must
            // not fan out into a hidden call to the dedicated popularity API.
            return GlobalPopularity(entity: entity, totalListenCount: nil, totalUserCount: nil)
        }
    }
}

struct ArtistPageContextTopListenersProvider: TopListenersProviding {
    private let contextProvider: any ArtistPageContextProviding

    init(contextProvider: some ArtistPageContextProviding) {
        self.contextProvider = contextProvider
    }

    func topListeners(for entity: TopListenersEntity) async throws -> TopListeners? {
        guard entity.kind == .artist else { return nil }
        do {
            return try await contextProvider.context(
                for: entity.mbid,
                forceRefresh: false
            )?.topListeners
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Do not turn one failed page read into an automatic endpoint
            // fallback. The rest of Artist Detail remains usable.
            return nil
        }
    }
}

enum SimilarArtistsProviderError: LocalizedError, Sendable {
    case invalidResponse
    case responseTooLarge
    case rateLimited(retryAfter: Int)
    case unavailable(retryAfter: Int)
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: String(localized: "ListenBrainz sent an unreadable artist response.")
        case .responseTooLarge: String(localized: "ListenBrainz returned too much artist data.")
        case let .rateLimited(seconds): String(localized: "ListenBrainz is busy. Try again in about \(seconds) seconds.")
        case let .unavailable(seconds): String(localized: "ListenBrainz is temporarily unavailable. Try again in about \(seconds) seconds.")
        case .server: String(localized: "ListenBrainz couldn’t load these artist details.")
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
    private let cache: EntityDetailCache<UUID, ArtistPageContextCacheValue>
    private let transport: @Sendable (UUID) async throws -> Data?

    init(
        gate: RequestGate = .shared,
        cache: EntityDetailCache<UUID, ArtistPageContextCacheValue> = ArtistPageContextCaches.values
    ) {
        self.gate = gate
        self.cache = cache
        transport = SimilarArtistsTransport.load
    }

    init(
        gate: RequestGate,
        cache: EntityDetailCache<UUID, ArtistPageContextCacheValue> = .init(timeToLive: 2 * 60),
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
            switch cached.value {
            case let .response(value): return value
            case let .failure(error): throw error
            }
        }

        return try await gate.read(
            for: .artistPageContext(.anonymous, artistMBID: artistMBID)
        ) {
            // A caller can miss the fast-path cache and reach this closure just
            // after an earlier flight completes. Recheck here, and publish the
            // result before the request key drains, so that race cannot start a
            // duplicate transport.
            if !forceRefresh,
               let cached = await cache.value(for: artistMBID),
               cached.isFresh
            {
                switch cached.value {
                case let .response(value): return value
                case let .failure(error): throw error
                }
            }

            let stale: ArtistPageContext?
            if !forceRefresh,
               let cached = await cache.value(for: artistMBID),
               case let .response(value) = cached.value
            {
                stale = value
            } else {
                stale = nil
            }

            do {
                let value: ArtistPageContext?
                if let data = try await transport(artistMBID) {
                    value = try ArtistPageContextDecoder.decode(
                        data,
                        sourceArtistMBID: artistMBID
                    )
                } else {
                    value = nil
                }
                await cache.save(.response(value), for: artistMBID)
                return value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let stale {
                    await cache.save(.response(stale), for: artistMBID)
                    return stale
                }
                // Preserve failure as failure so the page owner always presents
                // its retry control, even when a child awaited the request first.
                let cachedError = error as? SimilarArtistsProviderError
                    ?? .server(status: 0)
                await cache.save(.failure(cachedError), for: artistMBID)
                throw error
            }
        } deferralForError: { error in
            switch error {
            case let SimilarArtistsProviderError.rateLimited(seconds): .seconds(max(seconds, 1))
            case let SimilarArtistsProviderError.unavailable(seconds): .seconds(max(seconds, 1))
            default: nil
            }
        }
    }
}

struct ListenBrainzSimilarArtistsProvider: SimilarArtistsProviding {
    private let contextProvider: any ArtistPageContextProviding
    private let suppressesErrors: Bool

    init(gate: RequestGate = .shared) {
        contextProvider = ListenBrainzArtistPageContextProvider(gate: gate)
        suppressesErrors = false
    }

    init(
        gate: RequestGate,
        transport: @escaping @Sendable (UUID) async throws -> Data?
    ) {
        contextProvider = ListenBrainzArtistPageContextProvider(
            gate: gate,
            transport: transport
        )
        suppressesErrors = false
    }

    init(
        contextProvider: some ArtistPageContextProviding,
        suppressesErrors: Bool = false
    ) {
        self.contextProvider = contextProvider
        self.suppressesErrors = suppressesErrors
    }

    func similarArtists(to artistMBID: UUID) async throws -> SimilarArtists? {
        do {
            return try await contextProvider.context(
                for: artistMBID,
                forceRefresh: false
            )?.similarArtists
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if suppressesErrors { return nil }
            throw error
        }
    }
}

struct ListenBrainzArtistHighlightsProvider: ArtistHighlightsProviding {
    private let contextProvider: any ArtistPageContextProviding
    private let suppressesErrors: Bool

    init(gate: RequestGate = .shared) {
        contextProvider = ListenBrainzArtistPageContextProvider(gate: gate)
        suppressesErrors = false
    }

    init(
        contextProvider: some ArtistPageContextProviding,
        suppressesErrors: Bool = false
    ) {
        self.contextProvider = contextProvider
        self.suppressesErrors = suppressesErrors
    }

    func highlights(for artistMBID: UUID, forceRefresh: Bool = false) async throws -> ArtistHighlights? {
        do {
            let highlights = try await contextProvider.context(
                for: artistMBID,
                forceRefresh: forceRefresh
            )?.highlights
            return highlights?.hasVisibleContent == true ? highlights : nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if suppressesErrors { return nil }
            throw error
        }
    }
}

enum ArtistPageContextDecoder {
    static let maximumCoverArtBytes = 512 * 1_024
    static let maximumTopListenerCount = 10

    static func decode(_ data: Data, sourceArtistMBID: UUID) throws -> ArtistPageContext {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimilarArtistsProviderError.invalidResponse
        }

        let rawArtist = root["artist"] as? [String: Any]
        try validateIdentity(
            values: [rawArtist?["artist_mbid"], rawArtist?["mbid"]],
            sourceArtistMBID: sourceArtistMBID
        )
        let identity = decodeIdentity(rawArtist, sourceArtistMBID: sourceArtistMBID)
        let rootArtistName = identity?.name
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
        let community = try decodeCommunityContext(
            root["listeningStats"],
            sourceArtistMBID: sourceArtistMBID
        )

        return ArtistPageContext(
            artistMBID: sourceArtistMBID,
            identity: identity,
            coverArtSVG: decodeCoverArt(root["coverArt"]),
            popularity: community.popularity,
            topListeners: community.topListeners,
            highlights: ArtistHighlights(
                artistMBID: sourceArtistMBID,
                recordings: recordings,
                releaseGroups: releaseGroups
            ),
            similarArtists: similarArtists
        )
    }

    private static func validateIdentity(
        values: [Any?],
        sourceArtistMBID: UUID
    ) throws {
        for value in values.compactMap({ $0 }) where !(value is NSNull) {
            guard uuid(value) == sourceArtistMBID else {
                throw SimilarArtistsProviderError.invalidResponse
            }
        }
    }

    private static func decodeIdentity(
        _ value: [String: Any]?,
        sourceArtistMBID: UUID
    ) -> ArtistPageIdentity? {
        guard let value else { return nil }
        let identity = ArtistPageIdentity(
            artistMBID: sourceArtistMBID,
            name: displayText(value["name"]),
            type: displayText(value["type"]),
            area: displayText(value["area"]),
            beginYear: year(value["begin_year"]),
            endYear: year(value["end_year"])
        )
        guard identity.name != nil
                || identity.type != nil
                || identity.area != nil
                || identity.beginYear != nil
                || identity.endYear != nil
        else { return nil }
        return identity
    }

    private static func decodeCommunityContext(
        _ value: Any?,
        sourceArtistMBID: UUID
    ) throws -> (popularity: GlobalPopularity?, topListeners: TopListeners?) {
        guard let value = value as? [String: Any] else { return (nil, nil) }
        try validateIdentity(
            values: [value["artist_mbid"]],
            sourceArtistMBID: sourceArtistMBID
        )

        if let range = displayText(value["range"] ?? value["stats_range"]),
           range != "all_time"
        {
            return (nil, nil)
        }

        let entity = PopularityEntity(kind: .artist, mbid: sourceArtistMBID)
        let totalListenCount = nonnegativeInteger(value["total_listen_count"])
        let totalUserCount = nonnegativeInteger(value["total_user_count"])
        let popularity = totalListenCount == nil && totalUserCount == nil
            ? nil
            : GlobalPopularity(
                entity: entity,
                totalListenCount: totalListenCount,
                totalUserCount: totalUserCount
            )

        let listenerRows = (value["listeners"] as? [Any]) ?? []
        var listeners: [TopListener] = []
        listeners.reserveCapacity(min(listenerRows.count, maximumTopListenerCount))
        for raw in listenerRows {
            guard listeners.count < maximumTopListenerCount else { break }
            guard let row = raw as? [String: Any],
                  let username = displayText(row["user_name"], maximumLength: 255),
                  let listenCount = nonnegativeInteger(row["listen_count"])
            else { continue }
            listeners.append(TopListener(username: username, listenCount: listenCount))
        }
        let topListeners = listeners.isEmpty
            ? nil
            : TopListeners(
                entity: TopListenersEntity(kind: .artist, mbid: sourceArtistMBID),
                listeners: listeners,
                totalListenCount: totalListenCount
            )
        return (popularity, topListeners)
    }

    private static func decodeCoverArt(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.count <= maximumCoverArtBytes,
              isSVG(value),
              SVGArtworkRenderingPolicy.permitsExternalResources(in: value)
        else { return nil }
        return value
    }

    private static func isSVG(_ value: String) -> Bool {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        if trimmed.range(of: "<svg", options: [.anchored, .caseInsensitive]) != nil {
            return true
        }
        guard trimmed.range(of: "<?xml", options: [.anchored, .caseInsensitive]) != nil,
              let declarationEnd = trimmed.range(of: "?>")?.upperBound
        else { return false }
        return trimmed[declarationEnd...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: "<svg", options: [.anchored, .caseInsensitive]) != nil
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

    private static func year(_ value: Any?) -> Int? {
        nonnegativeInteger(value).flatMap { (1 ... 9_999).contains($0) ? $0 : nil }
    }

    private static func displayText(
        _ value: Any?,
        maximumLength: Int = 500
    ) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maximumLength))
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
    /// Missing responses and failures remain distinguishable while both form
    /// a brief negative cache, preventing independently mounted sections from
    /// retrying or hiding the page-owned recovery action.
    static let values = EntityDetailCache<UUID, ArtistPageContextCacheValue>(
        timeToLive: 2 * 60,
        maximumEntryCount: 100
    )
}
