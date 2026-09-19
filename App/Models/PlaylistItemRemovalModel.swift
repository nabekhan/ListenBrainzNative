import CryptoKit
import Darwin
import Foundation
import Observation

/// The sole contents of a per-account/per-playlist safety file. It deliberately
/// contains no credential, track, title, or other listening metadata.
private struct PlaylistItemRemovalRecord: Codable, Hashable, Sendable {
    let playlistMBID: UUID
    let attemptedAt: Date
}

/// Token-free, per-pair durable barrier for a positional, non-idempotent
/// removal. A bad file for one account/playlist never affects another pair.
@MainActor @Observable
final class PlaylistItemRemovalJournal {
    static let shared: PlaylistItemRemovalJournal = {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return .init(storageUnavailable: true)
        }
        return .init(
            directoryURL: root.appending(path: "Brainz/playlist-item-removals-v1", directoryHint: .isDirectory))
    }()
    @ObservationIgnored private let directoryURL: URL?
    @ObservationIgnored private let storageUnavailable: Bool
    private var loadedKeys: Set<String> = []
    private var unreadableKeys: Set<String> = []
    private var records: [String: PlaylistItemRemovalRecord] = [:]
    private var activeReservations: Set<String> = []

    /// A nil directory is intentionally in-memory for deterministic unit tests.
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
        return storageUnavailable || unreadableKeys.contains(key) || records[key] != nil
    }

    /// Reserves this pair only after its unresolved barrier is durably stored.
    func begin(username: String, playlistMBID: UUID, at: Date = .now) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        guard !storageUnavailable, !unreadableKeys.contains(key), records[key] == nil, !activeReservations.contains(key)
        else { return false }
        let record = PlaylistItemRemovalRecord(playlistMBID: playlistMBID, attemptedAt: at)
        guard persist(record, username: username) else {
            unreadableKeys.insert(key)
            return false
        }
        records[key] = record
        activeReservations.insert(key)
        return true
    }

    /// Clears a resolved barrier. A failed durable clear stays blocked.
    func resolveAfterInspection(username: String, playlistMBID: UUID) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        guard !storageUnavailable, !unreadableKeys.contains(key) else { return false }
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

    /// Explicit recovery is pair-scoped and must follow a fresh inspection.
    func resetRecovery(username: String, playlistMBID: UUID) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        guard unreadableKeys.contains(key), !storageUnavailable,
            let fileURL = pairURL(username: username, playlistMBID: playlistMBID)
        else { return false }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: fileURL.path()) {
                try manager.removeItem(at: fileURL)
                try Self.syncDirectory(fileURL.deletingLastPathComponent())
            }
            guard !manager.fileExists(atPath: fileURL.path()) else { return false }
            unreadableKeys.remove(key)
            records.removeValue(forKey: key)
            activeReservations.remove(key)
            loadedKeys.insert(key)
            return true
        } catch { return false }
    }

    private func loadIfNeeded(username: String, playlistMBID: UUID) {
        let key = recordKey(username, playlistMBID)
        guard !loadedKeys.contains(key) else { return }
        loadedKeys.insert(key)
        guard !storageUnavailable, let fileURL = pairURL(username: username, playlistMBID: playlistMBID),
            FileManager.default.fileExists(atPath: fileURL.path())
        else { return }
        do {
            let record = try JSONDecoder().decode(PlaylistItemRemovalRecord.self, from: Data(contentsOf: fileURL))
            guard record.playlistMBID == playlistMBID else { throw CocoaError(.fileReadCorruptFile) }
            records[key] = record
        } catch { unreadableKeys.insert(key) }
    }
    private func persist(_ record: PlaylistItemRemovalRecord, username: String) -> Bool {
        guard let url = pairURL(username: username, playlistMBID: record.playlistMBID) else {
            return directoryURL == nil && !storageUnavailable
        }
        do {
            try Self.writeDurably(JSONEncoder().encode(record), to: url)
            return true
        } catch { return false }
    }
    private func removePair(username: String, playlistMBID: UUID) -> Bool {
        guard let url = pairURL(username: username, playlistMBID: playlistMBID) else {
            return directoryURL == nil && !storageUnavailable
        }
        do {
            if FileManager.default.fileExists(atPath: url.path()) {
                try FileManager.default.removeItem(at: url)
                try Self.syncDirectory(url.deletingLastPathComponent())
            }
            return !FileManager.default.fileExists(atPath: url.path())
        } catch { return false }
    }
    private func pairURL(username: String, playlistMBID: UUID) -> URL? {
        directoryURL?.appending(path: "\(Self.hash(normalized(username))).\(playlistMBID.uuidString.lowercased()).json")
    }
    private func recordKey(_ username: String, _ playlistMBID: UUID) -> String {
        "\(Self.hash(normalized(username))):\(playlistMBID.uuidString.lowercased())"
    }
    private func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private static func hash(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func writeDurably(_ data: Data, to fileURL: URL) throws {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let existed = manager.fileExists(atPath: directory.path())
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !existed { try syncDirectory(directory.deletingLastPathComponent()) }
        let temporary = directory.appending(path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            #if os(iOS)
                try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path())
            #endif
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            guard temporary.path.withCString({ source in fileURL.path.withCString { Darwin.rename(source, $0) } }) == 0
            else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            #if os(iOS)
                try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path())
            #endif
            try syncDirectory(directory)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }
    private static func syncDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString { Darwin.open($0, O_RDONLY) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
}

