import Foundation

protocol CritiqueBrainzReviewsProviding: Sendable {
    func reviews(for entity: CritiqueBrainzEntity) async throws -> CritiqueBrainzReviewSummary?
    func reviewPage(for entity: CritiqueBrainzEntity, offset: Int, limit: Int) async throws -> CritiqueBrainzReviewPage?
}

extension CritiqueBrainzReviewsProviding {
    func reviewPage(for entity: CritiqueBrainzEntity, offset: Int, limit: Int) async throws -> CritiqueBrainzReviewPage? {
        throw CritiqueBrainzProviderError.invalidResponse
    }
}

enum CritiqueBrainzRequestGate {
    /// CritiqueBrainz has its own host and its own intentionally modest lane.
    static let shared = RequestGate(
        minimumInterval: .seconds(1),
        maximumConcurrentReads: 1,
        pacesReadStarts: true
    )
}

enum CritiqueBrainzProviderError: LocalizedError, Sendable {
    case invalidResponse
    case responseTooLarge
    case rateLimited(retryAfter: Int)
    case unavailable(retryAfter: Int)
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: String(localized: "CritiqueBrainz sent an unreadable response. Try again in a moment.")
        case .responseTooLarge: String(localized: "CritiqueBrainz returned too much review data. Try again in a moment.")
        case let .rateLimited(seconds): String(localized: "CritiqueBrainz is busy. Try again in about \(seconds) seconds.")
        case let .unavailable(seconds): String(localized: "CritiqueBrainz is temporarily unavailable. Try again in about \(seconds) seconds.")
        case .server: String(localized: "CritiqueBrainz couldn’t load reviews. Try again in a moment.")
        }
    }
}

enum CritiqueBrainzTransport {
    static let maximumResponseBytes = 256 * 1_024
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

    static func reviews(for entity: CritiqueBrainzEntity, offset: Int, limit: Int) async throws -> Data {
        var components = URLComponents(string: "https://critiquebrainz.org/ws/1/review/")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "sort", value: "published_on"),
            URLQueryItem(name: "sort_order", value: "desc"),
            URLQueryItem(name: "entity_id", value: entity.mbid.uuidString.lowercased()),
            URLQueryItem(name: "entity_type", value: entity.kind.rawValue),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)", forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              http.url?.scheme?.lowercased() == "https",
              http.url?.host?.lowercased() == "critiquebrainz.org"
        else { throw CritiqueBrainzProviderError.invalidResponse }
        switch http.statusCode {
        case 200...299: break
        case 429: throw CritiqueBrainzProviderError.rateLimited(retryAfter: retryAfter(http))
        case 503: throw CritiqueBrainzProviderError.unavailable(retryAfter: retryAfter(http))
        default: throw CritiqueBrainzProviderError.server(status: http.statusCode)
        }
        guard let mimeType = http.mimeType?.lowercased(),
              mimeType == "application/json" || mimeType.hasSuffix("+json")
        else { throw CritiqueBrainzProviderError.invalidResponse }
        if http.expectedContentLength > Int64(maximumResponseBytes) { throw CritiqueBrainzProviderError.responseTooLarge }

        var data = Data()
        data.reserveCapacity(min(maximumResponseBytes, max(0, Int(http.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            if data.count > maximumResponseBytes { throw CritiqueBrainzProviderError.responseTooLarge }
        }
        return data
    }

    static func allowsRedirect(to url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "critiquebrainz.org",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443
        else { return false }
        return true
    }

    static func retryAfter(_ response: HTTPURLResponse, now: Date = .now) -> Int {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return 1 }
        if let seconds = Int(value) { return min(max(seconds, 1), maximumRetryAfterSeconds) }

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
            completionHandler(CritiqueBrainzTransport.allowsRedirect(to: request.url) ? request : nil)
        }
    }
}

struct CritiqueBrainzReviewsProvider: CritiqueBrainzReviewsProviding {
    private static let reviewSort = "published_on"
    private static let reviewSortOrder = "desc"

    private let gate: RequestGate
    private let pageCache: EntityDetailCache<CritiqueBrainzReviewPageCacheKey, CritiqueBrainzReviewPage>
    private let transport: @Sendable (CritiqueBrainzEntity, Int, Int) async throws -> Data

