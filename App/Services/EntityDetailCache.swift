import Foundation

actor EntityDetailCache<Key: Hashable & Sendable, Value: Sendable> {
    struct CachedValue: Sendable {
        let value: Value
        let isFresh: Bool
    }

    private struct Entry {
        let value: Value
        let savedAt: Date
        var lastAccessedAt: Date
    }

    private let timeToLive: TimeInterval
    private let maximumEntryCount: Int
    private var entries: [Key: Entry] = [:]

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
        entries[key] = Entry(value: value, savedAt: now, lastAccessedAt: now)
        trimIfNeeded()
    }

    func removeAll() {
        entries.removeAll()
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
    static let playlists = EntityDetailCache<UUID, PlaylistDetail>()
}
