import CoreTransferable
import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

enum UserDataExportStorageError: Error, Equatable {
    case unavailable
    case corruptState
    case reconciliationRequired
    case insufficientSpace
    case invalidArchive
}

struct UserDataExportDownloadTarget: Sendable {
    fileprivate let accountFingerprint: String
    fileprivate let generation: Int
    let exportID: Int
    let range: UserDataExportRange
    let partialURL: URL
}

protocol UserDataExportStoring: Sendable {
    func beginCreation(account: Account, range: UserDataExportRange) async throws -> UUID
    func cancelCreationBeforeDispatch(account: Account, reservationID: UUID) async throws
    func finishCreation(
        account: Account,
        reservationID: UUID,
        exportID: Int
    ) async throws
    func reconcileCreation(account: Account, jobs: [UserDataExportJob]) async throws
    func existingArchive(
        account: Account,
        exportID: Int,
        range: UserDataExportRange
    ) async throws -> UserDataExportArchive?
    func prepareDownload(
        account: Account,
        exportID: Int,
        range: UserDataExportRange
    ) async throws -> UserDataExportDownloadTarget
    func finishDownload(
        account: Account,
        target: UserDataExportDownloadTarget
    ) async throws -> UserDataExportArchive
    func abandonDownload(_ target: UserDataExportDownloadTarget) async
    func removeArchive(account: Account, exportID: Int) async throws
    func cleanupExpired() async
    func purgeAll() async throws
}