    init(
        gate: RequestGate = CritiqueBrainzRequestGate.shared,
        pageCache: EntityDetailCache<CritiqueBrainzReviewPageCacheKey, CritiqueBrainzReviewPage> = CritiqueBrainzReviewCaches.pages
    ) {
        self.gate = gate
        self.pageCache = pageCache
        transport = CritiqueBrainzTransport.reviews
    }

    init(
        gate: RequestGate,
        pageCache: EntityDetailCache<CritiqueBrainzReviewPageCacheKey, CritiqueBrainzReviewPage> = CritiqueBrainzReviewCaches.pages,
        transport: @escaping @Sendable (CritiqueBrainzEntity, Int, Int) async throws -> Data
    ) {
        self.gate = gate
        self.pageCache = pageCache
        self.transport = transport
    }

    func reviews(for entity: CritiqueBrainzEntity) async throws -> CritiqueBrainzReviewSummary? {
        try await reviewPage(for: entity, offset: 0, limit: 5)?.summary
    }

    func reviewPage(for entity: CritiqueBrainzEntity, offset: Int, limit: Int) async throws -> CritiqueBrainzReviewPage? {
        guard offset >= 0, (1...50).contains(limit) else { throw CritiqueBrainzProviderError.invalidResponse }
        let cacheKey = CritiqueBrainzReviewPageCacheKey(
            entity: entity,
            offset: offset,
            limit: limit,
            sort: Self.reviewSort,
            sortOrder: Self.reviewSortOrder
        )
        if let cached = await pageCache.value(for: cacheKey), cached.isFresh {
            return cached.value
        }

        let data: Data = try await gate.read(for: .critiqueBrainzReviews(.anonymous, entity: entity, offset: offset, limit: limit, sort: Self.reviewSort, sortOrder: Self.reviewSortOrder)) {
            try await transport(entity, offset, limit)
        } deferralForError: { error in
            switch error {
            case let CritiqueBrainzProviderError.rateLimited(seconds): .seconds(max(seconds, 1))
            case let CritiqueBrainzProviderError.unavailable(seconds): .seconds(max(seconds, 1))
            default: nil
            }
        }
        let page = try CritiqueBrainzReviewDecoder.decodePage(
            data,
            for: entity,
            expectedOffset: offset,
            expectedLimit: limit
        )
        if let page {
            await pageCache.save(page, for: cacheKey)
        }
        return page
    }
}

