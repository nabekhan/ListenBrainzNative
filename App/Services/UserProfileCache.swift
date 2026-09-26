import CryptoKit
import Foundation

/// A small, public-only cache for visited ListenBrainz profiles.
///
/// This intentionally has no account, token, or request-scope dimension: every
/// value is data that the ListenBrainz public profile endpoints return without
/// authentication. Private pages, playlists, and raw responses never enter it.
actor UserProfileCache {
    struct CachedValue: Sendable {
        let snapshot: UserProfileSnapshot
        let isOverviewFresh: Bool
        let isTopArtistsFresh: Bool
        let isTopReleasesFresh: Bool
        let isTopRecordingsFresh: Bool

        var isFresh: Bool { isOverviewFresh }
    }

    static let shared = UserProfileCache()

    private static let schemaVersion = 1
    private static let defaultHardRetention: TimeInterval = 7 * 24 * 60 * 60
    private static let defaultMaximumDiskBytes = 16 * 1_024 * 1_024
    private static let defaultMaximumEntryBytes = 4 * 1_024 * 1_024

    private struct Entry: Codable {
        var snapshot: UserProfileSnapshot
        var overviewSavedAt: Date?
        var topArtistsSavedAt: Date?
        var topReleasesSavedAt: Date?
        var topRecordingsSavedAt: Date?
        var createdAt: Date
        var lastAccessedAt: Date
    }

    private struct DiskEntry: Codable {
        let version: Int
        let username: String
        let entry: Entry
    }

    private let fileManager: FileManager
    private let directory: URL
    private let timeToLive: TimeInterval
    private let maximumEntryCount: Int
    private let maximumDiskBytes: Int
    private let maximumEntryBytes: Int
    private let hardRetention: TimeInterval
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var entries: [String: Entry] = [:]

    init(
        timeToLive: TimeInterval = 5 * 60,
        maximumEntryCount: Int = 100,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        maximumDiskBytes: Int = UserProfileCache.defaultMaximumDiskBytes,
        maximumEntryBytes: Int = UserProfileCache.defaultMaximumEntryBytes,
        hardRetention: TimeInterval = UserProfileCache.defaultHardRetention
    ) {
        self.timeToLive = max(0, timeToLive)
        self.maximumEntryCount = min(max(1, maximumEntryCount), 100)
        self.fileManager = fileManager
        self.maximumDiskBytes = min(max(1, maximumDiskBytes), Self.defaultMaximumDiskBytes)
        self.maximumEntryBytes = min(max(1, maximumEntryBytes), Self.defaultMaximumEntryBytes)
        self.hardRetention = min(max(0, hardRetention), Self.defaultHardRetention)
        let root = rootDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = root
            .appending(path: "ListenBrainzNative", directoryHint: .isDirectory)
            .appending(path: "PublicProfiles", directoryHint: .isDirectory)
        Self.configureDirectory(directory, fileManager: fileManager)
    }

    func value(for username: String, now: Date = .now) -> CachedValue? {
        guard let key = Self.canonicalUsername(username), let entry = entry(for: key, now: now) else { return nil }
        return cachedValue(from: entry, now: now)
    }

    /// Compatibility overload for callers/tests that formerly supplied a
    /// request scope. The value is deliberately ignored and never stored.
    func value(for username: String, scope _: RequestGate.ReadScope, now: Date = .now) -> CachedValue? {
        value(for: username, now: now)
    }

    func save(_ snapshot: UserProfileSnapshot, for username: String, now: Date = .now) {
        guard let key = Self.canonicalUsername(username) else { return }
        var cacheableSnapshot = snapshot
        cacheableSnapshot.playingNow = nil
        save(Entry(
            snapshot: cacheableSnapshot,
            overviewSavedAt: snapshot.hasLoadedOverview ? now : nil,
            topArtistsSavedAt: snapshot.hasLoadedTopArtists ? now : nil,
            topReleasesSavedAt: snapshot.hasLoadedTopReleases ? now : nil,
            topRecordingsSavedAt: snapshot.hasLoadedTopRecordings ? now : nil,
            createdAt: now,
            lastAccessedAt: now
        ), for: key, now: now)
    }

    func save(_ snapshot: UserProfileSnapshot, for username: String, scope _: RequestGate.ReadScope, now: Date = .now) {
        save(snapshot, for: username, now: now)
    }

    func saveOverview(_ snapshot: UserProfileSnapshot, for username: String, now: Date = .now) {
        updateEntry(for: username, now: now) { entry in
            entry.snapshot.recentListens = snapshot.recentListens
            // Playing Now is live state and must never survive a cache read.
            entry.snapshot.playingNow = nil
            entry.snapshot.listenCount = snapshot.listenCount
            entry.snapshot.hasLoadedOverview = snapshot.hasLoadedOverview
            entry.snapshot.savedAt = snapshot.savedAt
            if snapshot.hasLoadedOverview { entry.overviewSavedAt = now }
        }
    }

    func saveOverview(_ snapshot: UserProfileSnapshot, for username: String, scope _: RequestGate.ReadScope, now: Date = .now) {
        saveOverview(snapshot, for: username, now: now)
    }

    func saveTopArtists(_ snapshot: UserProfileSnapshot, for username: String, now: Date = .now) {
        updateEntry(for: username, now: now) { entry in
            entry.snapshot.topArtists = snapshot.topArtists
            entry.snapshot.hasLoadedTopArtists = snapshot.hasLoadedTopArtists
            entry.snapshot.savedAt = snapshot.savedAt
            if snapshot.hasLoadedTopArtists { entry.topArtistsSavedAt = now }
        }
    }

    func saveTopArtists(_ snapshot: UserProfileSnapshot, for username: String, scope _: RequestGate.ReadScope, now: Date = .now) {
        saveTopArtists(snapshot, for: username, now: now)
    }

    func saveTopReleases(_ snapshot: UserProfileSnapshot, for username: String, now: Date = .now) {
        updateEntry(for: username, now: now) { entry in
            entry.snapshot.topReleases = snapshot.topReleases
            entry.snapshot.hasLoadedTopReleases = snapshot.hasLoadedTopReleases
            entry.snapshot.savedAt = snapshot.savedAt
            if snapshot.hasLoadedTopReleases { entry.topReleasesSavedAt = now }
        }
    }

    func saveTopReleases(_ snapshot: UserProfileSnapshot, for username: String, scope _: RequestGate.ReadScope, now: Date = .now) {
        saveTopReleases(snapshot, for: username, now: now)
    }

    func saveTopRecordings(_ snapshot: UserProfileSnapshot, for username: String, now: Date = .now) {
        updateEntry(for: username, now: now) { entry in
            entry.snapshot.topRecordings = snapshot.topRecordings
            entry.snapshot.hasLoadedTopRecordings = snapshot.hasLoadedTopRecordings
            entry.snapshot.savedAt = snapshot.savedAt
            if snapshot.hasLoadedTopRecordings { entry.topRecordingsSavedAt = now }
        }
    }

    func saveTopRecordings(_ snapshot: UserProfileSnapshot, for username: String, scope _: RequestGate.ReadScope, now: Date = .now) {
        saveTopRecordings(snapshot, for: username, now: now)
    }

    func removeAll() {
        entries.removeAll()
        try? fileManager.removeItem(at: directory)
        Self.configureDirectory(directory, fileManager: fileManager)
    }

    // Internal solely for focused safety tests. The result contains a fixed
    // SHA-256 filename, never a username or any authentication material.
    func fileURL(for username: String) -> URL? {
        guard let key = Self.canonicalUsername(username) else { return nil }
        return directory.appending(path: "v\(Self.schemaVersion)-\(Self.digest(key)).json")
    }

    private func entry(for key: String, now: Date) -> Entry? {
        if let storedEntry = entries[key] {
            let retained = retainedEntry(storedEntry, at: now)
            guard var entry = retained.entry else {
                entries.removeValue(forKey: key)
                removeFile(for: key)
                return nil
            }
            entry.lastAccessedAt = now
            entries[key] = entry
            if !write(entry, for: key), retained.didChange {
                removeFile(for: key)
            }
            return entry
        }

        guard let url = fileURL(for: key), fileManager.fileExists(atPath: url.path()) else { return nil }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let fileSize = values.fileSize, fileSize > 0, fileSize <= maximumEntryBytes else {
                removeFile(for: key)
                return nil
            }
            let data = try Data(contentsOf: url)
            guard data.count <= maximumEntryBytes else {
                removeFile(for: key)
                return nil
            }
            let disk = try decoder.decode(DiskEntry.self, from: data)
            guard disk.version == Self.schemaVersion, disk.username == key else {
                removeFile(for: key)
                return nil
            }
            let retained = retainedEntry(disk.entry, at: now)
            guard var entry = retained.entry else {
                removeFile(for: key)
                return nil
            }
            entry.lastAccessedAt = now
            entries[key] = entry
            if !write(entry, for: key), retained.didChange {
                removeFile(for: key)
            }
            trimIfNeeded(now: now)
            return entry
        } catch {
            // A locked/protected file is a cache miss; deleting it could turn a
            // temporary device-lock state into permanent data loss.
            if isProtectedFileError(error) { return nil }
            removeFile(for: key)
            return nil
        }
    }

    private func updateEntry(for username: String, now: Date, update: (inout Entry) -> Void) {
        guard let key = Self.canonicalUsername(username) else { return }
        var entry = entry(for: key, now: now) ?? Entry(
            snapshot: .empty,
            overviewSavedAt: nil,
            topArtistsSavedAt: nil,
            topReleasesSavedAt: nil,
            topRecordingsSavedAt: nil,
            createdAt: now,
            lastAccessedAt: now
        )
        update(&entry)
        entry.lastAccessedAt = now
        save(entry, for: key, now: now)
    }

    private func save(_ entry: Entry, for key: String, now: Date) {
        entries[key] = entry
        _ = write(entry, for: key)
        trimIfNeeded(now: now)
        trimMemoryIfNeeded(now: now)
    }

    @discardableResult
    private func write(_ entry: Entry, for key: String) -> Bool {
        guard let url = fileURL(for: key),
              let data = try? encoder.encode(DiskEntry(version: Self.schemaVersion, username: key, entry: entry))
        else { return false }
        // Keep the previous valid disk snapshot when a new value is too large.
        // The current screen still owns the live value; persistence is best effort.
        guard data.count <= maximumEntryBytes else { return false }
        do {
            Self.configureDirectory(directory, fileManager: fileManager)
            try data.write(to: url, options: .atomic)
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path())
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
            return true
        } catch {
            // Disk caching is opportunistic. A full, protected, or unavailable
            // cache must never block a public profile from rendering.
            return false
        }
    }

    private static func configureDirectory(_ directory: URL, fileManager: FileManager) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path())
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private func cachedValue(from entry: Entry, now: Date) -> CachedValue {
        CachedValue(
            snapshot: entry.snapshot,
            isOverviewFresh: Self.isFresh(entry.overviewSavedAt, at: now, timeToLive: timeToLive) && entry.snapshot.hasLoadedOverview,
            isTopArtistsFresh: Self.isFresh(entry.topArtistsSavedAt, at: now, timeToLive: timeToLive) && entry.snapshot.hasLoadedTopArtists,
            isTopReleasesFresh: Self.isFresh(entry.topReleasesSavedAt, at: now, timeToLive: timeToLive) && entry.snapshot.hasLoadedTopReleases,
            isTopRecordingsFresh: Self.isFresh(entry.topRecordingsSavedAt, at: now, timeToLive: timeToLive) && entry.snapshot.hasLoadedTopRecordings
        )
    }

    private func trimIfNeeded(now: Date) {
        let diskEntries = diskEntries(now: now)
        let kept = diskEntries.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        let permitted = kept.prefix(maximumEntryCount)
        let permittedURLs = Set(permitted.map(\.url))
        for item in diskEntries where !permittedURLs.contains(item.url) {
            try? fileManager.removeItem(at: item.url)
            entries.removeValue(forKey: item.username)
        }

        var bytes = 0
        for item in permitted {
            if bytes + item.size <= maximumDiskBytes {
                bytes += item.size
            } else {
                try? fileManager.removeItem(at: item.url)
                entries.removeValue(forKey: item.username)
            }
        }
    }

    private func trimMemoryIfNeeded(now: Date) {
        for key in Array(entries.keys) {
            guard let entry = entries[key] else { continue }
            if let retained = retainedEntry(entry, at: now).entry {
                entries[key] = retained
            } else {
                entries.removeValue(forKey: key)
            }
        }
        guard entries.count > maximumEntryCount else { return }
        for key in entries
            .sorted(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })
            .prefix(entries.count - maximumEntryCount)
            .map(\.key) {
            entries.removeValue(forKey: key)
        }
    }

    private struct DiskItem {
        let url: URL
        let username: String
        let lastAccessedAt: Date
        let size: Int
    }

    private func diskEntries(now: Date) -> [DiskItem] {
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "json" else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            do {
                let fileValues = try url.resourceValues(forKeys: [.fileSizeKey])
                guard let originalFileSize = fileValues.fileSize,
                      originalFileSize > 0,
                      originalFileSize <= maximumEntryBytes
                else {
                    try? fileManager.removeItem(at: url)
                    return nil
                }
                let data = try Data(contentsOf: url)
                guard data.count <= maximumEntryBytes,
                      let disk = try? decoder.decode(DiskEntry.self, from: data),
                      disk.version == Self.schemaVersion,
                      Self.canonicalUsername(disk.username) == disk.username,
                      url == fileURL(for: disk.username)
                else {
                    try? fileManager.removeItem(at: url)
                    return nil
                }
                let retained = retainedEntry(disk.entry, at: now)
                guard let entry = retained.entry else {
                    try? fileManager.removeItem(at: url)
                    entries.removeValue(forKey: disk.username)
                    return nil
                }
                var fileSize = originalFileSize
                if retained.didChange {
                    guard write(entry, for: disk.username) else {
                        try? fileManager.removeItem(at: url)
                        entries.removeValue(forKey: disk.username)
                        return nil
                    }
                    fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? originalFileSize
                }
                return DiskItem(
                    url: url,
                    username: disk.username,
                    lastAccessedAt: entry.lastAccessedAt,
                    size: fileSize
                )
            } catch {
                if !isProtectedFileError(error) { try? fileManager.removeItem(at: url) }
                return nil
            }
        }
    }

    private func retainedEntry(_ source: Entry, at now: Date) -> (entry: Entry?, didChange: Bool) {
        var entry = source
        var didChange = false

        if entry.snapshot.playingNow != nil {
            entry.snapshot.playingNow = nil
            didChange = true
        }
        if shouldDiscardSection(
            loaded: entry.snapshot.hasLoadedOverview,
            savedAt: entry.overviewSavedAt,
            hasContent: !entry.snapshot.recentListens.isEmpty || entry.snapshot.listenCount != nil,
            now: now
        ) {
            entry.snapshot.recentListens = []
            entry.snapshot.listenCount = nil
            entry.snapshot.hasLoadedOverview = false
            entry.overviewSavedAt = nil
            didChange = true
        }
        if shouldDiscardSection(
            loaded: entry.snapshot.hasLoadedTopArtists,
            savedAt: entry.topArtistsSavedAt,
            hasContent: !entry.snapshot.topArtists.isEmpty,
            now: now
        ) {
            entry.snapshot.topArtists = []
            entry.snapshot.hasLoadedTopArtists = false
            entry.topArtistsSavedAt = nil
            didChange = true
        }
        if shouldDiscardSection(
            loaded: entry.snapshot.hasLoadedTopReleases,
            savedAt: entry.topReleasesSavedAt,
            hasContent: !entry.snapshot.topReleases.isEmpty,
            now: now
        ) {
            entry.snapshot.topReleases = []
            entry.snapshot.hasLoadedTopReleases = false
            entry.topReleasesSavedAt = nil
            didChange = true
        }
        if shouldDiscardSection(
            loaded: entry.snapshot.hasLoadedTopRecordings,
            savedAt: entry.topRecordingsSavedAt,
            hasContent: !entry.snapshot.topRecordings.isEmpty,
            now: now
        ) {
            entry.snapshot.topRecordings = []
            entry.snapshot.hasLoadedTopRecordings = false
            entry.topRecordingsSavedAt = nil
            didChange = true
        }

        let hasRetainedSection = entry.overviewSavedAt != nil
            || entry.topArtistsSavedAt != nil
            || entry.topReleasesSavedAt != nil
            || entry.topRecordingsSavedAt != nil
        if !hasRetainedSection, now.timeIntervalSince(entry.createdAt) >= hardRetention {
            return (nil, true)
        }
        return (entry, didChange)
    }

    private func shouldDiscardSection(loaded: Bool, savedAt: Date?, hasContent: Bool, now: Date) -> Bool {
        guard loaded, let savedAt else { return loaded || savedAt != nil || hasContent }
        return now.timeIntervalSince(savedAt) >= hardRetention
    }

    private func removeFile(for key: String) {
        guard let url = fileURL(for: key) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func isProtectedFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(nsError.code)
    }

    private static func canonicalUsername(_ username: String) -> String? {
        let value = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .precomposedStringWithCanonicalMapping
        guard !value.isEmpty, value.utf8.count <= 255 else { return nil }
        return value
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isFresh(_ savedAt: Date?, at now: Date, timeToLive: TimeInterval) -> Bool {
        guard let savedAt else { return false }
        return now.timeIntervalSince(savedAt) < timeToLive
    }
}
