import Foundation

actor EntityDetailCache<Key: Hashable & Sendable, Value: Sendable> {
    struct CachedValue: Sendable {
        let value: Value
        let isFresh: Bool
    }

    struct WriteReceipt: Sendable, Equatable {
        fileprivate let id: UUID
    }

    private struct Entry {
        let value: Value
        let savedAt: Date
        var lastAccessedAt: Date
        let writeID: UUID
    }

    private let timeToLive: TimeInterval
    private let maximumEntryCount: Int
    private var entries: [Key: Entry] = [:]
    private var revision: UInt64 = 0

    init(timeToLive: TimeInterval = 5 * 60, maximumEntryCount: Int = 100) {
        self.timeToLive = timeToLive
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    func value(for key: Key, now: Date = .now) -> CachedValue? {
        guard var entry = entries[key] else { return nil }
        entry.lastAccessedAt = now
        entries[key] = entry
        return CachedValue(
            value: entry.value,
            isFresh: now.timeIntervalSince(entry.savedAt) < timeToLive
        )
    }

    func save(_ value: Value, for key: Key, now: Date = .now) {
        entries[key] = Entry(value: value, savedAt: now, lastAccessedAt: now, writeID: UUID())
        trimIfNeeded()
    }

    /// Saves only when no invalidation happened after a caller began its
    /// asynchronous read. This prevents a late response from repopulating a
    /// cache after a related mutation deliberately cleared it.
    @discardableResult
    func save(
        _ value: Value,
        for key: Key,
        ifUnchangedSince expectedRevision: UInt64,
        now: Date = .now
    ) -> WriteReceipt? {
        guard revision == expectedRevision else { return nil }
        let receipt = WriteReceipt(id: UUID())
        entries[key] = Entry(value: value, savedAt: now, lastAccessedAt: now, writeID: receipt.id)
        trimIfNeeded()
        return receipt
    }

    func currentRevision() -> UInt64 { revision }

    func removeValue(for key: Key) {
        entries.removeValue(forKey: key)
        revision &+= 1
    }

    /// Removes only the exact value written by a suspended caller. A newer
    /// write for the same key is preserved.
    @discardableResult
    func removeValue(for key: Key, ifWrittenWith receipt: WriteReceipt) -> Bool {
        guard entries[key]?.writeID == receipt.id else { return false }
        entries.removeValue(forKey: key)
        return true
    }

    func removeAll() {
        entries.removeAll()
        revision &+= 1
    }

    private func trimIfNeeded() {
        guard entries.count > maximumEntryCount else { return }
        let overflow = entries.count - maximumEntryCount
        let keys = entries
            .sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            .prefix(overflow)
            .map(\.key)
        for key in keys {
            entries.removeValue(forKey: key)
        }
    }
}

enum EntityDetailCaches {
    static let releaseGroups = EntityDetailCache<UUID, ReleaseGroupDetail>()
    static let releases = EntityDetailCache<UUID, ReleaseDetail>()
    static let playlists = EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>()
    static let dailyActivity = EntityDetailCache<DailyActivityCacheKey, DailyActivity>(
        timeToLive: 10 * 60,
        maximumEntryCount: 28
    )
    static let eraActivity = EntityDetailCache<EraActivityCacheKey, EraActivity>(
        timeToLive: 10 * 60,
        maximumEntryCount: 28
    )
    static let artistEvolutionActivity = EntityDetailCache<ArtistEvolutionActivityCacheKey, ArtistEvolutionActivity>(
        timeToLive: 10 * 60,
        maximumEntryCount: 28
    )
    static let genreActivity = EntityDetailCache<GenreActivityCacheKey, GenreActivity>(
        timeToLive: 10 * 60,
        maximumEntryCount: 28
    )
    static let artistOrigins = EntityDetailCache<ArtistOriginsCacheKey, ArtistOrigins>(
        timeToLive: 10 * 60,
        maximumEntryCount: 28
    )
    static let artistActivity = EntityDetailCache<ArtistActivityCacheKey, ArtistActivity>(
        timeToLive: 10 * 60, maximumEntryCount: 28
    )
    static let releaseGroupRankings = EntityDetailCache<ReleaseGroupRankingCacheKey, [RankedReleaseGroup]>(
        timeToLive: 10 * 60, maximumEntryCount: 28
    )
}
