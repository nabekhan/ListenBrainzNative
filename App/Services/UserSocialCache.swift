import Foundation

actor UserSocialCache {
    struct CachedSection<Value: Sendable>: Sendable {
        let value: Value
        let isFresh: Bool
    }

    struct PublicValue: Sendable {
        let followers: CachedSection<[SearchUser]>?
        let following: CachedSection<[SearchUser]>?
        let similarUsers: CachedSection<[SimilarListener]>?
    }

    struct ViewerValue: Sendable {
        let isFollowing: CachedSection<Bool>?
        let compatibility: CachedSection<Double?>?
    }

    static let shared = UserSocialCache()

    private struct Timed<Value: Sendable>: Sendable {
        var value: Value
        var savedAt: Date
    }

    private struct PublicEntry: Sendable {
        var followers: Timed<[SearchUser]>? = nil
        var following: Timed<[SearchUser]>? = nil
        var similarUsers: Timed<[SimilarListener]>? = nil
        var lastAccessedAt: Date
    }

    private struct ViewerEntry: Sendable {
        var isFollowing: Timed<Bool>? = nil
        var compatibility: Timed<Double?>? = nil
        var lastAccessedAt: Date
    }

    private struct ViewerKey: Hashable, Sendable {
        let viewer: String
        let target: String
    }

    private let timeToLive: TimeInterval
    private let maximumPublicEntries: Int
    private let maximumViewerEntries: Int
    private var publicEntries: [String: PublicEntry] = [:]
    private var viewerEntries: [ViewerKey: ViewerEntry] = [:]

    init(
        timeToLive: TimeInterval = 5 * 60,
        maximumPublicEntries: Int = 100,
        maximumViewerEntries: Int = 200
    ) {
        self.timeToLive = timeToLive
        self.maximumPublicEntries = max(1, maximumPublicEntries)
        self.maximumViewerEntries = max(1, maximumViewerEntries)
    }

    func publicValue(for username: String, now: Date = .now) -> PublicValue? {
        let key = Self.normalized(username)
        guard var entry = publicEntries[key] else { return nil }
        entry.lastAccessedAt = now
        publicEntries[key] = entry
        return PublicValue(
            followers: cached(entry.followers, now: now),
            following: cached(entry.following, now: now),
            similarUsers: cached(entry.similarUsers, now: now)
        )
    }

    func viewerValue(viewer: String, target: String, now: Date = .now) -> ViewerValue? {
        let key = ViewerKey(viewer: Self.normalized(viewer), target: Self.normalized(target))
        guard var entry = viewerEntries[key] else { return nil }
        entry.lastAccessedAt = now
        viewerEntries[key] = entry
        return ViewerValue(
            isFollowing: cached(entry.isFollowing, now: now),
            compatibility: cached(entry.compatibility, now: now)
        )
    }

    func saveFollowers(_ users: [SearchUser], for username: String, now: Date = .now) {
        updatePublic(username: username, now: now) { $0.followers = Timed(value: users, savedAt: now) }
    }

    func saveFollowing(_ users: [SearchUser], for username: String, now: Date = .now) {
        updatePublic(username: username, now: now) { $0.following = Timed(value: users, savedAt: now) }
    }

    func saveSimilarUsers(_ users: [SimilarListener], for username: String, now: Date = .now) {
        updatePublic(username: username, now: now) { $0.similarUsers = Timed(value: users, savedAt: now) }
    }

    func saveIsFollowing(_ value: Bool, viewer: String, target: String, now: Date = .now) {
        updateViewer(viewer: viewer, target: target, now: now) {
            $0.isFollowing = Timed(value: value, savedAt: now)
        }
    }

    func saveCompatibility(_ value: Double?, viewer: String, target: String, now: Date = .now) {
        updateViewer(viewer: viewer, target: target, now: now) {
            $0.compatibility = Timed(value: value, savedAt: now)
        }
    }

    func removeAll() {
        publicEntries.removeAll()
        viewerEntries.removeAll()
    }

    private func cached<Value: Sendable>(
        _ timed: Timed<Value>?,
        now: Date
    ) -> CachedSection<Value>? {
        guard let timed else { return nil }
        return CachedSection(
            value: timed.value,
            isFresh: now.timeIntervalSince(timed.savedAt) < timeToLive
        )
    }

    private func updatePublic(
        username: String,
        now: Date,
        update: (inout PublicEntry) -> Void
    ) {
        let key = Self.normalized(username)
        var entry = publicEntries[key] ?? PublicEntry(lastAccessedAt: now)
        update(&entry)
        entry.lastAccessedAt = now
        publicEntries[key] = entry
        trimPublicEntries()
    }

    private func updateViewer(
        viewer: String,
        target: String,
        now: Date,
        update: (inout ViewerEntry) -> Void
    ) {
        let key = ViewerKey(viewer: Self.normalized(viewer), target: Self.normalized(target))
        var entry = viewerEntries[key] ?? ViewerEntry(lastAccessedAt: now)
        update(&entry)
        entry.lastAccessedAt = now
        viewerEntries[key] = entry
        trimViewerEntries()
    }

    private func trimPublicEntries() {
        guard publicEntries.count > maximumPublicEntries else { return }
        for key in publicEntries
            .sorted(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })
            .prefix(publicEntries.count - maximumPublicEntries)
            .map(\.key) {
            publicEntries.removeValue(forKey: key)
        }
    }

    private func trimViewerEntries() {
        guard viewerEntries.count > maximumViewerEntries else { return }
        for key in viewerEntries
            .sorted(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })
            .prefix(viewerEntries.count - maximumViewerEntries)
            .map(\.key) {
            viewerEntries.removeValue(forKey: key)
        }
    }

    private static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
