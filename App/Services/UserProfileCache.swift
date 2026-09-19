import Foundation

actor UserProfileCache {
    struct CachedValue: Sendable {
        let snapshot: UserProfileSnapshot
        let isOverviewFresh: Bool
        let isTopArtistsFresh: Bool

        var isFresh: Bool { isOverviewFresh }
    }

    static let shared = UserProfileCache()

    private struct Entry {
        var snapshot: UserProfileSnapshot
        var overviewSavedAt: Date?
        var topArtistsSavedAt: Date?
        var lastAccessedAt: Date
    }

    private let timeToLive: TimeInterval
    private let maximumEntryCount: Int
    private struct Key: Hashable, Sendable {
        let username: String
        let scope: RequestGate.ReadScope
    }

    private var entries: [Key: Entry] = [:]

    init(timeToLive: TimeInterval = 5 * 60, maximumEntryCount: Int = 100) {
        self.timeToLive = timeToLive
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    func value(
        for username: String,
        scope: RequestGate.ReadScope,
        now: Date = .now
    ) -> CachedValue? {
        let key = Self.key(for: username, scope: scope)
        guard var entry = entries[key] else { return nil }
        entry.lastAccessedAt = now
        entries[key] = entry
        return CachedValue(
            snapshot: entry.snapshot,
            isOverviewFresh: Self.isFresh(
                entry.overviewSavedAt,
                at: now,
                timeToLive: timeToLive
            ) && entry.snapshot.hasLoadedOverview,
            isTopArtistsFresh: Self.isFresh(
                entry.topArtistsSavedAt,
                at: now,
                timeToLive: timeToLive
            ) && entry.snapshot.hasLoadedTopArtists
        )
    }

    func save(
        _ snapshot: UserProfileSnapshot,
        for username: String,
        scope: RequestGate.ReadScope,
        now: Date = .now
    ) {
        entries[Self.key(for: username, scope: scope)] = Entry(
            snapshot: snapshot,
            overviewSavedAt: snapshot.hasLoadedOverview ? now : nil,
            topArtistsSavedAt: snapshot.hasLoadedTopArtists ? now : nil,
            lastAccessedAt: now
        )
        trimIfNeeded()
    }

    func saveOverview(
        _ snapshot: UserProfileSnapshot,
        for username: String,
        scope: RequestGate.ReadScope,
        now: Date = .now
    ) {
        let key = Self.key(for: username, scope: scope)
        var entry = entries[key] ?? Entry(
            snapshot: .empty,
            overviewSavedAt: nil,
            topArtistsSavedAt: nil,
            lastAccessedAt: now
        )
        entry.snapshot.recentListens = snapshot.recentListens
        entry.snapshot.playingNow = snapshot.playingNow
        entry.snapshot.listenCount = snapshot.listenCount
        entry.snapshot.hasLoadedOverview = snapshot.hasLoadedOverview
        entry.snapshot.savedAt = snapshot.savedAt
        if snapshot.hasLoadedOverview {
            entry.overviewSavedAt = now
        }
        entry.lastAccessedAt = now
        entries[key] = entry
        trimIfNeeded()
    }

    func saveTopArtists(
        _ snapshot: UserProfileSnapshot,
        for username: String,
        scope: RequestGate.ReadScope,
        now: Date = .now
    ) {
        let key = Self.key(for: username, scope: scope)
        var entry = entries[key] ?? Entry(
            snapshot: .empty,
            overviewSavedAt: nil,
            topArtistsSavedAt: nil,
            lastAccessedAt: now
        )
        entry.snapshot.topArtists = snapshot.topArtists
        entry.snapshot.hasLoadedTopArtists = snapshot.hasLoadedTopArtists
        entry.snapshot.savedAt = snapshot.savedAt
        if snapshot.hasLoadedTopArtists {
            entry.topArtistsSavedAt = now
        }
        entry.lastAccessedAt = now
        entries[key] = entry
        trimIfNeeded()
    }

    func removeAll() {
        entries.removeAll()
    }

    private static func key(for username: String, scope: RequestGate.ReadScope) -> Key {
        Key(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            scope: scope
        )
    }

    private static func isFresh(
        _ savedAt: Date?,
        at now: Date,
        timeToLive: TimeInterval
    ) -> Bool {
        guard let savedAt else { return false }
        return now.timeIntervalSince(savedAt) < timeToLive
    }

    private func trimIfNeeded() {
        guard entries.count > maximumEntryCount else { return }
        let overflow = entries.count - maximumEntryCount
        for key in entries
            .sorted(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })
            .prefix(overflow)
            .map(\.key) {
            entries.removeValue(forKey: key)
        }
    }
}
