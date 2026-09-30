import CryptoKit
import Darwin
import Foundation
import ListenBrainzKit
import Observation

struct PlaylistServiceImportRecord: Codable, Equatable, Sendable {
    let attemptedAt: Date
}

/// A durable, token-free replay barrier for linked-service imports.
///
/// The server offers no idempotency key or operation status. The barrier
/// remains until a confirmed result or the listener explicitly reconciles the
/// possible copy in Owned Playlists.
@MainActor
@Observable
final class PlaylistServiceImportJournal {
    static let shared: PlaylistServiceImportJournal = {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return .init(storageUnavailable: true)
        }
        return .init(directoryURL: root.appending(
            path: "Brainz/playlist-service-imports-v1",
            directoryHint: .isDirectory
        ))
    }()

    @ObservationIgnored private let directoryURL: URL?
    @ObservationIgnored private let storageUnavailable: Bool
    private var loadedKeys: Set<String> = []
    private var unreadableKeys: Set<String> = []
    private var activeClaims: Set<String> = []
    private var records: [String: PlaylistServiceImportRecord] = [:]

    /// A nil directory creates an in-memory journal for focused tests.
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
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) -> PlaylistServiceImportRecord? {
        let recordKey = key(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        loadIfNeeded(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        return records[recordKey]
    }

    func requiresReview(
        username: String,
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) -> Bool {
        let recordKey = key(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        loadIfNeeded(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        return storageUnavailable || unreadableKeys.contains(recordKey) || records[recordKey] != nil
    }

    func requiresRecovery(
        username: String,
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) -> Bool {
        let recordKey = key(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        loadIfNeeded(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        return storageUnavailable || unreadableKeys.contains(recordKey)
    }

    /// Returns only after the replay barrier is on stable storage.
    func beginAttempt(
        username: String,
        service: PlaylistExternalService,
        externalPlaylistID: String,
        at date: Date
    ) -> Bool {
        let normalizedUsername = Self.normalized(username)
        let recordKey = key(
            username: normalizedUsername,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        loadIfNeeded(
            username: normalizedUsername,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        guard !storageUnavailable,
              !unreadableKeys.contains(recordKey),
              !activeClaims.contains(recordKey),
              records[recordKey] == nil
        else { return false }

        let record = PlaylistServiceImportRecord(attemptedAt: date)
        guard persist(
            record,
            username: normalizedUsername,
            service: service,
            externalPlaylistID: externalPlaylistID
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
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) {
        activeClaims.remove(key(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        ))
    }

    func resolveAfterReview(
        username: String,
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) -> Bool {
        let recordKey = key(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        loadIfNeeded(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        guard !storageUnavailable,
              !activeClaims.contains(recordKey),
              remove(
                  username: username,
                  service: service,
                  externalPlaylistID: externalPlaylistID
              )
        else { return false }
        unreadableKeys.remove(recordKey)
        records.removeValue(forKey: recordKey)
        loadedKeys.insert(recordKey)
        return true
    }

    private func key(
        username: String,
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) -> String {
        "\(Self.normalized(username)):\(service.rawValue):\(externalPlaylistID)"
    }

    private func loadIfNeeded(
        username: String,
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) {
        let recordKey = key(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        )
        guard !loadedKeys.contains(recordKey) else { return }
        loadedKeys.insert(recordKey)
        guard !storageUnavailable,
              let url = fileURL(
                  username: username,
                  service: service,
                  externalPlaylistID: externalPlaylistID
              ),
              FileManager.default.fileExists(atPath: url.path())
        else { return }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize <= 64 * 1_024
            else { throw CocoaError(.fileReadCorruptFile) }
            records[recordKey] = try JSONDecoder().decode(
                PlaylistServiceImportRecord.self,
                from: Data(contentsOf: url)
            )
        } catch {
            unreadableKeys.insert(recordKey)
        }
    }

    private func persist(
        _ record: PlaylistServiceImportRecord,
        username: String,
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) -> Bool {
        guard let url = fileURL(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
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
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) -> Bool {
        guard let url = fileURL(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
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
        service: PlaylistExternalService,
        externalPlaylistID: String
    ) -> URL? {
        let digest = SHA256.hash(data: Data(key(
            username: username,
            service: service,
            externalPlaylistID: externalPlaylistID
        ).utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL?.appending(path: "\(filename).json")
    }

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
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedURL.setResourceValues(values)
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

@MainActor
@Observable
final class PlaylistServiceImportModel {
    let account: Account
    let service: PlaylistExternalService

    private let scope: RequestGate.ReadScope
    private let provider: any PlaylistServiceImportProviding
    private let cache: EntityDetailCache<PlaylistServiceImportCacheKey, PlaylistServiceImportList>
    private let journal: PlaylistServiceImportJournal
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let refreshCooldown: Duration
    @ObservationIgnored private var refreshCooldownTask: Task<Void, Never>?
    private var requestID: UUID?
    private var didLoad = false

    var searchText = ""
    private(set) var phase: PlaylistServiceImportPhase = .idle
    private(set) var refreshMessage: String?
    private(set) var isListing = false
    private(set) var isRefreshCoolingDown = false
    private(set) var isImporting = false
    private(set) var activePlaylistID: String?
    private(set) var notice: PlaylistServiceImportNotice?

    init(
        account: Account,
        service: PlaylistExternalService = .spotify,
        provider: (any PlaylistServiceImportProviding)? = nil,
        cache: EntityDetailCache<PlaylistServiceImportCacheKey, PlaylistServiceImportList> = PlaylistServiceImportCaches.values,
        journal: PlaylistServiceImportJournal = .shared,
        now: @escaping () -> Date = Date.init,
        refreshCooldown: Duration = .seconds(3)
    ) {
        self.account = account
        self.service = service
        scope = .authenticated(token: account.token)
        self.provider = provider ?? ListenBrainzPlaylistServiceImportProvider(token: account.token)
        self.cache = cache
        self.journal = journal
        self.now = now
        self.refreshCooldown = refreshCooldown
    }

    init(
        account: Account,
        service: PlaylistExternalService = .spotify,
        scope: RequestGate.ReadScope = .isolated(),
        provider: some PlaylistServiceImportProviding,
        cache: EntityDetailCache<PlaylistServiceImportCacheKey, PlaylistServiceImportList> = PlaylistServiceImportCaches.values,
        journal: PlaylistServiceImportJournal = .init(),
        now: @escaping () -> Date = Date.init,
        refreshCooldown: Duration = .seconds(3)
    ) {
        self.account = account
        self.service = service
        self.scope = scope
        self.provider = provider
        self.cache = cache
        self.journal = journal
        self.now = now
        self.refreshCooldown = refreshCooldown
    }

    var loadedList: PlaylistServiceImportList? {
        guard case let .loaded(list) = phase else { return nil }
        return list
    }

    var filteredPlaylists: [PlaylistServiceImportItem] {
        loadedList?.playlists.filter { $0.matches(searchText) } ?? []
    }

    func load() async {
        guard requireAuthenticatedAccount(), !didLoad else { return }
        didLoad = true
        await fetch(refreshing: false)
    }

    func refresh() async {
        guard requireAuthenticatedAccount(),
              !isImporting,
              !isListing,
              !isRefreshCoolingDown
        else { return }
        didLoad = true
        await fetch(refreshing: true)
    }

    func cancelListing() {
        requestID = nil
        if phase == .loading {
            phase = .idle
            didLoad = false
        }
    }

    func importPlaylist(_ playlist: PlaylistServiceImportItem) async {
        guard account.isAuthenticated,
              playlist.service == service,
              !isImporting,
              !requiresReview(for: playlist)
        else { return }

        notice = nil
        guard journal.beginAttempt(
            username: account.username,
            service: playlist.service,
            externalPlaylistID: playlist.externalID,
            at: now()
        ) else {
            notice = .failed(id: UUID(), message: safetyStorageMessage)
            return
        }

        isImporting = true
        activePlaylistID = playlist.id
        defer {
            journal.releaseClaim(
                username: account.username,
                service: playlist.service,
                externalPlaylistID: playlist.externalID
            )
            isImporting = false
            activePlaylistID = nil
        }

        do {
            let playlistMBID = try await provider.importPlaylist(playlist)
            notice = .confirmed(
                id: UUID(),
                playlist: playlist,
                playlistMBID: playlistMBID
            )
        } catch let error as PlaylistServiceImportProviderError {
            switch error {
            case .cancelledBeforeTransport:
                if !clearDefiniteAttempt(playlist) {
                    notice = .failed(id: UUID(), message: safetyResetMessage)
                }
            case .invalidPlaylistIdentifier:
                notice = .failed(
                    id: UUID(),
                    message: clearDefiniteAttempt(playlist)
                        ? invalidPlaylistMessage
                        : safetyResetMessage
                )
            case .unsupportedService:
                notice = .failed(
                    id: UUID(),
                    message: clearDefiniteAttempt(playlist)
                        ? unsupportedServiceMessage
                        : safetyResetMessage
                )
            case .indeterminateImport:
                notice = .verificationNeeded(
                    id: UUID(),
                    playlist: playlist,
                    message: verificationMessage(for: playlist)
                )
            }
        } catch {
            notice = .verificationNeeded(
                id: UUID(),
                playlist: playlist,
                message: verificationMessage(for: playlist)
            )
        }
    }

    func requiresReview(for playlist: PlaylistServiceImportItem) -> Bool {
        journal.requiresReview(
            username: account.username,
            service: playlist.service,
            externalPlaylistID: playlist.externalID
        )
    }

    func verificationMessage(for playlist: PlaylistServiceImportItem) -> String {
        if journal.requiresRecovery(
            username: account.username,
            service: playlist.service,
            externalPlaylistID: playlist.externalID
        ) {
            return String(localized: "Brainz can’t read its duplicate-protection check for “\(playlist.title)”. Check Owned Playlists before allowing another import.")
        }
        return String(localized: "“\(playlist.title)” may already be in Owned Playlists. Check there before allowing another import.")
    }

    @discardableResult
    func acknowledgeConfirmedImport(_ playlist: PlaylistServiceImportItem) -> Bool {
        guard case let .confirmed(_, noticePlaylist, _) = notice,
              noticePlaylist.id == playlist.id
        else { return false }
        guard resolve(playlist) else {
            notice = .confirmedRecoveryNeeded(
                id: UUID(),
                playlist: playlist,
                message: confirmedRecoveryMessage
            )
            return false
        }
        notice = nil
        return true
    }

    func clearAfterUserReview(_ playlist: PlaylistServiceImportItem) {
        guard !isImporting else { return }
        guard resolve(playlist) else {
            notice = .failed(id: UUID(), message: safetyResetMessage)
            return
        }
        if case let .verificationNeeded(_, noticePlaylist, _) = notice,
           noticePlaylist.id == playlist.id {
            notice = nil
        }
    }

    func dismissFailureNotice() {
        guard case .failed = notice else { return }
        notice = nil
    }

    func acknowledgeVerificationNotice() {
        guard case .verificationNeeded = notice else { return }
        notice = nil
    }

    func acknowledgeConfirmedRecoveryNotice() {
        guard case .confirmedRecoveryNeeded = notice else { return }
        notice = nil
    }

    private func fetch(refreshing: Bool) async {
        guard !isListing else { return }
        isListing = true
        defer {
            isListing = false
            beginRefreshCooldown()
        }
        let key = PlaylistServiceImportCacheKey(
            username: account.username,
            scope: scope,
            service: service
        )
        var stale: PlaylistServiceImportList?
        if let cached = await cache.value(for: key) {
            phase = .loaded(cached.value)
            stale = cached.value
            if cached.isFresh, !refreshing { return }
        }

        if stale == nil { phase = .loading }
        refreshMessage = nil
        let id = UUID()
        requestID = id
        do {
            let result = try await provider.playlists(from: service)
            try Task.checkCancellation()
            guard requestID == id else { return }
            phase = .loaded(result)
            await cache.save(result, for: key)
        } catch is CancellationError {
            guard requestID == id else { return }
            if stale == nil {
                phase = .idle
                didLoad = false
            }
        } catch {
            guard requestID == id else { return }
            if isAuthenticationError(error) {
                await cache.removeValue(for: key)
                guard requestID == id else { return }
                refreshMessage = nil
                phase = .failed(String(localized: "Your ListenBrainz sign-in needs attention. Sign in again to import playlists."))
            } else if stale != nil {
                refreshMessage = String(localized: "Couldn’t refresh your Spotify playlists. Showing the last saved list.")
            } else {
                phase = .failed(listErrorMessage(error))
            }
        }
    }

    private func requireAuthenticatedAccount() -> Bool {
        guard account.isAuthenticated else {
            refreshMessage = nil
            phase = .failed(String(localized: "Sign in to import playlists from Spotify."))
            return false
        }
        return true
    }

    private func listErrorMessage(_ error: Error) -> String {
        guard let error = error as? LBError else {
            return String(localized: "Couldn’t load your Spotify playlists. Check your connection and try again.")
        }
        switch error {
        case .badRequest, .forbidden:
            return String(localized: "Reconnect Spotify on ListenBrainz, then try again.")
        case .invalidAuth, .noToken:
            return String(localized: "Your ListenBrainz sign-in needs attention. Sign in again to import playlists.")
        case .rateLimited:
            return String(localized: "ListenBrainz is busy. Wait a moment, then try again.")
        case .notFound:
            return String(localized: "Spotify playlist import isn’t available right now. Try again later.")
        default:
            return String(localized: "Couldn’t read your Spotify playlists. Reconnect Spotify or try again later.")
        }
    }

    private func isAuthenticationError(_ error: Error) -> Bool {
        guard let error = error as? LBError else { return false }
        switch error {
        case .invalidAuth, .noToken:
            return true
        default:
            return false
        }
    }

    private func clearDefiniteAttempt(_ playlist: PlaylistServiceImportItem) -> Bool {
        journal.releaseClaim(
            username: account.username,
            service: playlist.service,
            externalPlaylistID: playlist.externalID
        )
        return resolve(playlist)
    }

    private func resolve(_ playlist: PlaylistServiceImportItem) -> Bool {
        journal.resolveAfterReview(
            username: account.username,
            service: playlist.service,
            externalPlaylistID: playlist.externalID
        )
    }

    private func beginRefreshCooldown() {
        refreshCooldownTask?.cancel()
        isRefreshCoolingDown = true
        let duration = refreshCooldown
        refreshCooldownTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.isRefreshCoolingDown = false
        }
    }

    private var safetyStorageMessage: String {
        String(localized: "Brainz couldn’t save its duplicate-protection check, so the import didn’t start.")
    }

    private var safetyResetMessage: String {
        String(localized: "Brainz couldn’t reset duplicate protection. Importing this playlist again is still paused.")
    }

    private var confirmedRecoveryMessage: String {
        String(localized: "The playlist was added, but duplicate protection couldn’t be cleared. Check Owned Playlists before importing it again.")
    }

    private var invalidPlaylistMessage: String {
        String(localized: "This Spotify playlist can’t be imported. Reload your playlists and try again.")
    }

    private var unsupportedServiceMessage: String {
        String(localized: "This music service isn’t available for import yet.")
    }
}