/// Protected, non-backed-up storage for short-lived account export files and
/// the token-free reservation that prevents replaying an uncertain create.
actor UserDataExportStorage: UserDataExportStoring {
    static let shared: UserDataExportStorage = {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return UserDataExportStorage(storageUnavailable: true)
        }
        return UserDataExportStorage(
            rootDirectory: root
                .appending(path: "Brainz", directoryHint: .isDirectory)
                .appending(path: "user-data-exports-v1", directoryHint: .isDirectory)
        )
    }()

    private static let schemaVersion = 1
    private static let maximumManifestBytes = 512 * 1_024
    private static let maximumArchiveBytes: Int64 = 4 * 1_024 * 1_024 * 1_024
    private static let minimumAvailableBytes: Int64 = 256 * 1_024 * 1_024
    private static let archiveRetention: TimeInterval = 24 * 60 * 60

    private struct CreationReservation: Codable, Equatable {
        let id: UUID
        let range: UserDataExportRange
        let reservedAt: Date
    }

    private struct ArchiveRecord: Codable, Equatable {
        let exportID: Int
        let range: UserDataExportRange
        let downloadedAt: Date
        let byteCount: Int64
        let digest: String
    }

    private struct Manifest: Codable {
        let version: Int
        let accountFingerprint: String
        var reservation: CreationReservation?
        var lastListedAt: Date?
        var lastCreatedExportID: Int?
        var archives: [ArchiveRecord]
    }

    private let fileManager: FileManager
    private let rootDirectory: URL?
    private let storageUnavailable: Bool
    private var generation = 0

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        storageUnavailable = false
    }

    private init(storageUnavailable: Bool) {
        rootDirectory = nil
        fileManager = .default
        self.storageUnavailable = storageUnavailable
    }

    func beginCreation(
        account: Account,
        range: UserDataExportRange
    ) throws -> UUID {
        let fingerprint = try accountFingerprint(account)
        var manifest = try loadManifest(fingerprint: fingerprint)
        guard manifest.reservation == nil,
              let lastListedAt = manifest.lastListedAt,
              Date.now.timeIntervalSince(lastListedAt) < 5 * 60
        else {
            throw UserDataExportStorageError.reconciliationRequired
        }
        let reservation = CreationReservation(
            id: UUID(),
            range: range,
            reservedAt: .now
        )
        manifest.reservation = reservation
        try persist(manifest)
        return reservation.id
    }

    func cancelCreationBeforeDispatch(
        account: Account,
        reservationID: UUID
    ) throws {
        let fingerprint = try accountFingerprint(account)
        var manifest = try loadManifest(fingerprint: fingerprint)
        guard manifest.reservation?.id == reservationID else { return }
        manifest.reservation = nil
        try persist(manifest)
    }

    func finishCreation(
        account: Account,
        reservationID: UUID,
        exportID: Int
    ) throws {
        guard exportID > 0 else { throw UserDataExportStorageError.corruptState }
        let fingerprint = try accountFingerprint(account)
        var manifest = try loadManifest(fingerprint: fingerprint)
        guard manifest.reservation?.id == reservationID else {
            throw UserDataExportStorageError.corruptState
        }
        manifest.lastCreatedExportID = exportID
        manifest.reservation = nil
        try persist(manifest)
    }

    /// One successful, explicit list is the recovery boundary for an
    /// indeterminate create. A matching job is remembered; no match means the
    /// server's authoritative list has established that a new attempt is safe.
    func reconcileCreation(account: Account, jobs: [UserDataExportJob]) throws {
        let fingerprint = try accountFingerprint(account)
        var manifest = try loadManifest(fingerprint: fingerprint)
        manifest.lastListedAt = .now
        guard let reservation = manifest.reservation else {
            _ = try removeExpiredArchives(from: &manifest, now: .now)
            try persist(manifest)
            return
        }

        let earliestPlausibleCreation = reservation.reservedAt.addingTimeInterval(-5 * 60)
        if let match = jobs.first(where: {
            $0.range == reservation.range && $0.createdAt >= earliestPlausibleCreation
        }) {
            manifest.lastCreatedExportID = match.id
        }
        manifest.reservation = nil
        _ = try removeExpiredArchives(from: &manifest, now: .now)
        try persist(manifest)
    }

    func existingArchive(
        account: Account,
        exportID: Int,
        range: UserDataExportRange
    ) throws -> UserDataExportArchive? {
        let fingerprint = try accountFingerprint(account)
        var manifest = try loadManifest(fingerprint: fingerprint)
        if try removeExpiredArchives(from: &manifest, now: .now) {
            try persist(manifest)
        }
        guard let record = manifest.archives.first(where: { $0.exportID == exportID }) else {
            return nil
        }
        let url = try archiveURL(fingerprint: fingerprint, exportID: exportID)
        let metadataIsValid = record.range == range
            && record.byteCount > 0
            && record.byteCount <= Self.maximumArchiveBytes
        let archiveIsValid = metadataIsValid
            && ((try? validateArchive(url, against: record)) == true)
        guard archiveIsValid else {
            if fileManager.fileExists(atPath: url.path()) {
                try fileManager.removeItem(at: url)
                try syncDirectory(url.deletingLastPathComponent())
            }
            manifest.archives.removeAll { $0.exportID == exportID }
            try persist(manifest)
            return nil
        }
        return UserDataExportArchive(
            exportID: exportID,
            range: range,
            downloadedAt: record.downloadedAt,
            byteCount: record.byteCount,
            fileURL: url
        )
    }

    func prepareDownload(
        account: Account,
        exportID: Int,
        range: UserDataExportRange
    ) throws -> UserDataExportDownloadTarget {
        guard exportID > 0 else { throw UserDataExportStorageError.corruptState }
        let fingerprint = try accountFingerprint(account)
        _ = try loadManifest(fingerprint: fingerprint)
        let accountDirectory = try configuredAccountDirectory(fingerprint: fingerprint)
        let archiveDirectory = accountDirectory.appending(
            path: "archives",
            directoryHint: .isDirectory
        )
        try configureDirectory(archiveDirectory)
        try requireAvailableSpace(at: archiveDirectory)

        let partialURL = archiveDirectory.appending(
            path: ".export-\(exportID)-\(UUID().uuidString).partial"
        )
        guard !fileManager.fileExists(atPath: partialURL.path()) else {
            throw UserDataExportStorageError.unavailable
        }
        return UserDataExportDownloadTarget(
            accountFingerprint: fingerprint,
            generation: generation,
            exportID: exportID,
            range: range,
            partialURL: partialURL
        )
    }

    func finishDownload(
        account: Account,
        target: UserDataExportDownloadTarget
    ) throws -> UserDataExportArchive {
        let fingerprint = try accountFingerprint(account)
        guard target.generation == generation,
              target.accountFingerprint == fingerprint,
              target.exportID > 0
        else {
            try? fileManager.removeItem(at: target.partialURL)
            throw CancellationError()
        }

        var manifest = try loadManifest(fingerprint: fingerprint)
        let attributes = try fileManager.attributesOfItem(atPath: target.partialURL.path())
        guard (attributes[.type] as? FileAttributeType) == .typeRegular,
              let number = attributes[.size] as? NSNumber
        else { throw UserDataExportStorageError.invalidArchive }
        let byteCount = number.int64Value
        guard byteCount >= 4, byteCount <= Self.maximumArchiveBytes else {
            throw UserDataExportStorageError.invalidArchive
        }

        try configureFile(target.partialURL)
        let digest = try fileDigest(target.partialURL)
        let finalURL = try archiveURL(
            fingerprint: fingerprint,
            exportID: target.exportID
        )
        if fileManager.fileExists(atPath: finalURL.path()) {
            try fileManager.removeItem(at: finalURL)
        }
        guard Darwin.rename(target.partialURL.path(), finalURL.path()) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try configureFile(finalURL)
        try syncDirectory(finalURL.deletingLastPathComponent())

        let record = ArchiveRecord(
            exportID: target.exportID,
            range: target.range,
            downloadedAt: .now,
            byteCount: byteCount,
            digest: digest
        )
        manifest.archives.removeAll { $0.exportID == target.exportID }
        manifest.archives.append(record)
        do {
            try persist(manifest)
        } catch {
            try? fileManager.removeItem(at: finalURL)
            throw error
        }
        return UserDataExportArchive(
            exportID: target.exportID,
            range: target.range,
            downloadedAt: record.downloadedAt,
            byteCount: byteCount,
            fileURL: finalURL
        )
    }

    func abandonDownload(_ target: UserDataExportDownloadTarget) {
        try? fileManager.removeItem(at: target.partialURL)
    }

    func removeArchive(account: Account, exportID: Int) throws {
        let fingerprint = try accountFingerprint(account)
        var manifest = try loadManifest(fingerprint: fingerprint)
        let url = try archiveURL(fingerprint: fingerprint, exportID: exportID)
        if fileManager.fileExists(atPath: url.path()) {
            try fileManager.removeItem(at: url)
            try syncDirectory(url.deletingLastPathComponent())
        }
        manifest.archives.removeAll { $0.exportID == exportID }
        try persist(manifest)
    }

    func cleanupExpired() {
        guard !storageUnavailable, let rootDirectory else { return }
        guard let accountDirectories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for directory in accountDirectories {
            guard Self.isFingerprint(directory.lastPathComponent),
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            do {
                try removePartialFiles(in: directory)
                var manifest = try loadManifest(fingerprint: directory.lastPathComponent)
                try removeOrphanedArchiveFiles(in: directory, manifest: manifest)
                _ = try removeExpiredArchives(from: &manifest, now: .now)
                try persist(manifest)
            } catch {
                // A corrupt manifest cannot safely prove which private files
                // are current. Prefer discarding the account-local download
                // cache; a locked/unavailable directory remains for the next
                // successful maintenance pass.
                if fileManager.fileExists(atPath: directory.path()),
                   (try? fileManager.removeItem(at: directory)) != nil {
                    try? syncDirectory(rootDirectory)
                }
                continue
            }
        }
    }

    func purgeAll() throws {
        generation &+= 1
        guard !storageUnavailable, let rootDirectory else {
            throw UserDataExportStorageError.unavailable
        }
        if fileManager.fileExists(atPath: rootDirectory.path()) {
            try fileManager.removeItem(at: rootDirectory)
            try syncDirectory(rootDirectory.deletingLastPathComponent())
        }
    }

    private func loadManifest(fingerprint: String) throws -> Manifest {
        guard !storageUnavailable,
              let rootDirectory,
              Self.isFingerprint(fingerprint)
        else { throw UserDataExportStorageError.unavailable }

        let accountDirectory = rootDirectory.appending(
            path: fingerprint,
            directoryHint: .isDirectory
        )
        let url = accountDirectory.appending(path: "manifest.json")
        guard fileManager.fileExists(atPath: url.path()) else {
            try configureDirectory(accountDirectory)
            return Manifest(
                version: Self.schemaVersion,
                accountFingerprint: fingerprint,
                reservation: nil,
                lastListedAt: nil,
                lastCreatedExportID: nil,
                archives: []
            )
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              (1 ... Self.maximumManifestBytes).contains(size)
        else { throw UserDataExportStorageError.corruptState }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumManifestBytes,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.version == Self.schemaVersion,
              manifest.accountFingerprint == fingerprint,
              manifest.archives.count <= 1_000,
              manifest.archives.allSatisfy({
                  $0.exportID > 0
                      && $0.byteCount > 0
                      && $0.byteCount <= Self.maximumArchiveBytes
                      && Self.isFingerprint($0.digest)
              })
        else { throw UserDataExportStorageError.corruptState }
        return manifest
    }

    private func persist(_ manifest: Manifest) throws {
        guard let rootDirectory,
              manifest.version == Self.schemaVersion,
              Self.isFingerprint(manifest.accountFingerprint)
        else { throw UserDataExportStorageError.unavailable }
        let directory = rootDirectory.appending(
            path: manifest.accountFingerprint,
            directoryHint: .isDirectory
        )
        try configureDirectory(directory)
        let url = directory.appending(path: "manifest.json")
        let data = try JSONEncoder().encode(manifest)
        guard data.count <= Self.maximumManifestBytes else {
            throw UserDataExportStorageError.corruptState
        }
        try writeDurably(data, to: url)
    }

    private func removeExpiredArchives(
        from manifest: inout Manifest,
        now: Date
    ) throws -> Bool {
        let expired = manifest.archives.filter {
            now.timeIntervalSince($0.downloadedAt) >= Self.archiveRetention
        }
        guard !expired.isEmpty else { return false }
        var removedIDs: Set<Int> = []
        for record in expired {
            let url = try archiveURL(
                fingerprint: manifest.accountFingerprint,
                exportID: record.exportID
            )
            if !fileManager.fileExists(atPath: url.path()) {
                removedIDs.insert(record.exportID)
            } else if (try? fileManager.removeItem(at: url)) != nil {
                removedIDs.insert(record.exportID)
            }
        }
        guard !removedIDs.isEmpty else { return false }
        manifest.archives.removeAll { record in
            removedIDs.contains(record.exportID)
        }
        if let archiveDirectory = try? archiveURL(
            fingerprint: manifest.accountFingerprint,
            exportID: removedIDs.first ?? 1
        ).deletingLastPathComponent() {
            try? syncDirectory(archiveDirectory)
        }
        return true
    }

    private func validateArchive(
        _ url: URL,
        against record: ArchiveRecord
    ) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              Int64(values.fileSize ?? -1) == record.byteCount
        else { return false }
        return try fileDigest(url) == record.digest
    }

    private func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1 * 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func accountFingerprint(_ account: Account) throws -> String {
        let username = account.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        guard account.isAuthenticated,
              !username.isEmpty,
              username.utf8.count <= 255,
              !account.token.isEmpty
        else { throw UserDataExportStorageError.unavailable }
        let material = "user-data-export-v1\u{0}\(username)\u{0}\(account.token)"
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func configuredAccountDirectory(fingerprint: String) throws -> URL {
        guard let rootDirectory else { throw UserDataExportStorageError.unavailable }
        let directory = rootDirectory.appending(
            path: fingerprint,
            directoryHint: .isDirectory
        )
        try configureDirectory(directory)
        return directory
    }

    private func archiveURL(fingerprint: String, exportID: Int) throws -> URL {
        guard exportID > 0 else { throw UserDataExportStorageError.corruptState }
        return try configuredAccountDirectory(fingerprint: fingerprint)
            .appending(path: "archives", directoryHint: .isDirectory)
            .appending(path: "export-\(exportID).zip")
    }

    private func requireAvailableSpace(at directory: URL) throws {
        let values = try directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < Self.minimumAvailableBytes {
            throw UserDataExportStorageError.insufficientSpace
        }
    }

    private func removePartialFiles(in accountDirectory: URL) throws {
        let archiveDirectory = accountDirectory.appending(
            path: "archives",
            directoryHint: .isDirectory
        )
        guard let files = try? fileManager.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for file in files where file.pathExtension == "partial" {
            try fileManager.removeItem(at: file)
        }
    }

    private func removeOrphanedArchiveFiles(
        in accountDirectory: URL,
        manifest: Manifest
    ) throws {
        let archiveDirectory = accountDirectory.appending(
            path: "archives",
            directoryHint: .isDirectory
        )
        guard let files = try? fileManager.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }

        let expectedNames = Set(manifest.archives.map { "export-\($0.exportID).zip" })
        var removedFile = false
        for file in files where !expectedNames.contains(file.lastPathComponent) {
            try fileManager.removeItem(at: file)
            removedFile = true
        }
        if removedFile {
            try syncDirectory(archiveDirectory)
        }
    }

    private func configureDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path()
        )
        #if os(iOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directory.path()
            )
        #endif
        try excludeFromBackup(directory)
    }

    private func configureFile(_ url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path()
        )
        #if os(iOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path()
            )
        #endif
        try excludeFromBackup(url)
    }

    private func writeDurably(_ data: Data, to destination: URL) throws {
        try configureDirectory(destination.deletingLastPathComponent())
        let temporary = destination.deletingLastPathComponent().appending(
            path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporary)
            try configureFile(temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            guard Darwin.rename(temporary.path(), destination.path()) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            try configureFile(destination)
            try syncDirectory(destination.deletingLastPathComponent())
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private func syncDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString { Darwin.open($0, O_RDONLY) }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func isFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
        }
    }
}