enum CritiqueBrainzReviewDecoder {
    static func decode(_ data: Data, for entity: CritiqueBrainzEntity) throws -> CritiqueBrainzReviewSummary? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CritiqueBrainzProviderError.invalidResponse
        }
        guard let rawRows = root["reviews"] as? [Any] else {
            throw CritiqueBrainzProviderError.invalidResponse
        }
        let rows = rawRows.compactMap { $0 as? [String: Any] }
        let reviews = rows.compactMap { review(from: $0, expected: entity) }
        let averageObject = root["average_rating"] as? [String: Any]
        let average = number(root["average_rating"]) ?? number(averageObject?["rating"])
        let averageCount = integer(averageObject?["count"]) ?? 0
        // A rating aggregate remains meaningful even if this short page has
        // no text reviews, but only when the server says it has votes.
        let validAverage = average.flatMap { $0.isFinite && (1...5).contains($0) ? $0 : nil }
        guard !reviews.isEmpty || (validAverage != nil && averageCount > 0) else { return nil }
        return CritiqueBrainzReviewSummary(
            entity: entity,
            reviews: reviews,
            averageRating: validAverage,
            ratingCount: averageCount
        )
    }

    static func decodePage(
        _ data: Data,
        for entity: CritiqueBrainzEntity,
        expectedOffset: Int,
        expectedLimit: Int
    ) throws -> CritiqueBrainzReviewPage? {
        guard expectedOffset >= 0, (1...50).contains(expectedLimit),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawRows = root["reviews"] as? [Any],
              let count = integer(root["count"]), count >= 0,
              let offset = integer(root["offset"]), offset == expectedOffset,
              let limit = integer(root["limit"]), limit == expectedLimit,
              rawRows.count <= limit
        else { throw CritiqueBrainzProviderError.invalidResponse }
        guard count >= offset,
              rawRows.isEmpty || count >= offset + rawRows.count
        else {
            throw CritiqueBrainzProviderError.invalidResponse
        }

        let rows = rawRows.compactMap { $0 as? [String: Any] }
        let reviews = rows.compactMap { review(from: $0, expected: entity) }
        let averageObject = root["average_rating"] as? [String: Any]
        let average = number(root["average_rating"]) ?? number(averageObject?["rating"])
        let averageCount = integer(averageObject?["count"]) ?? 0
        let validAverage = average.flatMap { $0.isFinite && (1...5).contains($0) ? $0 : nil }
        let pagination = CritiqueBrainzReviewPagination(
            totalCount: count,
            offset: offset,
            limit: limit,
            rawRowCount: rawRows.count
        )
        let summary = CritiqueBrainzReviewSummary(
            entity: entity,
            reviews: reviews,
            averageRating: validAverage,
            ratingCount: averageCount,
            pagination: pagination
        )
        return CritiqueBrainzReviewPage(summary: summary, pagination: pagination)
    }

    private static func review(from row: [String: Any], expected: CritiqueBrainzEntity) -> CritiqueBrainzReview? {
        guard row["is_hidden"] as? Bool != true, row["is_draft"] as? Bool != true else { return nil }
        guard uuid(row["id"]) != nil else { return nil }
        let entityID = uuid(row["entity_id"]) ?? uuid((row["entity"] as? [String: Any])?["id"])
        let entityType = string(row["entity_type"]) ?? string((row["entity"] as? [String: Any])?["type"])
        guard entityID == expected.mbid, entityType == expected.kind.rawValue else { return nil }
        guard let id = uuid(row["id"]) else { return nil }

        let revision = row["last_revision"] as? [String: Any]
        let text = nonempty(string(row["text"]) ?? string(revision?["text"]))
        let rating = (integer(row["rating"]) ?? integer(revision?["rating"]))
            .flatMap { (1...5).contains($0) ? $0 : nil }
        guard text != nil || rating != nil else { return nil }
        let user = row["user"] as? [String: Any]
        let author = nonempty(
            string(user?["display_name"])
                ?? string(user?["musicbrainz_username"])
                ?? string(user?["user_ref"])
                ?? string(user?["name"])
                ?? string(user?["username"])
        )
        let licenseObject = row["license"] as? [String: Any]
        let license = nonempty(string(row["license_id"]) ?? string(licenseObject?["id"]))
        let licenseURL = safeLicenseURL(string(row["info_url"]) ?? string(licenseObject?["info_url"]))
        let publishedAt = date(
            string(row["published_on"])
                ?? string(revision?["timestamp"])
                ?? string(row["last_updated"])
                ?? string(row["created"])
        )
        return CritiqueBrainzReview(
            id: id,
            author: author,
            licenseID: license,
            licenseURL: licenseURL,
            rating: rating,
            text: text,
            publishedAt: publishedAt
        )
    }

    private static func uuid(_ value: Any?) -> UUID? { string(value).flatMap(UUID.init(uuidString:)) }
    private static func string(_ value: Any?) -> String? { value as? String }
    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value.doubleValue
        }
        if let value = value as? String { return Double(value) }
        return nil
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let value = number(value), value.isFinite, value.rounded() == value else { return nil }
        return Int(exactly: value)
    }
    private static func safeLicenseURL(_ value: String?) -> URL? {
        guard let value = nonempty(value), let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              ["creativecommons.org", "www.creativecommons.org"].contains(host),
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              url.path.hasPrefix("/licenses/") || url.path.hasPrefix("/publicdomain/")
        else { return nil }
        return url
    }
    private static func date(_ value: String?) -> Date? {
        guard let value = nonempty(value) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        if let parsed = formatter.date(from: value) { return parsed }
        return ISO8601DateFormatter().date(from: value)
    }
    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CritiqueBrainzReviewCaches {
    static let values = EntityDetailCache<CritiqueBrainzReviewCacheKey, CritiqueBrainzReviewSummary>(
        timeToLive: 5 * 60,
        maximumEntryCount: 100
    )
    static let pages = EntityDetailCache<CritiqueBrainzReviewPageCacheKey, CritiqueBrainzReviewPage>(
        timeToLive: 5 * 60,
        maximumEntryCount: 100
    )
}
