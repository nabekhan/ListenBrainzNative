import Foundation

protocol SimilarArtistsProviding: Sendable {
    func similarArtists(to artistMBID: UUID) async throws -> SimilarArtists?
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
        case .server: "ListenBrainz couldn’t load similar artists."
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

struct ListenBrainzSimilarArtistsProvider: SimilarArtistsProviding {
    private let gate: RequestGate
    private let transport: @Sendable (UUID) async throws -> Data?

    init(gate: RequestGate = .shared) {
        self.gate = gate
        transport = SimilarArtistsTransport.load
    }

    init(
        gate: RequestGate,
        transport: @escaping @Sendable (UUID) async throws -> Data?
    ) {
        self.gate = gate
        self.transport = transport
    }

    func similarArtists(to artistMBID: UUID) async throws -> SimilarArtists? {
        let data: Data? = try await gate.read(for: .similarArtists(.anonymous, artistMBID: artistMBID)) {
            try await transport(artistMBID)
        } deferralForError: { error in
            switch error {
            case let SimilarArtistsProviderError.rateLimited(seconds): .seconds(max(seconds, 1))
            case let SimilarArtistsProviderError.unavailable(seconds): .seconds(max(seconds, 1))
            default: nil
            }
        }
        guard let data else { return nil }
        return try SimilarArtistsDecoder.decode(data, sourceArtistMBID: artistMBID)
    }
}

enum SimilarArtistsDecoder {
    static func decode(_ data: Data, sourceArtistMBID: UUID) throws -> SimilarArtists? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimilarArtistsProviderError.invalidResponse
        }
        // This response belongs to a website route rather than the documented
        // API. A missing shelf is treated as unavailable so schema drift does
        // not break the rest of an artist page.
        guard let container = root["similarArtists"] as? [String: Any],
              let rawArtists = container["artists"] as? [Any]
        else { return nil }

        let artists = rawArtists.compactMap { raw -> SimilarArtist? in
            guard let row = raw as? [String: Any],
                  let identifier = row["artist_mbid"] as? String,
                  let mbid = UUID(uuidString: identifier),
                  let name = row["name"] as? String
            else { return nil }
            return SimilarArtist(mbid: mbid, name: name, score: number(row["score"]))
        }
        let value = SimilarArtists(sourceArtistMBID: sourceArtistMBID, artists: artists)
        return value.hasVisibleContent ? value : nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard !(value is Bool) else { return nil }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

enum SimilarArtistsCaches {
    /// Mirrors the public artist page's current `s-maxage=120` cache policy.
    static let values = EntityDetailCache<SimilarArtistsCacheKey, SimilarArtists>(
        timeToLive: 2 * 60,
        maximumEntryCount: 100
    )
}
