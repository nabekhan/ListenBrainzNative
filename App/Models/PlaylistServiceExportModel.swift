import CryptoKit
import Darwin
import Foundation
import Observation

struct PlaylistServiceExportRecord: Codable, Equatable, Sendable {
    let attemptedAt: Date
}

/// A durable, token-free replay barrier for external playlist creation.
///
/// ListenBrainz exposes no idempotency key or export-status endpoint. A record
/// therefore remains across launches until transport was cancelled before
/// dispatch or the user explicitly confirms checking the destination service.
@MainActor
@Observable
final class PlaylistServiceExportJournal {
    static let shared: PlaylistServiceExportJournal = {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return .init(storageUnavailable: true)
        }
        return .init(directoryURL: root.appending(
            path: "Brainz/playlist-service-exports-v1",
            directoryHint: .isDirectory
        ))
    }()

    @ObservationIgnored private let directoryURL: URL?
    @ObservationIgnored private let storageUnavailable: Bool
    private var loadedKeys: Set<String> = []
    private var unreadableKeys: Set<String> = []
    private var activeClaims: Set<String> = []
    private var records: [String: PlaylistServiceExportRecord] = [:]

    /// A nil directory creates an in-memory journal for focused tests.
    /// Production always supplies the Application Support directory above.
    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL
        storageUnavailable = false
    }

    private init(storageUnavailable: Bool) {
        directoryURL = nil
        self.storageUnavailable = storageUnavailable
    }

    func record(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) -> PlaylistServiceExportRecord? {
        let recordKey = key(username: username, playlistMBID: playlistMBID, service: service)
        loadIfNeeded(username: username, playlistMBID: playlistMBID, service: service)
        return records[recordKey]
    }

    func requiresReview(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) -> Bool {
        let recordKey = key(username: username, playlistMBID: playlistMBID, service: service)
        loadIfNeeded(username: username, playlistMBID: playlistMBID, service: service)
        return storageUnavailable || unreadableKeys.contains(recordKey) || records[recordKey] != nil
    }

    func requiresRecovery(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) -> Bool {
        let recordKey = key(username: username, playlistMBID: playlistMBID, service: service)
        loadIfNeeded(username: username, playlistMBID: playlistMBID, service: service)
        return storageUnavailable || unreadableKeys.contains(recordKey)
    }

    /// Returns only after the replay barrier is on stable storage. The caller
    /// must not dispatch the non-idempotent POST when this returns false.
    func beginAttempt(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService,
        at date: Date
    ) -> Bool {
        let normalizedUsername = Self.normalized(username)
        let recordKey = key(
            username: normalizedUsername,
            playlistMBID: playlistMBID,
            service: service
        )
        loadIfNeeded(
            username: normalizedUsername,
            playlistMBID: playlistMBID,
            service: service
        )
        guard !storageUnavailable,
              !unreadableKeys.contains(recordKey),
              !activeClaims.contains(recordKey),
              records[recordKey] == nil
        else { return false }

        let record = PlaylistServiceExportRecord(attemptedAt: date)
        guard persist(
            record,
            username: normalizedUsername,
            playlistMBID: playlistMBID,
            service: service
        ) else {
            unreadableKeys.insert(recordKey)
            return false
        }
        records[recordKey] = record
        activeClaims.insert(recordKey)
        return true
    }

    func releaseClaim(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) {
        activeClaims.remove(key(
            username: username,
            playlistMBID: playlistMBID,
            service: service
        ))
    }

    /// Clears a definite result or a barrier the user reconciled in the
    /// destination service. A failed clear remains blocked.
    func resolveAfterReview(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) -> Bool {
        let recordKey = key(username: username, playlistMBID: playlistMBID, service: service)
        loadIfNeeded(username: username, playlistMBID: playlistMBID, service: service)
        guard !storageUnavailable,
              !activeClaims.contains(recordKey),
              remove(username: username, playlistMBID: playlistMBID, service: service)
        else { return false }
        unreadableKeys.remove(recordKey)
        records.removeValue(forKey: recordKey)
        loadedKeys.insert(recordKey)
        return true
    }

    private func key(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) -> String {
        "\(Self.normalized(username)):\(playlistMBID.uuidString.lowercased()):\(service.rawValue)"
    }

    private func loadIfNeeded(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) {
        let recordKey = key(username: username, playlistMBID: playlistMBID, service: service)
        guard !loadedKeys.contains(recordKey) else { return }
        loadedKeys.insert(recordKey)
        guard !storageUnavailable,
              let url = fileURL(username: username, playlistMBID: playlistMBID, service: service),
              FileManager.default.fileExists(atPath: url.path())
        else { return }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize <= 64 * 1_024
            else { throw CocoaError(.fileReadCorruptFile) }
            let record = try JSONDecoder().decode(
                PlaylistServiceExportRecord.self,
                from: Data(contentsOf: url)
            )
            records[recordKey] = record
        } catch {
            unreadableKeys.insert(recordKey)
        }
    }

    private func persist(
        _ record: PlaylistServiceExportRecord,
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) -> Bool {
        guard let url = fileURL(
            username: username,
            playlistMBID: playlistMBID,
            service: service
        ) else {
            return directoryURL == nil && !storageUnavailable
        }
        do {
            try Self.writeDurably(JSONEncoder().encode(record), to: url)
            return true
        } catch {
            return false
        }
    }

    private func remove(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) -> Bool {
        guard let url = fileURL(
            username: username,
            playlistMBID: playlistMBID,
            service: service
        ) else {
            return directoryURL == nil && !storageUnavailable
        }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: url.path()) {
                try manager.removeItem(at: url)
                try Self.syncDirectory(url.deletingLastPathComponent())
            }
            return !manager.fileExists(atPath: url.path())
        } catch {
            return false
        }
    }

    private func fileURL(
        username: String,
        playlistMBID: UUID,
        service: PlaylistExternalService
    ) -> URL? {
        let recordKey = key(username: username, playlistMBID: playlistMBID, service: service)
        let digest = SHA256.hash(data: Data(recordKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL?.appending(path: "\(digest).json")
    }

    /// Sync the barrier and its containing directory before a POST can start.
    private static func writeDurably(_ data: Data, to fileURL: URL) throws {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let existed = manager.fileExists(atPath: directory.path())
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !existed {
            try syncDirectory(directory.deletingLastPathComponent())
        }

        let temporary = directory.appending(path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            #if os(iOS)
                try manager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: temporary.path()
                )
            #endif
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            let result = temporary.path.withCString { source in
                fileURL.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }
            guard result == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            #if os(iOS)
                try manager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: fileURL.path()
                )
            #endif
            var protectedURL = fileURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try protectedURL.setResourceValues(resourceValues)
            try syncDirectory(directory)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    private static func syncDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString { Darwin.open($0, O_RDONLY) }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum PlaylistServiceExportNotice: Identifiable, Equatable, Sendable {
    case confirmed(service: PlaylistExternalService, url: URL)
    case failed(id: UUID, message: String)
    case verificationNeeded(id: UUID, service: PlaylistExternalService, message: String)

    var id: String {
        switch self {
        case let .confirmed(service, url):
            "confirmed:\(service.rawValue):\(url.absoluteString)"
        case let .failed(id, _):
            "failed:\(id.uuidString)"
        case let .verificationNeeded(id, service, _):
            "verification:\(service.rawValue):\(id.uuidString)"
        }
    }
}

@MainActor
@Observable
final class PlaylistServiceExportModel {
    let account: Account
    let playlistMBID: UUID

    private let provider: any PlaylistServiceExportProviding
    private let journal: PlaylistServiceExportJournal
    @ObservationIgnored private let now: () -> Date

    private(set) var isExporting = false
    private(set) var activeService: PlaylistExternalService?
    private(set) var notice: PlaylistServiceExportNotice?

    init(
        account: Account,
        playlistMBID: UUID,
        provider: (any PlaylistServiceExportProviding)? = nil,
        journal: PlaylistServiceExportJournal = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.account = account
        self.playlistMBID = playlistMBID
        self.provider = provider
            ?? ListenBrainzPlaylistServiceExportProvider(token: account.token)
        self.journal = journal
        self.now = now
    }

    func export(to service: PlaylistExternalService, isPublic: Bool) async {
        guard account.isAuthenticated,
              !isExporting,
              !requiresReview(for: service)
        else { return }

        notice = nil
        guard journal.beginAttempt(
            username: account.username,
            playlistMBID: playlistMBID,
            service: service,
            at: now()
        ) else {
            notice = .failed(id: UUID(), message: safetyStorageMessage)
            return
        }

        isExporting = true
        activeService = service
        defer {
            journal.releaseClaim(
                username: account.username,
                playlistMBID: playlistMBID,
                service: service
            )
            isExporting = false
            activeService = nil
        }

        do {
            let url = try await provider.export(
                playlistMBID: playlistMBID,
                to: service,
                isPublic: isPublic
            )
            notice = .confirmed(service: service, url: url)
        } catch let error as PlaylistServiceExportProviderError {
            switch error {
            case .cancelledBeforeTransport:
                journal.releaseClaim(
                    username: account.username,
                    playlistMBID: playlistMBID,
                    service: service
                )
                if !resolve(service) {
                    notice = .failed(id: UUID(), message: safetyResetMessage)
                }
            case .indeterminateExport:
                notice = .verificationNeeded(
                    id: UUID(),
                    service: service,
                    message: verificationMessage(for: service)
                )
            }
        } catch {
            // An injected or future transport error cannot prove that the
            // external playlist was not created.
            notice = .verificationNeeded(
                id: UUID(),
                service: service,
                message: verificationMessage(for: service)
            )
        }
    }

    func requiresReview(for service: PlaylistExternalService) -> Bool {
        journal.requiresReview(
            username: account.username,
            playlistMBID: playlistMBID,
            service: service
        )
    }

    func acknowledgeConfirmedExport() {
        guard case let .confirmed(service, _) = notice else { return }
        _ = resolve(service)
        notice = nil
    }

    func clearAfterUserReview(_ service: PlaylistExternalService) {
        guard !isExporting else { return }
        guard resolve(service) else {
            notice = .failed(id: UUID(), message: safetyResetMessage)
            return
        }
        if case let .verificationNeeded(_, noticeService, _) = notice,
           noticeService == service {
            notice = nil
        }
    }

    func dismissNotice() {
        guard case .failed = notice else { return }
        notice = nil
    }

    func acknowledgeVerificationNotice() {
        guard case .verificationNeeded = notice else { return }
        notice = nil
    }

    func verificationMessage(for service: PlaylistExternalService) -> String {
        if journal.requiresRecovery(
            username: account.username,
            playlistMBID: playlistMBID,
            service: service
        ) {
            return String(localized: "Brainz can’t read its duplicate-protection check. Check \(service.label) before allowing another export.")
        }
        return String(localized: "An export to \(service.label) may already exist. Check \(service.label) before allowing another export.")
    }

    private var safetyStorageMessage: String {
        String(localized: "Brainz couldn’t save its duplicate-protection check, so no playlist was sent.")
    }

    private var safetyResetMessage: String {
        String(localized: "Brainz couldn’t reset its duplicate-protection check. Exporting again is still paused.")
    }

    private func resolve(_ service: PlaylistExternalService) -> Bool {
        journal.resolveAfterReview(
            username: account.username,
            playlistMBID: playlistMBID,
            service: service
        )
    }
}

#if DEBUG
struct PlaylistServiceExportPreviewProvider: PlaylistServiceExportProviding {
    func export(
        playlistMBID: UUID,
        to service: PlaylistExternalService,
        isPublic: Bool
    ) async throws -> URL {
        try await Task.sleep(for: .milliseconds(250))
        switch service {
        case .spotify:
            return URL(string: "https://open.spotify.com/playlist/visual")!
        case .appleMusic:
            return URL(string: "https://music.apple.com/ca/playlist/visual/pl.visual")!
        case .soundCloud:
            return URL(string: "https://soundcloud.com/visual/sets/playlist")!
        }
    }
}
#endif
