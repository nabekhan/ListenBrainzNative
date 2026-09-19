import Foundation
import ListenBrainzKit

protocol PopularityProviding: Sendable {
    func popularity(for entity: PopularityEntity) async throws -> GlobalPopularity
}

protocol PopularityTransport: Sendable {
    func artists(_ mbids: [UUID]) async throws -> [LBPopularity]
    func recordings(_ mbids: [UUID]) async throws -> [LBPopularity]
    func releases(_ mbids: [UUID]) async throws -> [LBPopularity]
    func releaseGroups(_ mbids: [UUID]) async throws -> [LBPopularity]
}

private struct LivePopularityTransport: PopularityTransport {
    let client: LBClient

    func artists(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await client.popularity.artists(mbids)
    }

    func recordings(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await client.popularity.recordings(mbids)
    }

    func releases(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await client.popularity.releases(mbids)
    }

    func releaseGroups(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await client.popularity.releaseGroups(mbids)
    }
}

struct ListenBrainzPopularityProvider: PopularityProviding {
    private let transport: any PopularityTransport
    private let gate: RequestGate
    private let cache: PopularityCache
    private let readScope: RequestGate.ReadScope

    init(
        token: String,
        gate: RequestGate = .shared,
        cache: PopularityCache = .shared
    ) {
        transport = LivePopularityTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        self.cache = cache
        readScope = .authenticated(token: token)
    }

    init(
        transport: some PopularityTransport,
        gate: RequestGate,
        cache: PopularityCache = .init(),
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.cache = cache
        self.readScope = readScope
    }

    func popularity(for entity: PopularityEntity) async throws -> GlobalPopularity {
        try await cache.value(for: entity) {
            let rows: [LBPopularity] = try await gate.read(for: .popularity(readScope, kind: entity.kind.rawValue, mbid: entity.mbid)) {
                switch entity.kind {
                case .artist:
                    try await transport.artists([entity.mbid])
                case .recording:
                    try await transport.recordings([entity.mbid])
                case .release:
                    try await transport.releases([entity.mbid])
                case .releaseGroup:
                    try await transport.releaseGroups([entity.mbid])
                }
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }

            let row = rows.first(where: { $0.mbid == entity.mbid })
            return GlobalPopularity(
                entity: entity,
                totalListenCount: row?.totalListenCount,
                totalUserCount: row?.totalUserCount
            )
        }
    }
}

/// An in-memory daily cache for global popularity. It also owns in-flight work so
/// duplicate detail loads do not spend another paced ListenBrainz request.
actor PopularityCache {
    static let shared = PopularityCache()

    private struct Entry {
        let value: GlobalPopularity
        let savedAt: Date
        var lastAccessedAt: Date
    }

    private let timeToLive: TimeInterval
    private let maximumEntryCount: Int
    private var entries: [PopularityEntity: Entry] = [:]
    private var inFlight: [PopularityEntity: Task<GlobalPopularity, any Error>] = [:]

    init(timeToLive: TimeInterval = 24 * 60 * 60, maximumEntryCount: Int = 200) {
        self.timeToLive = timeToLive
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    func value(
        for entity: PopularityEntity,
        now: Date = .now,
        load: @escaping @Sendable () async throws -> GlobalPopularity
    ) async throws -> GlobalPopularity {
        if var entry = entries[entity], now.timeIntervalSince(entry.savedAt) < timeToLive {
            entry.lastAccessedAt = now
            entries[entity] = entry
            return entry.value
        }

        if let task = inFlight[entity] {
            return try await task.value
        }

        let task = Task { try await load() }
        inFlight[entity] = task
        do {
            let loaded = try await task.value
            entries[entity] = Entry(value: loaded, savedAt: now, lastAccessedAt: now)
            trimIfNeeded()
            inFlight.removeValue(forKey: entity)
            return loaded
        } catch {
            inFlight.removeValue(forKey: entity)
            throw error
        }
    }

    private func trimIfNeeded() {
        guard entries.count > maximumEntryCount else { return }
        let overflow = entries.count - maximumEntryCount
        let leastRecentlyUsed = entries
            .sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            .prefix(overflow)
            .map(\.key)
        for entity in leastRecentlyUsed {
            entries.removeValue(forKey: entity)
        }
    }
}
