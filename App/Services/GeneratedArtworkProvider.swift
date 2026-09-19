import Foundation
import ListenBrainzKit

protocol GeneratedArtworkProviding: Sendable {
    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> GeneratedArtworkDocument?
}

protocol GeneratedArtworkTransport: Sendable {
    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> LBGeneratedArtwork?
}

private struct LiveGeneratedArtworkTransport: GeneratedArtworkTransport {
    let anonymousClient: LBClient
    let authenticatedClient: LBClient

    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> LBGeneratedArtwork? {
        switch request {
        case let .statistics(username, range, dimension, layout, imageSize, options):
            try await anonymousClient.art.statisticsGrid(
                username: username,
                range: range,
                dimension: dimension,
                layout: layout,
                imageSize: imageSize,
                options: options
            )
        case let .artist(mbid, dimension, layout, imageSize, options):
            try await anonymousClient.art.artistGrid(
                artistMBID: mbid,
                dimension: dimension,
                layout: layout,
                imageSize: imageSize,
                options: options
            )
        case let .playlist(mbid, dimension, layout):
            try await authenticatedClient.art.playlistArtwork(
                playlistMBID: mbid,
                dimension: dimension,
                layout: layout
            )
        }
    }
}

struct ListenBrainzGeneratedArtworkProvider: GeneratedArtworkProviding {
    private let transport: any GeneratedArtworkTransport
    private let gate: RequestGate
    private let cache: GeneratedArtworkCache
    private let authenticatedScope: RequestGate.ReadScope
    private let hasAuthenticatedToken: Bool

    init(
        token: String,
        gate: RequestGate = .shared,
        cache: GeneratedArtworkCache = .shared
    ) {
        let userAgent = "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        transport = LiveGeneratedArtworkTransport(
            anonymousClient: LBClient(token: "", userAgent: userAgent),
            authenticatedClient: LBClient(token: token, userAgent: userAgent)
        )
        self.gate = gate
        self.cache = cache
        authenticatedScope = .authenticated(token: token)
        hasAuthenticatedToken = !token.isEmpty
    }

    init(
        transport: some GeneratedArtworkTransport,
        gate: RequestGate,
        cache: GeneratedArtworkCache = .init(),
        authenticatedScope: RequestGate.ReadScope = .isolated(),
        hasAuthenticatedToken: Bool = true
    ) {
        self.transport = transport
        self.gate = gate
        self.cache = cache
        self.authenticatedScope = authenticatedScope
        self.hasAuthenticatedToken = hasAuthenticatedToken
    }

    func artwork(
        for request: GeneratedArtworkRequest
    ) async throws -> GeneratedArtworkDocument? {
        if request.scope == .authenticated, !hasAuthenticatedToken {
            throw ProviderError.invalidToken
        }

        let scope: RequestGate.ReadScope = request.scope == .anonymous
            ? .anonymous
            : authenticatedScope

        switch await cache.lookup(request: request, scope: scope) {
        case let .hit(document):
            return document
        case .miss:
            break
        }

        let document: GeneratedArtworkDocument?
        do {
            let source = try await gate.read(
                for: .generatedArtwork(scope, request: request)
            ) {
                try await transport.artwork(for: request)
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else {
                    return nil
                }
                return .seconds(max(resetIn, 1))
            }
            document = source.map {
                GeneratedArtworkDocument(request: request, svg: $0.svg)
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(
                retryAfterSeconds: max(resetIn, 1)
            )
        } catch LBError.badRequest, LBError.notFound, LBError.noContent {
            document = nil
        } catch let error as LBError {
            switch error {
            case .invalidAuth, .noToken:
                throw ProviderError.invalidToken
            case .forbidden:
                throw GeneratedArtworkProviderError.accessDenied
            case .invalidJSON, .invalidResponse:
                throw GeneratedArtworkProviderError.invalidArtwork
            default:
                throw GeneratedArtworkProviderError.creationFailed
            }
        }

        try Task.checkCancellation()
        await cache.insert(document, request: request, scope: scope)
        return document
    }
}

enum GeneratedArtworkProviderError: LocalizedError, Sendable {
    case accessDenied
    case invalidArtwork
    case creationFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Your ListenBrainz account can’t create artwork for this playlist."
        case .invalidArtwork:
            "ListenBrainz returned artwork Brainz couldn’t open. Try again later."
        case .creationFailed:
            "ListenBrainz couldn’t create this artwork. Try again."
        }
    }
}

actor GeneratedArtworkCache {
    static let shared = GeneratedArtworkCache()

    enum Lookup: Equatable, Sendable {
        case hit(GeneratedArtworkDocument?)
        case miss
    }

    private struct Key: Hashable, Sendable {
        let request: GeneratedArtworkRequest
        let scope: RequestGate.ReadScope
    }

    private struct Entry: Sendable {
        let value: GeneratedArtworkDocument?
        let savedAt: Date
        var lastAccessedAt: Date

        var byteCount: Int {
            value?.svg.utf8.count ?? 0
        }
    }

    private let timeToLive: TimeInterval
    private let maximumEntryCount: Int
    private let maximumByteCount: Int
    private var entries: [Key: Entry] = [:]

    init(
        timeToLive: TimeInterval = 24 * 60 * 60,
        maximumEntryCount: Int = 24,
        maximumByteCount: Int = 16 * 1_024 * 1_024
    ) {
        self.timeToLive = timeToLive
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.maximumByteCount = max(1, maximumByteCount)
    }

    func lookup(
        request: GeneratedArtworkRequest,
        scope: RequestGate.ReadScope,
        now: Date = .now
    ) -> Lookup {
        purgeExpired(now: now)
        let key = Key(request: request, scope: scope)
        guard var entry = entries[key] else { return .miss }

        entry.lastAccessedAt = now
        entries[key] = entry
        return .hit(entry.value)
    }

    func insert(
        _ value: GeneratedArtworkDocument?,
        request: GeneratedArtworkRequest,
        scope: RequestGate.ReadScope,
        now: Date = .now
    ) {
        purgeExpired(now: now)
        entries[Key(request: request, scope: scope)] = Entry(
            value: value,
            savedAt: now,
            lastAccessedAt: now
        )
        trimIfNeeded()
    }

    private func purgeExpired(now: Date) {
        entries = entries.filter {
            now.timeIntervalSince($0.value.savedAt) < timeToLive
        }
    }

    private func trimIfNeeded() {
        while entries.count > maximumEntryCount
                || entries.values.reduce(0, { $0 + $1.byteCount }) > maximumByteCount {
            guard let leastRecentlyUsed = entries.min(by: {
                $0.value.lastAccessedAt < $1.value.lastAccessedAt
            })?.key else {
                return
            }
            entries.removeValue(forKey: leastRecentlyUsed)
        }
    }
}
