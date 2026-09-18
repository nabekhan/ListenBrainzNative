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
        anonymous: Bool?
    ) async throws -> LBYearInMusicArtwork?
}

private struct LiveYearInMusicArtworkTransport: YearInMusicArtworkTransport {
    let client: LBClient

    func yearInMusic(
        username: String,
        year: Int,
        variant: LBYearInMusicArtVariant,
        anonymous: Bool?
    ) async throws -> LBYearInMusicArtwork? {
        try await client.art.yearInMusic(
            username: username,
            year: year,
            variant: variant,
            anonymous: anonymous
        )
    }
}

struct ListenBrainzYearInMusicArtworkProvider: YearInMusicArtworkProviding {
    private let transport: any YearInMusicArtworkTransport
    private let gate: RequestGate
    private let cache: YearInMusicArtworkCache

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
    }

    init(
        transport: some YearInMusicArtworkTransport,
        gate: RequestGate,
        cache: YearInMusicArtworkCache = .init()
    ) {
        self.transport = transport
        self.gate = gate
        self.cache = cache
    }

    func artwork(for options: YearInMusicArtworkOptions) async throws -> YearInMusicArtwork? {
        try await cache.value(for: options) {
            do {
                let source = try await gate.perform({
                    try await transport.yearInMusic(
                        username: options.username,
                        year: options.year,
                        variant: options.variant,
                        anonymous: options.anonymous
                    )
                }) { error in
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
    private var entries: [YearInMusicArtworkOptions: Entry] = [:]
    private var inFlight: [YearInMusicArtworkOptions: Flight] = [:]

    init(timeToLive: TimeInterval = 24 * 60 * 60, maximumEntryCount: Int = 24) {
        self.timeToLive = timeToLive
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    func value(
        for options: YearInMusicArtworkOptions,
        now: Date = .now,
        load: @escaping @Sendable () async throws -> YearInMusicArtwork?
    ) async throws -> YearInMusicArtwork? {
        if var entry = entries[options], now.timeIntervalSince(entry.savedAt) < timeToLive {
            entry.lastAccessedAt = now
            entries[options] = entry
            return entry.value
        }
        let waiterID = UUID()
        let flight: Flight
        if var existing = inFlight[options] {
            existing.waiterIDs.insert(waiterID)
            inFlight[options] = existing
            flight = existing
        } else {
            let created = Flight(
                id: UUID(),
                task: Task { try await load() },
                waiterIDs: [waiterID]
            )
            inFlight[options] = created
            flight = created
        }

        do {
            let loaded = try await withTaskCancellationHandler {
                try await flight.task.value
            } onCancel: {
                Task {
                    await self.cancelWaiter(
                        waiterID,
                        for: options,
                        flightID: flight.id
                    )
                }
            }
            try Task.checkCancellation()
            completeFlight(loaded, for: options, flightID: flight.id, now: now)
            return loaded
        } catch is CancellationError {
            cancelWaiter(waiterID, for: options, flightID: flight.id)
            throw CancellationError()
        } catch {
            failFlight(for: options, flightID: flight.id)
            throw error
        }
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        for options: YearInMusicArtworkOptions,
        flightID: UUID
    ) {
        guard var flight = inFlight[options], flight.id == flightID else { return }
        guard flight.waiterIDs.remove(waiterID) != nil else { return }
        if flight.waiterIDs.isEmpty {
            flight.task.cancel()
            inFlight.removeValue(forKey: options)
        } else {
            inFlight[options] = flight
        }
    }

    private func completeFlight(
        _ loaded: YearInMusicArtwork?,
        for options: YearInMusicArtworkOptions,
        flightID: UUID,
        now: Date
    ) {
        guard inFlight[options]?.id == flightID else { return }
        entries[options] = Entry(value: loaded, savedAt: now, lastAccessedAt: now)
        inFlight.removeValue(forKey: options)
        trimIfNeeded()
    }

    private func failFlight(for options: YearInMusicArtworkOptions, flightID: UUID) {
        guard inFlight[options]?.id == flightID else { return }
        inFlight.removeValue(forKey: options)
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
