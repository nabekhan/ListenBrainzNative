import Foundation
import ListenBrainzKit

protocol YearInMusicArtworkProviding: Sendable {
    /// `nil` means the requested image is unavailable for this user/year.
    func artwork(for options: YearInMusicArtworkOptions) async throws -> YearInMusicArtwork?
}

protocol YearInMusicArtworkTransport: Sendable {
    func yearInMusic(
        username: String,
        year: Int,
        variant: LBYearInMusicArtVariant,
        anonymous: Bool?,
        legacy: Bool
    ) async throws -> LBYearInMusicArtwork?
}

private struct LiveYearInMusicArtworkTransport: YearInMusicArtworkTransport {
    let client: LBClient

    func yearInMusic(
        username: String,
        year: Int,
        variant: LBYearInMusicArtVariant,
        anonymous: Bool?,
        legacy: Bool
    ) async throws -> LBYearInMusicArtwork? {
        try await client.art.yearInMusic(
            username: username,
            year: year,
            variant: variant,
            anonymous: anonymous,
            legacy: legacy
        )
    }
}

struct ListenBrainzYearInMusicArtworkProvider: YearInMusicArtworkProviding {
    private let transport: any YearInMusicArtworkTransport
    private let gate: RequestGate
    private let cache: YearInMusicArtworkCache
    private let readScope: RequestGate.ReadScope

    init(
        token: String,
        gate: RequestGate = .shared,
        cache: YearInMusicArtworkCache = .shared
    ) {
        transport = LiveYearInMusicArtworkTransport(
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
        transport: some YearInMusicArtworkTransport,
        gate: RequestGate,
        cache: YearInMusicArtworkCache = .init(),
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.cache = cache
        self.readScope = readScope
    }

    func artwork(for options: YearInMusicArtworkOptions) async throws -> YearInMusicArtwork? {
        try await cache.value(for: options, scope: readScope) {
            do {
                let source = try await gate.read(for: .yearInMusicArtwork(readScope, user: options.username, year: options.year, variant: options.variant.rawValue, anonymous: options.anonymous, legacy: options.legacy)) {
                    try await transport.yearInMusic(
                        username: options.username,
                        year: options.year,
                        variant: options.variant,
                        anonymous: options.anonymous,
                        legacy: options.legacy
                    )
                } deferralForError: { error in
                    guard case let LBError.rateLimited(resetIn) = error else { return nil }
                    return .seconds(max(resetIn, 1))
                }
                return source.map { YearInMusicArtwork(options: options, source: $0) }
            } catch let LBError.rateLimited(resetIn) {
                throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
            }
        }
    }
}

/// Daily, memory-only cache for generated image documents. Cache ownership also
/// coalesces duplicate taps before they can occupy another request-gate slot.
actor YearInMusicArtworkCache {
    static let shared = YearInMusicArtworkCache()

    private struct Key: Hashable, Sendable {
        let options: YearInMusicArtworkOptions
        let scope: RequestGate.ReadScope
    }

    private struct Entry {
        let value: YearInMusicArtwork?
        let savedAt: Date
        var lastAccessedAt: Date
    }

    private struct Flight {
        let id: UUID
        let task: Task<YearInMusicArtwork?, any Error>
        var waiterIDs: Set<UUID>
    }

    private let timeToLive: TimeInterval
    private let maximumEntryCount: Int
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Flight] = [:]

    init(timeToLive: TimeInterval = 24 * 60 * 60, maximumEntryCount: Int = 24) {
        self.timeToLive = timeToLive
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    func value(
        for options: YearInMusicArtworkOptions,
        scope: RequestGate.ReadScope,
        now: Date = .now,
        load: @escaping @Sendable () async throws -> YearInMusicArtwork?
    ) async throws -> YearInMusicArtwork? {
        let key = Key(options: options, scope: scope)
        if var entry = entries[key], now.timeIntervalSince(entry.savedAt) < timeToLive {
            entry.lastAccessedAt = now
            entries[key] = entry
            return entry.value
        }
        let waiterID = UUID()
        let flight: Flight
        if var existing = inFlight[key] {
            existing.waiterIDs.insert(waiterID)
            inFlight[key] = existing
            flight = existing
        } else {
            let created = Flight(
                id: UUID(),
                task: Task { try await load() },
                waiterIDs: [waiterID]
            )
            inFlight[key] = created
            flight = created
        }

        do {
            let loaded = try await withTaskCancellationHandler {
                try await flight.task.value
            } onCancel: {
                Task {
                    await self.cancelWaiter(
                        waiterID,
                        for: key,
                        flightID: flight.id
                    )
                }
            }
            try Task.checkCancellation()
            completeFlight(loaded, for: key, flightID: flight.id, now: now)
            return loaded
        } catch is CancellationError {
            cancelWaiter(waiterID, for: key, flightID: flight.id)
            throw CancellationError()
        } catch {
            failFlight(for: key, flightID: flight.id)
            throw error
        }
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        for key: Key,
        flightID: UUID
    ) {
        guard var flight = inFlight[key], flight.id == flightID else { return }
        guard flight.waiterIDs.remove(waiterID) != nil else { return }
        if flight.waiterIDs.isEmpty {
            flight.task.cancel()
            inFlight.removeValue(forKey: key)
        } else {
            inFlight[key] = flight
        }
    }

    private func completeFlight(
        _ loaded: YearInMusicArtwork?,
        for key: Key,
        flightID: UUID,
        now: Date
    ) {
        guard inFlight[key]?.id == flightID else { return }
        entries[key] = Entry(value: loaded, savedAt: now, lastAccessedAt: now)
        inFlight.removeValue(forKey: key)
        trimIfNeeded()
    }

    private func failFlight(for key: Key, flightID: UUID) {
        guard inFlight[key]?.id == flightID else { return }
        inFlight.removeValue(forKey: key)
    }

    private func trimIfNeeded() {
        guard entries.count > maximumEntryCount else { return }
        let keys = entries
            .sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            .prefix(entries.count - maximumEntryCount)
            .map(\.key)
        for key in keys { entries.removeValue(forKey: key) }
    }
}