enum PlaylistItemRemovalNotice: Identifiable, Equatable {
    case stale
    case confirmed(track: String, playlist: String)
    case needsReview(String)
    case refreshed
    case failed(String)
    case accessLost(String)
    var id: String {
        switch self {
        case .stale: "stale"
        case .confirmed: "confirmed"
        case .needsReview(let message): "review:\(message)"
        case .refreshed: "refreshed"
        case .failed(let message): "failed:\(message)"
        case .accessLost(let message): "access:\(message)"
        }
    }
}

@MainActor @Observable
final class PlaylistItemRemovalModel {
    private let account: Account
    private let detailProvider: any PlaylistDetailProviding
    private let provider: any PlaylistItemRemovalProviding
    private let journal: PlaylistItemRemovalJournal
    private let mutationJournal: PlaylistMutationJournal
    private(set) var isRemoving = false
    private(set) var isReconciling = false
    private(set) var notice: PlaylistItemRemovalNotice?
    private var reviewedPairs: Set<UUID> = []
    private var mutationDeniedPairs: Set<UUID> = []
    init(
        account: Account,
        detailProvider: any PlaylistDetailProviding,
        provider: any PlaylistItemRemovalProviding,
        journal: PlaylistItemRemovalJournal = .shared,
        mutationJournal: PlaylistMutationJournal = .shared
    ) {
        self.account = account
        self.detailProvider = detailProvider
        self.provider = provider
        self.journal = journal
        self.mutationJournal = mutationJournal
    }
    func requiresReview(playlistMBID: UUID) -> Bool {
        journal.requiresReview(username: account.username, playlistMBID: playlistMBID)
    }
    func requiresRecovery(playlistMBID: UUID) -> Bool {
        journal.requiresRecovery(username: account.username, playlistMBID: playlistMBID)
    }
    func dismissNotice() { notice = nil }
    func canResetSafetyRecord(playlistMBID: UUID) -> Bool {
        reviewedPairs.contains(playlistMBID) && requiresRecovery(playlistMBID: playlistMBID)
    }
    func resetSafetyRecord(playlistMBID: UUID) -> Bool {
        guard canResetSafetyRecord(playlistMBID: playlistMBID) else { return false }
        guard journal.resetRecovery(username: account.username, playlistMBID: playlistMBID) else {
            notice = .needsReview(
                "Brainz couldn’t reset this playlist’s removal safety record. Try again before removing another track.")
            return false
        }
        reviewedPairs.remove(playlistMBID)
        return true
    }
    static func canRemove(account: Account, detail: PlaylistDetail?) -> Bool {
        guard account.isAuthenticated, let detail else { return false }
        let viewer = account.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.creator.caseInsensitiveCompare(viewer) == .orderedSame
            || detail.collaborators.contains { $0.caseInsensitiveCompare(viewer) == .orderedSame }
    }
    func canAttemptRemoval(from detail: PlaylistDetail?) -> Bool {
        guard let detail, !mutationDeniedPairs.contains(detail.mbid) else { return false }
        return Self.canRemove(account: account, detail: detail)
    }
    func remove(_ selected: PlaylistTrack, from seed: PlaylistDetail) async -> PlaylistDetail? {
        guard !isRemoving, !isReconciling, !requiresReview(playlistMBID: seed.mbid) else { return nil }
        isRemoving = true
        defer { isRemoving = false }
        do {
            let latest = try await detailProvider.playlistForMutationInspection(mbid: seed.mbid)
            guard Self.canRemove(account: account, detail: latest) else {
                mutationDeniedPairs.insert(seed.mbid)
                notice = .failed(PlaylistMutationProviderError.notCollaborator.localizedDescription)
                return latest
            }
            guard let current = latest.tracks.first(where: { $0.position == selected.position }), current == selected
            else {
                notice = .stale
                return latest
            }
            guard journal.begin(username: account.username, playlistMBID: seed.mbid) else {
                notice = .needsReview(
                    "Removal is paused because its safety record can’t be read. Reset the record only after reviewing this playlist on ListenBrainz."
                )
                return latest
            }
            do {
                try Task.checkCancellation()
                try await provider.removeItem(at: selected.position - 1, from: seed.mbid)
            } catch is CancellationError {
                if !journal.cancelBeforeDispatch(username: account.username, playlistMBID: seed.mbid) {
                    notice = .needsReview(
                        "Removal was canceled, but its safety record could not be cleared. Refresh and review the playlist before removing another track."
                    )
                }
                return nil
            } catch PlaylistMutationProviderError.notCollaborator {
                mutationDeniedPairs.insert(seed.mbid)
                return await reconcileAfterMutationPermissionDenied(latest, playlistMBID: seed.mbid)
            } catch let error as PlaylistMutationProviderError where PlaylistAccessFailurePolicy.requiresPurge(error) {
                _ = journal.cancelBeforeDispatch(username: account.username, playlistMBID: seed.mbid)
                return await recordAccessLoss(error, playlistMBID: seed.mbid)
            } catch let error as PlaylistMutationProviderError where !error.isIndeterminate {
                _ = journal.cancelBeforeDispatch(username: account.username, playlistMBID: seed.mbid)
                notice = .failed(error.localizedDescription)
                return nil
            } catch {
                notice = .needsReview(
                    "ListenBrainz may have removed a track, but the response was lost. Refresh the playlist before removing another track."
                )
                return latest
            }
            isReconciling = true
            defer { isReconciling = false }
            do {
                let canonical = try await detailProvider.playlistForMutationInspection(mbid: seed.mbid)
                guard Self.isExactRemoval(of: selected, from: latest, canonical: canonical) else {
                    notice = .needsReview(
                        "The playlist changed while the track was being removed. Review the current order before removing another track."
                    )
                    return canonical
                }
                guard journal.resolveAfterInspection(username: account.username, playlistMBID: seed.mbid) else {
                    notice = .needsReview(
                        "The track was removed, but its safety record could not be cleared. Refresh and review the playlist before removing another track."
                    )
                    return canonical
                }
                notice = .confirmed(track: selected.recording.title, playlist: canonical.title)
                return canonical
            } catch {
                if PlaylistAccessFailurePolicy.requiresPurge(error) {
                    return await recordAccessLoss(error, playlistMBID: seed.mbid)
                }
                notice = .needsReview(
                    "The playlist could not be refreshed after removal. Refresh and review the playlist before removing another track."
                )
                return nil
            }
        } catch {
            if PlaylistAccessFailurePolicy.requiresPurge(error) {
                return await recordAccessLoss(error, playlistMBID: seed.mbid)
            }
            notice = .failed(error.localizedDescription)
            return nil
        }
    }
    func refreshAfterReview(playlistMBID: UUID) async -> PlaylistDetail? {
        isReconciling = true
        defer { isReconciling = false }
        do {
            let detail = try await detailProvider.playlistForMutationInspection(mbid: playlistMBID)
            reviewedPairs.insert(playlistMBID)
            if !journal.requiresRecovery(username: account.username, playlistMBID: playlistMBID),
                !journal.resolveAfterInspection(username: account.username, playlistMBID: playlistMBID)
            {
                notice = .needsReview(
                    "The playlist was refreshed, but its safety record could not be cleared. Reset the record before removing another track."
                )
                return detail
            }
            notice = .refreshed
            return detail
        } catch {
            if PlaylistAccessFailurePolicy.requiresPurge(error) {
                return await recordAccessLoss(error, playlistMBID: playlistMBID)
            }
            notice = .needsReview("The playlist could not be refreshed. Try again before removing another track.")
            return nil
        }
    }
    private func recordAccessLoss(
        _ error: any Error,
        playlistMBID: UUID
    ) async -> PlaylistDetail? {
        guard let reason = PlaylistAccessFailurePolicy.reason(for: error) else {
            notice = .failed(error.localizedDescription)
            return nil
        }
        let message = error.localizedDescription
        await mutationJournal.recordAccessLoss(
            sourceMBID: playlistMBID,
            viewerUsername: account.username,
            reason: reason,
            message: message
        )
        notice = .accessLost(message)
        return nil
    }
    private func reconcileAfterMutationPermissionDenied(
        _ latest: PlaylistDetail,
        playlistMBID: UUID
    ) async -> PlaylistDetail? {
        isReconciling = true
        defer { isReconciling = false }
        do {
            let canonical = try await detailProvider.playlistForMutationInspection(mbid: playlistMBID)
            guard journal.cancelBeforeDispatch(username: account.username, playlistMBID: playlistMBID) else {
                notice = .needsReview(
                    "ListenBrainz rejected the removal, but its safety record could not be cleared. Refresh and review the playlist before removing another track."
                )
                return canonical
            }
            notice = .failed(PlaylistMutationProviderError.notCollaborator.localizedDescription)
            return canonical
        } catch {
            if PlaylistAccessFailurePolicy.requiresPurge(error) {
                _ = journal.cancelBeforeDispatch(username: account.username, playlistMBID: playlistMBID)
                return await recordAccessLoss(error, playlistMBID: playlistMBID)
            }
            notice = .needsReview(
                "ListenBrainz rejected the removal, but Brainz couldn’t refresh the playlist. Refresh it before trying again."
            )
            return latest
        }
    }
    private static func isExactRemoval(
        of selected: PlaylistTrack, from preflight: PlaylistDetail, canonical: PlaylistDetail
    ) -> Bool {
        guard canonical.mbid == preflight.mbid, let index = preflight.tracks.firstIndex(of: selected) else {
            return false
        }
        var expected = preflight.tracks
        expected.remove(at: index)
        guard canonical.tracks.count == expected.count else { return false }
        return zip(expected.indices, canonical.tracks).allSatisfy { index, actual in
            let expectedTrack = expected[index]
            return actual.position == index + 1 && actual.recording == expectedTrack.recording
                && actual.addedAt == expectedTrack.addedAt && actual.addedBy == expectedTrack.addedBy
        }
    }
}
