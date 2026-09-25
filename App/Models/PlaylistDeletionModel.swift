import CryptoKit
import Darwin
import Foundation
import Observation

/// The sole contents of a per-account/per-playlist deletion safety file. It
/// deliberately contains no credential, username, title, tracks, or metadata.
private struct PlaylistDeletionRecord: Codable, Hashable, Sendable {
    let pairDigest: String
}

/// A process-scoped denial prevents a creator-only 403 from becoming a request
/// loop when the detail screen is dismissed and reopened. It stores no token or
/// playlist metadata and deliberately resets only when the app process ends.
@MainActor
final class PlaylistDeletionDenialRegistry {
    static let shared = PlaylistDeletionDenialRegistry()

    private var deniedPairs: Set<String> = []

    func contains(username: String, playlistMBID: UUID) -> Bool {
        deniedPairs.contains(Self.key(username: username, playlistMBID: playlistMBID))
    }

    func deny(username: String, playlistMBID: UUID) {
        deniedPairs.insert(Self.key(username: username, playlistMBID: playlistMBID))
    }

    private static func key(username: String, playlistMBID: UUID) -> String {
        let normalizedUsername = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return PlaylistDeletionJournal.hash(
            "\(normalizedUsername)\u{0}\(playlistMBID.uuidString.lowercased())"
        )
    }
}

