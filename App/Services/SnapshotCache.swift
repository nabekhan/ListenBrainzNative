import Foundation

actor SnapshotCache {
    struct HistoryDayListenKey: Hashable, Sendable {
        let listenedAt: Int
        let recordingMSID: UUID
    }

    struct CachedHistoryDay: Sendable {
        let listens: [Listen]
        let canLoadMore: Bool
        let savedAt: Date
        let isFresh: Bool
    }

    static let shared = SnapshotCache()

    private static let historyDaySchemaVersion = 1
    private static let historyDayFreshness: TimeInterval = 5 * 60
    private static let historyDayRetention: TimeInterval = 30 * 24 * 60 * 60
    private static let maximumHistoryDays = 30
    private static let maximumListensPerHistoryDay = 2_000
    private static let maximumHistoryDayEntryBytes = 4 * 1_024 * 1_024
    private static let maximumHistoryDayAccountBytes = 16 * 1_024 * 1_024

    private struct HistoryDayKey: Codable, Hashable {
        let earliest: Int
        let latest: Int
        init(_ bounds: HistoryDayBounds) {
            earliest = Int(bounds.earliest.timeIntervalSince1970)
            latest = Int(bounds.latest.timeIntervalSince1970)
        }
    }

    private struct HistoryDayEntry: Codable {
        let key: HistoryDayKey
        var listens: [Listen]
        var canLoadMore: Bool
        let savedAt: Date
        var lastAccessedAt: Date
    }

    private struct HistoryDayDisk: Codable {
        let version: Int
        let username: String
        var entries: [HistoryDayEntry]
    }

    private let fileManager: FileManager
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var activeLeases: [String: UUID] = [:]

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager
        let root = rootDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = root.appending(path: "ListenBrainzNative", directoryHint: .isDirectory)
        Self.configureDirectory(directory, fileManager: fileManager)
    }

    func beginSession(username: String) -> UUID {
        let lease = UUID()
        activeLeases[username] = lease
        return lease
    }

    func load(username: String, lease: UUID) -> ListeningSnapshot? {
        guard activeLeases[username] == lease else { return nil }
        guard let data = try? Data(contentsOf: fileURL(username: username)) else { return nil }
        return try? decoder.decode(ListeningSnapshot.self, from: data)
    }

    func save(_ snapshot: ListeningSnapshot, username: String, lease: UUID) {
        guard activeLeases[username] == lease else { return }
        guard let data = try? encoder.encode(snapshot) else { return }
        write(data, to: fileURL(username: username))
    }

    func loadHistoryDay(username: String, lease: UUID, bounds: HistoryDayBounds, now: Date = .now) -> CachedHistoryDay? {
        guard activeLeases[username] == lease else { return nil }
        guard var disk = historyDayDisk(username: username, now: now),
              let index = disk.entries.firstIndex(where: { $0.key == HistoryDayKey(bounds) })
        else { return nil }
        var entry = disk.entries[index]
        entry.lastAccessedAt = now
        disk.entries[index] = entry
        persistHistoryDayDisk(disk, username: username)
        return CachedHistoryDay(
            listens: entry.listens,
            canLoadMore: entry.canLoadMore,
            savedAt: entry.savedAt,
            isFresh: now.timeIntervalSince(entry.savedAt) < Self.historyDayFreshness
        )
    }

    func saveHistoryDay(listens: [Listen], canLoadMore: Bool, username: String, lease: UUID, bounds: HistoryDayBounds, now: Date = .now) {
        guard activeLeases[username] == lease else { return }
        let key = HistoryDayKey(bounds)
        let validListens = Array(listens.filter {
            !$0.isPlayingNow && $0.listenedAt > bounds.earliest && $0.listenedAt < bounds.latest
        }.prefix(Self.maximumListensPerHistoryDay))
        let candidate = HistoryDayEntry(
            key: key,
            listens: validListens,
            // If retention clipped a malformed/oversized response, keep the
            // cursor pageable so a later server read can recover omitted rows.
            canLoadMore: canLoadMore || listens.count > Self.maximumListensPerHistoryDay,
            savedAt: now,
            lastAccessedAt: now
        )
        guard let candidateData = try? encoder.encode(candidate), candidateData.count <= Self.maximumHistoryDayEntryBytes else { return }
        var disk = historyDayDisk(username: username, now: now) ?? HistoryDayDisk(
            version: Self.historyDaySchemaVersion, username: username, entries: []
        )
        disk.entries.removeAll { $0.key == key }
        disk.entries.append(candidate)
        disk.entries = trimmedHistoryDayEntries(disk.entries, now: now)
        persistHistoryDayDisk(disk, username: username)
    }

    func removeHistoryDayListen(username: String, lease: UUID, listenedAt: Int, recordingMSID: UUID, now: Date = .now) {
        removeHistoryDayListens(
            username: username,
            lease: lease,
            keys: [HistoryDayListenKey(listenedAt: listenedAt, recordingMSID: recordingMSID)],
            now: now
        )
    }

    func removeHistoryDayListens(
        username: String,
        lease: UUID,
        keys: Set<HistoryDayListenKey>,
        now: Date = .now
    ) {
        guard !keys.isEmpty else { return }
        guard activeLeases[username] == lease, var disk = historyDayDisk(username: username, now: now) else { return }
        var changed = false
        for index in disk.entries.indices {
            let original = disk.entries[index].listens
            disk.entries[index].listens = original.filter {
                guard let recordingMSID = $0.recording.identity.msid else { return true }
                return !keys.contains(HistoryDayListenKey(
                    listenedAt: Int($0.listenedAt.timeIntervalSince1970),
                    recordingMSID: recordingMSID
                ))
            }
            changed = changed || disk.entries[index].listens.count != original.count
        }
        if changed { persistHistoryDayDisk(disk, username: username) }
    }

    func invalidate(username: String) throws {
        activeLeases.removeValue(forKey: username)
        var removalError: Error?
        for url in [fileURL(username: username), historyDayFileURL(username: username)] where fileManager.fileExists(atPath: url.path()) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                removalError = removalError ?? error
            }
        }
        if let removalError { throw removalError }
    }

    private func historyDayDisk(username: String, now: Date) -> HistoryDayDisk? {
        let url = historyDayFileURL(username: username)
        guard fileManager.fileExists(atPath: url.path()) else { return nil }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size > 0, size <= Self.maximumHistoryDayAccountBytes else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maximumHistoryDayAccountBytes else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            var disk = try decoder.decode(HistoryDayDisk.self, from: data)
            guard disk.version == Self.historyDaySchemaVersion, disk.username == username else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            guard Set(disk.entries.map(\.key)).count == disk.entries.count else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            let originalCount = disk.entries.count
            disk.entries = trimmedHistoryDayEntries(disk.entries, now: now)
            if disk.entries.count != originalCount { persistHistoryDayDisk(disk, username: username) }
            return disk
        } catch {
            if !isProtectedFileError(error) { try? fileManager.removeItem(at: url) }
            return nil
        }
    }

    private func trimmedHistoryDayEntries(_ entries: [HistoryDayEntry], now: Date) -> [HistoryDayEntry] {
        return entries.filter { entry in
            entry.key.latest > entry.key.earliest
                && entry.listens.count <= Self.maximumListensPerHistoryDay
                && now.timeIntervalSince(entry.savedAt) < Self.historyDayRetention
                && entry.savedAt <= now
                && entry.listens.allSatisfy {
                    !$0.isPlayingNow
                        && $0.listenedAt.timeIntervalSince1970 > Double(entry.key.earliest)
                        && $0.listenedAt.timeIntervalSince1970 < Double(entry.key.latest)
                }
        }
        .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        .prefix(Self.maximumHistoryDays)
        .map { $0 }
    }

    private func persistHistoryDayDisk(_ disk: HistoryDayDisk, username: String) {
        guard disk.username == username,
              let data = try? encoder.encode(disk),
              data.count <= Self.maximumHistoryDayAccountBytes
        else { return }
        write(data, to: historyDayFileURL(username: username))
    }

    private func write(_ data: Data, to url: URL) {
        do {
            Self.configureDirectory(directory, fileManager: fileManager)
            try data.write(to: url, options: .atomic)
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path())
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
        } catch { }
    }

    private static func configureDirectory(_ directory: URL, fileManager: FileManager) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path())
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private func isProtectedFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(nsError.code)
    }

    private func fileURL(username: String) -> URL { directory.appending(path: "\(safeFilename(username)).json") }
    private func historyDayFileURL(username: String) -> URL { directory.appending(path: "\(safeFilename(username)).history-days.v\(Self.historyDaySchemaVersion).json") }
    private func safeFilename(_ username: String) -> String {
        Data(username.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