enum UserDataExportShareStaging {
    private static let directoryName = "Brainz-Shared-User-Data"
    private static let staleAge: TimeInterval = 24 * 60 * 60

    static func stage(_ archive: UserDataExportArchive) throws -> URL {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(
            path: directoryName,
            directoryHint: .isDirectory
        )
        try configureDirectory(root, fileManager: manager)
        cleanupStaleFiles(in: root, fileManager: manager)

        let directory = root.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try configureDirectory(directory, fileManager: manager)
        let destination = directory.appending(
            path: "ListenBrainz-data-export-\(archive.exportID).zip"
        )
        try manager.copyItem(at: archive.fileURL, to: destination)
        try configureFile(destination, fileManager: manager)
        let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? -1) == archive.byteCount else {
            try? manager.removeItem(at: directory)
            throw UserDataExportStorageError.invalidArchive
        }
        return destination
    }

    static func cleanupStaleFiles(
        in root: URL? = nil,
        now: Date = .now,
        fileManager: FileManager = .default
    ) {
        let root = root ?? fileManager.temporaryDirectory.appending(
            path: directoryName,
            directoryHint: .isDirectory
        )
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = now.addingTimeInterval(-staleAge)
        for url in contents {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey]
            ),
            values.isDirectory == true,
            let modifiedAt = values.contentModificationDate,
            modifiedAt < cutoff
            else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    static func purgeAll(fileManager: FileManager = .default) throws {
        let root = fileManager.temporaryDirectory.appending(
            path: directoryName,
            directoryHint: .isDirectory
        )
        if fileManager.fileExists(atPath: root.path()) {
            try fileManager.removeItem(at: root)
        }
    }

    private static func configureDirectory(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        #if os(iOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path()
            )
        #endif
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private static func configureFile(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path()
        )
        #if os(iOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path()
            )
        #endif
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}

extension UserDataExportArchive: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            SentTransferredFile(try UserDataExportShareStaging.stage(archive))
        }
    }
}