/// A token-free durable barrier written before the destructive POST. A bad
/// file blocks only its account/playlist pair and can be reset only after a
/// fresh canonical inspection.
@MainActor @Observable
final class PlaylistDeletionJournal {
    static let shared: PlaylistDeletionJournal = {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return .init(storageUnavailable: true)
        }
        return .init(
            directoryURL: root.appending(
                path: "Brainz/playlist-deletions-v1",
                directoryHint: .isDirectory
            )
        )
    }()

    @ObservationIgnored private let directoryURL: URL?
    @ObservationIgnored private let storageUnavailable: Bool
    private var loadedKeys: Set<String> = []
    private var unreadableKeys: Set<String> = []
    private var records: [String: PlaylistDeletionRecord] = [:]
    private var activeReservations: Set<String> = []

    /// A nil directory is intentionally in-memory for deterministic tests and
    /// local fixtures. Production uses ``shared`` and fails closed when its
    /// Application Support location is unavailable.
    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL
        storageUnavailable = false
    }

    private init(storageUnavailable: Bool) {
        directoryURL = nil
        self.storageUnavailable = storageUnavailable
    }

    func requiresRecovery(username: String, playlistMBID: UUID) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        return storageUnavailable || unreadableKeys.contains(key)
    }

    func requiresReview(username: String, playlistMBID: UUID) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        return storageUnavailable
            || unreadableKeys.contains(key)
            || records[key] != nil
    }

    /// Reserves this exact account/playlist pair only after its barrier is
    /// durable. Two model instances sharing the journal cannot both dispatch.
    func begin(
        username: String,
        playlistMBID: UUID
    ) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        guard !storageUnavailable,
              !unreadableKeys.contains(key),
              records[key] == nil,
              !activeReservations.contains(key)
        else { return false }

        let record = PlaylistDeletionRecord(
            pairDigest: key
        )
        guard persist(record) else {
            unreadableKeys.insert(key)
            return false
        }
        records[key] = record
        activeReservations.insert(key)
        return true
    }

    /// Clears a resolved barrier. A failed durable clear remains blocked.
    func resolveAfterInspection(
        username: String,
        playlistMBID: UUID
    ) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        guard !storageUnavailable, !unreadableKeys.contains(key) else {
            return false
        }
        guard removePair(username: username, playlistMBID: playlistMBID) else {
            unreadableKeys.insert(key)
            return false
        }
        records.removeValue(forKey: key)
        activeReservations.remove(key)
        loadedKeys.insert(key)
        return true
    }

    func cancelBeforeDispatch(username: String, playlistMBID: UUID) -> Bool {
        resolveAfterInspection(username: username, playlistMBID: playlistMBID)
    }

    /// Explicit recovery is pair-scoped and is exposed only after the model
    /// has completed a fresh canonical inspection.
    func resetRecovery(username: String, playlistMBID: UUID) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        guard unreadableKeys.contains(key),
              !storageUnavailable,
              let fileURL = pairURL(
                  username: username,
                  playlistMBID: playlistMBID
              )
        else { return false }

        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: fileURL.path()) {
                try manager.removeItem(at: fileURL)
                try Self.syncDirectory(fileURL.deletingLastPathComponent())
            }
            guard !manager.fileExists(atPath: fileURL.path()) else {
                return false
            }
            unreadableKeys.remove(key)
            records.removeValue(forKey: key)
            activeReservations.remove(key)
            loadedKeys.insert(key)
            return true
        } catch {
            return false
        }
    }

    private func loadIfNeeded(username: String, playlistMBID: UUID) {
        let key = recordKey(username, playlistMBID)
        guard !loadedKeys.contains(key) else { return }
        loadedKeys.insert(key)
        guard !storageUnavailable,
              let fileURL = pairURL(
                  username: username,
                  playlistMBID: playlistMBID
              ),
              FileManager.default.fileExists(atPath: fileURL.path())
        else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let record = try JSONDecoder().decode(
                PlaylistDeletionRecord.self,
                from: data
            )
            guard record.pairDigest == key else {
                throw CocoaError(.fileReadCorruptFile)
            }
            records[key] = record
        } catch {
            unreadableKeys.insert(key)
        }
    }

    private func persist(_ record: PlaylistDeletionRecord) -> Bool {
        guard let fileURL = directoryURL?.appending(
            path: "\(record.pairDigest).json"
        ) else {
            return directoryURL == nil && !storageUnavailable
        }
        do {
            try Self.writeDurably(JSONEncoder().encode(record), to: fileURL)
            return true
        } catch {
            return false
        }
    }

    private func removePair(username: String, playlistMBID: UUID) -> Bool {
        guard let fileURL = pairURL(
            username: username,
            playlistMBID: playlistMBID
        ) else {
            return directoryURL == nil && !storageUnavailable
        }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: fileURL.path()) {
                try manager.removeItem(at: fileURL)
                try Self.syncDirectory(fileURL.deletingLastPathComponent())
            }
            return !manager.fileExists(atPath: fileURL.path())
        } catch {
            return false
        }
    }

    private func pairURL(username: String, playlistMBID: UUID) -> URL? {
        directoryURL?.appending(path: "\(recordKey(username, playlistMBID)).json")
    }

    private func recordKey(_ username: String, _ playlistMBID: UUID) -> String {
        Self.hash("\(normalized(username))\u{0}\(playlistMBID.uuidString.lowercased())")
    }

    private func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    fileprivate static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func writeDurably(_ data: Data, to fileURL: URL) throws {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try ensureDirectoryDurably(directory)
        try manager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path()
        )
        try excludeFromBackup(directory)

        let temporary = directory.appending(
            path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporary, options: .atomic)
            try manager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporary.path()
            )
            #if os(iOS)
                try manager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: temporary.path()
                )
            #endif
            try excludeFromBackup(temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            let renameResult = temporary.path.withCString { source in
                fileURL.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }
            guard renameResult == 0 else {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errno)
                )
            }
            #if os(iOS)
                try manager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: fileURL.path()
                )
            #endif
            try manager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path()
            )
            try excludeFromBackup(fileURL)
            let finalHandle = try FileHandle(forWritingTo: fileURL)
            do {
                try finalHandle.synchronize()
                try finalHandle.close()
            } catch {
                try? finalHandle.close()
                throw error
            }
            try syncDirectory(directory)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    private static func ensureDirectoryDurably(_ directory: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: directory.path(), isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }

        let parent = directory.deletingLastPathComponent()
        guard parent.path() != directory.path() else {
            throw CocoaError(.fileNoSuchFile)
        }
        try ensureDirectoryDurably(parent)
        do {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            var racedDirectory: ObjCBool = false
            guard manager.fileExists(
                atPath: directory.path(),
                isDirectory: &racedDirectory
            ), racedDirectory.boolValue else { throw error }
        }
        try syncDirectory(parent)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }

    private static func syncDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString {
            Darwin.open($0, O_RDONLY)
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

enum PlaylistDeletionConfirmation: Equatable, Sendable {
    case deleted(title: String)
    case noLongerAvailable
}

enum PlaylistDeletionNotice: Identifiable, Equatable, Sendable {
    case confirmed(PlaylistDeletionConfirmation)
    case needsReview(String)
    case failed(String)

    var id: String {
        switch self {
        case let .confirmed(outcome):
            "confirmed:\(String(describing: outcome))"
        case let .needsReview(message):
            "review:\(message)"
        case let .failed(message):
            "failed:\(message)"
        }
    }
}

@MainActor @Observable
final class PlaylistDeletionModel {
    private enum ReviewedOutcome {
        case exists(title: String)
        case unavailable
    }

    private let account: Account
    private let detailProvider: any PlaylistDetailProviding
    private let provider: any PlaylistDeletionProviding
    private let journal: PlaylistDeletionJournal
    private let mutationJournal: PlaylistMutationJournal
    private let denialRegistry: PlaylistDeletionDenialRegistry
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>
    private let profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>

    private(set) var isDeleting = false
    private(set) var isChecking = false
    private(set) var notice: PlaylistDeletionNotice?
    private(set) var accessLossReason: PlaylistAccessLossReason?
    private(set) var accessLossMessage: String?

    private var reviewedPairs: Set<UUID> = []
    private var reviewedOutcomes: [UUID: ReviewedOutcome] = [:]

    init(
        account: Account,
        detailProvider: any PlaylistDetailProviding,
        provider: any PlaylistDeletionProviding,
        journal: PlaylistDeletionJournal = .shared,
        mutationJournal: PlaylistMutationJournal = .shared,
        denialRegistry: PlaylistDeletionDenialRegistry = .shared,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        self.account = account
        self.detailProvider = detailProvider
        self.provider = provider
        self.journal = journal
        self.mutationJournal = mutationJournal
        self.denialRegistry = denialRegistry
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    static func canDelete(account: Account, detail: PlaylistDetail?) -> Bool {
        guard account.isAuthenticated, let detail else { return false }
        return normalized(detail.creator) == normalized(account.username)
    }

    func requiresReview(playlistMBID: UUID) -> Bool {
        journal.requiresReview(
            username: account.username,
            playlistMBID: playlistMBID
        )
    }

    func requiresRecovery(playlistMBID: UUID) -> Bool {
        journal.requiresRecovery(
            username: account.username,
            playlistMBID: playlistMBID
        )
    }

    func canAttemptDelete(_ detail: PlaylistDetail?) -> Bool {
        guard let detail,
              !denialRegistry.contains(
                  username: account.username,
                  playlistMBID: detail.mbid
              ),
              !requiresReview(playlistMBID: detail.mbid)
        else { return false }
        return Self.canDelete(account: account, detail: detail)
    }

    func canResetSafetyRecord(playlistMBID: UUID) -> Bool {
        reviewedPairs.contains(playlistMBID)
            && requiresRecovery(playlistMBID: playlistMBID)
    }

    func dismissNotice() {
        notice = nil
    }

    @discardableResult
    func resetSafetyRecord(playlistMBID: UUID) async -> Bool {
        guard canResetSafetyRecord(playlistMBID: playlistMBID) else {
            notice = .needsReview(
                String(localized: "Brainz couldn’t reset this playlist’s deletion safety record. Try again after checking the playlist.")
            )
            return false
        }

        let outcome = reviewedOutcomes[playlistMBID]
        if case .unavailable = outcome {
            await evictConfirmedDeletionCaches()
        }

        guard journal.resetRecovery(
                  username: account.username,
                  playlistMBID: playlistMBID
              )
        else {
            notice = .needsReview(
                String(localized: "Brainz couldn’t reset this playlist’s deletion safety record. Try again after checking the playlist.")
            )
            return false
        }

        reviewedOutcomes.removeValue(forKey: playlistMBID)
        reviewedPairs.remove(playlistMBID)
        switch outcome {
        case .unavailable:
            publishConfirmedDeletion(
                playlistMBID: playlistMBID,
                outcome: .noLongerAvailable
            )
        case let .exists(title):
            notice = .failed(
                String(localized: "“\(title)” still exists. You can delete it again when you’re ready.")
            )
        case nil:
            notice = .failed(
                String(localized: "The safety record was reset. Check the playlist again before deleting it.")
            )
        }
        return true
    }

    /// Performs one fresh, non-coalesced owner preflight and at most one
    /// serialized deletion POST. It never replays an ambiguous attempt.
    @discardableResult
    func delete(_ seed: PlaylistDetail) async -> Bool {
        guard !isDeleting,
              !isChecking,
              canAttemptDelete(seed)
        else { return false }

        isDeleting = true
        accessLossReason = nil
        accessLossMessage = nil
        notice = nil
        defer { isDeleting = false }

        do {
            try Task.checkCancellation()
        } catch {
            return false
        }

        let canonical: PlaylistDetail
        do {
            canonical = try await detailProvider.playlistForMutationInspection(
                mbid: seed.mbid
            )
            guard canonical.mbid == seed.mbid else {
                notice = .failed(
                    String(localized: "ListenBrainz returned a different playlist. Reload this page before deleting.")
                )
                return false
            }
            guard Self.canDelete(account: account, detail: canonical) else {
                denialRegistry.deny(
                    username: account.username,
                    playlistMBID: seed.mbid
                )
                notice = .failed(
                    PlaylistMutationProviderError.deleteNotOwner.localizedDescription
                )
                return false
            }
        } catch {
            await captureAccessLossIfNeeded(error, playlistMBID: seed.mbid)
            notice = .failed(error.localizedDescription)
            return false
        }

        guard journal.begin(
            username: account.username,
            playlistMBID: seed.mbid
        ) else {
            notice = .needsReview(
                requiresRecovery(playlistMBID: seed.mbid)
                    ? String(localized: "Brainz can’t read this playlist’s deletion safety record. Check the playlist before resetting the record.")
                    : String(localized: "A previous deletion still needs review. Check whether this playlist exists before deleting it again.")
            )
            return false
        }

        do {
            try Task.checkCancellation()
        } catch {
            guard clearReservation(playlistMBID: seed.mbid) else {
                notice = .needsReview(
                    String(localized: "Deletion was canceled, but its safety record couldn’t be cleared. Check the playlist before deleting it again.")
                )
                return false
            }
            return false
        }

        do {
            try await provider.delete(mbid: seed.mbid)
        } catch is CancellationError {
            // An abstract provider can only prove pre-admission cancellation by
            // returning before this call. A cancellation thrown from inside it
            // may follow dispatch, so preserve the durable barrier.
            notice = .needsReview(
                String(localized: "Deletion was canceled after it was prepared. Check whether this playlist still exists before deleting it again.")
            )
            return false
        } catch PlaylistMutationProviderError.indeterminateDeletion {
            notice = .needsReview(
                PlaylistMutationProviderError.indeterminateDeletion.localizedDescription
            )
            return false
        } catch PlaylistMutationProviderError.playlistUnavailable {
            await evictConfirmedDeletionCaches()
            guard clearReservation(playlistMBID: seed.mbid) else {
                notice = .needsReview(
                    String(localized: "The playlist is no longer available, but its safety record couldn’t be cleared. Check again before continuing.")
                )
                return false
            }
            publishConfirmedDeletion(
                playlistMBID: seed.mbid,
                outcome: .noLongerAvailable
            )
            return true
        } catch PlaylistMutationProviderError.deleteNotOwner {
            denialRegistry.deny(
                username: account.username,
                playlistMBID: seed.mbid
            )
            guard clearReservation(playlistMBID: seed.mbid) else {
                notice = .needsReview(
                    String(localized: "ListenBrainz rejected the deletion, but its safety record couldn’t be cleared. Check this playlist before continuing.")
                )
                return false
            }
            notice = .failed(
                PlaylistMutationProviderError.deleteNotOwner.localizedDescription
            )
            return false
        } catch {
            let isAccessLoss = PlaylistAccessFailurePolicy.reason(for: error) != nil
            guard clearReservation(playlistMBID: seed.mbid) else {
                notice = .needsReview(
                    String(localized: "ListenBrainz rejected the deletion, but its safety record couldn’t be cleared. Check this playlist before continuing.")
                )
                return false
            }
            if isAccessLoss {
                await captureAccessLossIfNeeded(error, playlistMBID: seed.mbid)
            }
            notice = .failed(error.localizedDescription)
            return false
        }

        await evictConfirmedDeletionCaches()
        guard clearReservation(playlistMBID: seed.mbid) else {
            notice = .needsReview(
                String(localized: "The playlist was deleted, but its safety record couldn’t be cleared. Check again before continuing.")
            )
            return false
        }
        publishConfirmedDeletion(
            playlistMBID: seed.mbid,
            outcome: .deleted(title: canonical.title)
        )
        return true
    }

    /// Performs one explicit non-coalesced recovery read. An exact owner-owned
    /// playlist proves the POST did not leave it absent; current unavailability
    /// reaches the desired end state without claiming this client deleted it.
    @discardableResult
    func checkAgain(playlistMBID: UUID) async -> Bool {
        guard !isDeleting,
              !isChecking,
              requiresReview(playlistMBID: playlistMBID)
        else { return false }

        isChecking = true
        accessLossReason = nil
        accessLossMessage = nil
        notice = nil
        defer { isChecking = false }

        do {
            let detail = try await detailProvider.playlistForMutationInspection(
                mbid: playlistMBID
            )
            guard detail.mbid == playlistMBID,
                  Self.canDelete(account: account, detail: detail)
            else {
                notice = .needsReview(
                    String(localized: "This playlist no longer matches the account that started deletion. Its status still needs review.")
                )
                return false
            }

            reviewedPairs.insert(playlistMBID)
            reviewedOutcomes[playlistMBID] = .exists(title: detail.title)
            guard journal.resolveAfterInspection(
                username: account.username,
                playlistMBID: playlistMBID
            ) else {
                notice = .needsReview(
                    String(localized: "The playlist still exists, but its safety record couldn’t be cleared. Reset the record only after reviewing this result.")
                )
                return false
            }
            reviewedPairs.remove(playlistMBID)
            reviewedOutcomes.removeValue(forKey: playlistMBID)
            notice = .failed(
                String(localized: "“\(detail.title)” still exists. You can delete it again when you’re ready.")
            )
            return false
        } catch {
            if PlaylistAccessFailurePolicy.reason(for: error) == .sourceVisibility {
                reviewedPairs.insert(playlistMBID)
                reviewedOutcomes[playlistMBID] = .unavailable
                await evictConfirmedDeletionCaches()
                guard journal.resolveAfterInspection(
                    username: account.username,
                    playlistMBID: playlistMBID
                ) else {
                    notice = .needsReview(
                        String(localized: "The playlist is no longer available, but its safety record couldn’t be cleared. Reset the record only after reviewing this result.")
                    )
                    return false
                }
                reviewedPairs.remove(playlistMBID)
                reviewedOutcomes.removeValue(forKey: playlistMBID)
                publishConfirmedDeletion(
                    playlistMBID: playlistMBID,
                    outcome: .noLongerAvailable
                )
                return true
            }

            await captureAccessLossIfNeeded(error, playlistMBID: playlistMBID)
            notice = .needsReview(
                String(localized: "Brainz couldn’t check this playlist. Check again before deleting it.")
            )
            return false
        }
    }

    private func clearReservation(playlistMBID: UUID) -> Bool {
        journal.resolveAfterInspection(
            username: account.username,
            playlistMBID: playlistMBID
        )
    }

    private func evictConfirmedDeletionCaches() async {
        await detailCache.removeAll()
        await profilePageCache.removeAll()
    }

    private func publishConfirmedDeletion(
        playlistMBID: UUID,
        outcome: PlaylistDeletionConfirmation
    ) {
        mutationJournal.recordConfirmedDeletion(
            mbid: playlistMBID,
            ownerUsername: account.username
        )
        notice = .confirmed(outcome)
    }

    private func captureAccessLossIfNeeded(
        _ error: any Error,
        playlistMBID: UUID
    ) async {
        guard let reason = PlaylistAccessFailurePolicy.reason(for: error) else {
            return
        }
        let message = error.localizedDescription
        accessLossReason = reason
        accessLossMessage = message
        await mutationJournal.recordAccessLoss(
            sourceMBID: playlistMBID,
            viewerUsername: account.username,
            reason: reason,
            message: message
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
