import CryptoKit
import Darwin
import Foundation
import Observation

/// The sole contents of a per-account/per-playlist safety file. It deliberately
/// contains no credential, track, title, or other listening metadata.
private struct PlaylistItemMutationRecord: Codable, Hashable, Sendable {
    let version: Int
    let digest: String
}

private struct LegacyPlaylistItemRemovalRecord: Codable, Hashable, Sendable {
    let playlistMBID: UUID
    let attemptedAt: Date
}

/// Token-free, per-pair durable barrier for positional, non-idempotent track
/// changes. A bad file for one account/playlist never affects another pair.
@MainActor @Observable
final class PlaylistItemMutationJournal {
    static let shared: PlaylistItemMutationJournal = {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return .init(storageUnavailable: true)
        }
        return .init(
            directoryURL: root.appending(path: "Brainz/playlist-item-mutations-v2", directoryHint: .isDirectory))
    }()
    @ObservationIgnored private let directoryURL: URL?
    @ObservationIgnored private let storageUnavailable: Bool
    private var loadedKeys: Set<String> = []
    private var unreadableKeys: Set<String> = []
    private var records: [String: PlaylistItemMutationRecord] = [:]
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
    func begin(username: String, playlistMBID: UUID) -> Bool {
        let key = recordKey(username, playlistMBID)
        loadIfNeeded(username: username, playlistMBID: playlistMBID)
        guard !storageUnavailable, !unreadableKeys.contains(key), records[key] == nil, !activeReservations.contains(key)
        else { return false }
        let record = PlaylistItemMutationRecord(version: 2, digest: digest(username, playlistMBID))
        guard persist(record, username: username, playlistMBID: playlistMBID) else {
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
        guard unreadableKeys.contains(key), !storageUnavailable else { return false }
        guard removePair(username: username, playlistMBID: playlistMBID) else { return false }
        unreadableKeys.remove(key)
        records.removeValue(forKey: key)
        activeReservations.remove(key)
        loadedKeys.insert(key)
        return true
    }

    private func loadIfNeeded(username: String, playlistMBID: UUID) {
        let key = recordKey(username, playlistMBID)
        guard !loadedKeys.contains(key) else { return }
        loadedKeys.insert(key)
        guard !storageUnavailable, let fileURL = pairURL(username: username, playlistMBID: playlistMBID) else { return }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: fileURL.path()) {
                let record = try JSONDecoder().decode(PlaylistItemMutationRecord.self, from: Data(contentsOf: fileURL))
                guard record.version == 2, record.digest == digest(username, playlistMBID) else { throw CocoaError(.fileReadCorruptFile) }
                records[key] = record
            } else if let legacyURL = legacyPairURL(username: username, playlistMBID: playlistMBID), manager.fileExists(atPath: legacyURL.path()) {
                let legacy = try JSONDecoder().decode(LegacyPlaylistItemRemovalRecord.self, from: Data(contentsOf: legacyURL))
                guard legacy.playlistMBID == playlistMBID else { throw CocoaError(.fileReadCorruptFile) }
                records[key] = .init(version: 2, digest: digest(username, playlistMBID))
            }
        } catch { unreadableKeys.insert(key) }
    }
    private func persist(_ record: PlaylistItemMutationRecord, username: String, playlistMBID: UUID) -> Bool {
        guard let url = pairURL(username: username, playlistMBID: playlistMBID) else {
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
            let manager = FileManager.default
            for candidate in [url, legacyPairURL(username: username, playlistMBID: playlistMBID)].compactMap({ $0 }) where manager.fileExists(atPath: candidate.path()) {
                try manager.removeItem(at: candidate)
                try Self.syncDirectory(candidate.deletingLastPathComponent())
            }
            return !manager.fileExists(atPath: url.path())
                && !(legacyPairURL(username: username, playlistMBID: playlistMBID).map { manager.fileExists(atPath: $0.path()) } ?? false)
        } catch { return false }
    }
    private func pairURL(username: String, playlistMBID: UUID) -> URL? {
        directoryURL?.appending(path: "\(digest(username, playlistMBID)).json")
    }
    private func legacyPairURL(username: String, playlistMBID: UUID) -> URL? {
        directoryURL?.deletingLastPathComponent().appending(path: "playlist-item-removals-v1", directoryHint: .isDirectory)
            .appending(path: "\(Self.hash(normalized(username))).\(playlistMBID.uuidString.lowercased()).json")
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
    private func digest(_ username: String, _ playlistMBID: UUID) -> String {
        Self.hash(normalized(username) + "\u{0}" + playlistMBID.uuidString.lowercased())
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

/// Compatibility name retained for existing removal callers. Both removal and
/// reorder reserve the same account/playlist barrier.
typealias PlaylistItemRemovalJournal = PlaylistItemMutationJournal

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
                String(localized: "Brainz couldn’t reset this playlist’s track-change safety record. Try again before changing tracks."))
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
                    String(localized: "Track changes are paused because their safety record can’t be read. Reset it only after reviewing this playlist on ListenBrainz.")
                )
                return latest
            }
            do {
                try Task.checkCancellation()
                try await provider.removeItem(at: selected.position - 1, from: seed.mbid)
            } catch is CancellationError {
                if !journal.cancelBeforeDispatch(username: account.username, playlistMBID: seed.mbid) {
                    notice = .needsReview(
                        String(localized: "The change was canceled, but its safety record could not be cleared. Refresh and review the playlist before changing tracks again.")
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
                    String(localized: "ListenBrainz may have moved or removed a track, but the response was lost. Refresh the playlist before changing tracks again.")
                )
                return latest
            }
            isReconciling = true
            defer { isReconciling = false }
            do {
                let canonical = try await detailProvider.playlistForMutationInspection(mbid: seed.mbid)
                guard Self.isExactRemoval(of: selected, from: latest, canonical: canonical) else {
                    notice = .needsReview(
                        String(localized: "The playlist changed while a track was being removed. Review the current order before changing tracks again.")
                    )
                    return canonical
                }
                guard journal.resolveAfterInspection(username: account.username, playlistMBID: seed.mbid) else {
                    notice = .needsReview(
                        String(localized: "The track was removed, but its safety record could not be cleared. Refresh and review the playlist before changing tracks again.")
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
                    String(localized: "The playlist could not be refreshed after removal. Refresh and review it before changing tracks again.")
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
            guard detail.mbid == playlistMBID else {
                notice = .needsReview(
                    String(localized: "Brainz refreshed a different playlist. Try again before changing tracks.")
                )
                return nil
            }
            reviewedPairs.insert(playlistMBID)
            if !journal.requiresRecovery(username: account.username, playlistMBID: playlistMBID),
                !journal.resolveAfterInspection(username: account.username, playlistMBID: playlistMBID)
            {
                notice = .needsReview(
                    String(localized: "The playlist was refreshed, but its safety record could not be cleared. Reset it before changing tracks again.")
                )
                return detail
            }
            notice = .refreshed
            return detail
        } catch {
            if PlaylistAccessFailurePolicy.requiresPurge(error) {
                return await recordAccessLoss(error, playlistMBID: playlistMBID)
            }
            notice = .needsReview(String(localized: "The playlist could not be refreshed. Try again before changing tracks."))
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
            guard canonical.mbid == playlistMBID else {
                notice = .needsReview(
                    String(localized: "Brainz refreshed a different playlist. Try again before changing tracks.")
                )
                return latest
            }
            guard journal.cancelBeforeDispatch(username: account.username, playlistMBID: playlistMBID) else {
                notice = .needsReview(
                    String(localized: "ListenBrainz rejected the removal, but its safety record could not be cleared. Refresh and review the playlist before removing another track.")
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
                String(localized: "ListenBrainz rejected the removal, but Brainz couldn’t refresh the playlist. Refresh it before trying again.")
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

enum PlaylistItemReorderNotice: Identifiable, Equatable {
    case stale
    case confirmed
    case needsReview(String)
    case failed(String)
    case accessLost(String)
    var id: String {
        switch self {
        case .stale: "stale"
        case .confirmed: "confirmed"
        case .needsReview(let value): "review:\(value)"
        case .failed(let value): "failed:\(value)"
        case .accessLost(let value): "access:\(value)"
        }
    }
}

/// Coordinates a single positional reorder. It intentionally uses a complete,
/// uncached playlist inspection before and after the POST: an OK response alone
/// never proves which duplicate occurrence the server moved.
@MainActor @Observable
final class PlaylistItemReorderModel {
    private let account: Account
    private let detailProvider: any PlaylistDetailProviding
    private let provider: any PlaylistItemReorderingProviding
    private let journal: PlaylistItemMutationJournal
    private let mutationJournal: PlaylistMutationJournal
    private(set) var isSaving = false
    private(set) var isReconciling = false
    private(set) var notice: PlaylistItemReorderNotice?
    private var mutationDeniedPairs: Set<UUID> = []

    init(account: Account, detailProvider: any PlaylistDetailProviding,
         provider: any PlaylistItemReorderingProviding,
         journal: PlaylistItemMutationJournal = .shared,
         mutationJournal: PlaylistMutationJournal = .shared) {
        self.account = account; self.detailProvider = detailProvider; self.provider = provider
        self.journal = journal; self.mutationJournal = mutationJournal
    }

    static func canReorder(account: Account, detail: PlaylistDetail?) -> Bool {
        PlaylistItemRemovalModel.canRemove(account: account, detail: detail)
    }
    func canAttemptReorder(_ detail: PlaylistDetail?) -> Bool {
        guard let detail, !mutationDeniedPairs.contains(detail.mbid) else { return false }
        return detail.tracks.count >= 2 && Self.hasCanonicalSlots(detail.tracks)
            && Self.canReorder(account: account, detail: detail)
            && !journal.requiresReview(username: account.username, playlistMBID: detail.mbid)
    }
    func dismissNotice() { notice = nil }

    func save(baseline: PlaylistDetail, from: Int, to: Int) async -> PlaylistDetail? {
        guard !isSaving, !isReconciling, from >= 0, to >= 0, from != to,
              from < baseline.tracks.count, to < baseline.tracks.count,
              canAttemptReorder(baseline), Self.hasCanonicalSlots(baseline.tracks),
              let sourceMBID = baseline.tracks[from].recording.identity.mbid
        else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let preflight = try await detailProvider.playlistForMutationInspection(mbid: baseline.mbid)
            guard Self.canReorder(account: account, detail: preflight) else {
                mutationDeniedPairs.insert(baseline.mbid); notice = .failed(PlaylistMutationProviderError.notCollaborator.localizedDescription); return preflight
            }
            guard preflight.mbid == baseline.mbid,
                  Self.sameSlots(baseline.tracks, preflight.tracks)
            else { notice = .stale; return preflight }
            try Task.checkCancellation()
            guard journal.begin(username: account.username, playlistMBID: baseline.mbid) else {
                notice = .needsReview(String(localized: "Track changes need review. Refresh the playlist before changing its order."))
                return preflight
            }
            do {
                try Task.checkCancellation()
                try await provider.moveItem(recordingMBID: sourceMBID, from: from, to: to, in: baseline.mbid)
            } catch is CancellationError {
                if !journal.cancelBeforeDispatch(username: account.username, playlistMBID: baseline.mbid) {
                    notice = .needsReview(String(localized: "Track changes need review. Refresh the playlist before changing it again."))
                }
                return nil
            } catch PlaylistMutationProviderError.notCollaborator {
                mutationDeniedPairs.insert(baseline.mbid)
                return await reconcilePermissionDenied(preflight, playlistMBID: baseline.mbid)
            } catch let error as PlaylistMutationProviderError where PlaylistAccessFailurePolicy.requiresPurge(error) {
                _ = journal.cancelBeforeDispatch(username: account.username, playlistMBID: baseline.mbid)
                return await accessLost(error, playlistMBID: baseline.mbid)
            } catch let error as PlaylistMutationProviderError where !error.isIndeterminate {
                guard journal.cancelBeforeDispatch(username: account.username, playlistMBID: baseline.mbid) else {
                    notice = .needsReview(String(localized: "ListenBrainz rejected the change, but Brainz couldn’t clear its safety record. Refresh and review the playlist before changing tracks again."))
                    return nil
                }
                notice = .failed(error.localizedDescription); return nil
            } catch let ProviderError.rateLimited(seconds) {
                guard journal.cancelBeforeDispatch(username: account.username, playlistMBID: baseline.mbid) else {
                    notice = .needsReview(String(localized: "The change did not start, but Brainz couldn’t clear its safety record. Refresh and review the playlist before changing tracks again."))
                    return nil
                }
                notice = .failed(ProviderError.rateLimited(retryAfterSeconds: seconds).localizedDescription)
                return nil
            } catch {
                // A dispatched request has an unresolved barrier. A live task
                // gets one postflight; cancelled work leaves it for explicit review.
                guard !Task.isCancelled else { return nil }
                return await postflight(preflight, from: from, to: to)
            }
            return await postflight(preflight, from: from, to: to)
        } catch is CancellationError { return nil }
        catch {
            if PlaylistAccessFailurePolicy.requiresPurge(error) { return await accessLost(error, playlistMBID: baseline.mbid) }
            notice = .failed(error.localizedDescription); return nil
        }
    }

    func refreshAfterReview(playlistMBID: UUID) async -> PlaylistDetail? {
        isReconciling = true; defer { isReconciling = false }
        do {
            let detail = try await detailProvider.playlistForMutationInspection(mbid: playlistMBID)
            guard detail.mbid == playlistMBID else {
                notice = .needsReview(String(localized: "Brainz refreshed a different playlist. Try again before changing tracks."))
                return nil
            }
            guard journal.resolveAfterInspection(username: account.username, playlistMBID: playlistMBID) else {
                notice = .needsReview(String(localized: "Track changes need review. Refresh the playlist before changing it again."))
                return detail
            }
            return detail
        } catch { if PlaylistAccessFailurePolicy.requiresPurge(error) { return await accessLost(error, playlistMBID: playlistMBID) }; notice = .needsReview(String(localized: "Couldn’t refresh this playlist. Try again before changing tracks.")); return nil }
    }

    private func postflight(_ preflight: PlaylistDetail, from: Int, to: Int) async -> PlaylistDetail? {
        isReconciling = true; defer { isReconciling = false }
        do {
            let canonical = try await detailProvider.playlistForMutationInspection(mbid: preflight.mbid)
            guard canonical.mbid == preflight.mbid,
                  Self.isExactMove(from: preflight.tracks, from: from, to: to, canonical: canonical.tracks)
            else {
                notice = .needsReview(String(localized: "This playlist changed. Track changes need review before you change its order again."))
                return canonical
            }
            guard journal.resolveAfterInspection(username: account.username, playlistMBID: preflight.mbid) else {
                notice = .needsReview(String(localized: "The order was saved, but its safety record could not be cleared. Refresh and review the playlist before changing tracks again."))
                return canonical
            }
            notice = .confirmed; return canonical
        } catch { if PlaylistAccessFailurePolicy.requiresPurge(error) { return await accessLost(error, playlistMBID: preflight.mbid) }; notice = .needsReview(String(localized: "Track changes need review. Refresh the playlist before changing it again.")); return nil }
    }
    private func reconcilePermissionDenied(_ latest: PlaylistDetail, playlistMBID: UUID) async -> PlaylistDetail? {
        isReconciling = true; defer { isReconciling = false }
        do {
            let canonical = try await detailProvider.playlistForMutationInspection(mbid: playlistMBID)
            guard canonical.mbid == playlistMBID else {
                notice = .needsReview(String(localized: "Brainz refreshed a different playlist. Try again before changing tracks."))
                return latest
            }
            guard journal.cancelBeforeDispatch(username: account.username, playlistMBID: playlistMBID) else { notice = .needsReview(String(localized: "Track changes need review. Refresh the playlist before changing it again.")); return canonical }
            notice = .failed(PlaylistMutationProviderError.notCollaborator.localizedDescription); return canonical
        } catch {
            if PlaylistAccessFailurePolicy.requiresPurge(error) {
                _ = journal.cancelBeforeDispatch(username: account.username, playlistMBID: playlistMBID)
                return await accessLost(error, playlistMBID: playlistMBID)
            }
            notice = .needsReview(String(localized: "Track changes need review. Refresh the playlist before changing it again."))
            return latest
        }
    }
    private func accessLost(_ error: any Error, playlistMBID: UUID) async -> PlaylistDetail? {
        guard let reason = PlaylistAccessFailurePolicy.reason(for: error) else { notice = .failed(error.localizedDescription); return nil }
        await mutationJournal.recordAccessLoss(sourceMBID: playlistMBID, viewerUsername: account.username, reason: reason, message: error.localizedDescription)
        notice = .accessLost(error.localizedDescription); return nil
    }
    private static func hasCanonicalSlots(_ tracks: [PlaylistTrack]) -> Bool {
        tracks.enumerated().allSatisfy { index, track in track.position == index + 1 && track.recording.identity.mbid != nil }
    }
    private struct SlotFingerprint: Hashable {
        let recordingMBID: UUID
        let addedAt: Date?
        let addedBy: String
    }
    private static func fingerprint(_ track: PlaylistTrack) -> SlotFingerprint? {
        guard let mbid = track.recording.identity.mbid else { return nil }
        return .init(
            recordingMBID: mbid,
            addedAt: track.addedAt,
            addedBy: track.addedBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        )
    }
    private static func sameSlots(_ lhs: [PlaylistTrack], _ rhs: [PlaylistTrack]) -> Bool {
        hasCanonicalSlots(lhs) && hasCanonicalSlots(rhs) && lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { fingerprint($0) == fingerprint($1) }
    }
    private static func isExactMove(from source: [PlaylistTrack], from: Int, to: Int, canonical: [PlaylistTrack]) -> Bool {
        guard hasCanonicalSlots(source), hasCanonicalSlots(canonical), source.indices.contains(from), source.indices.contains(to) else { return false }
        let sourceSlots = source.compactMap(fingerprint)
        let canonicalSlots = canonical.compactMap(fingerprint)
        guard sourceSlots.count == source.count, canonicalSlots.count == canonical.count else { return false }
        var expected = sourceSlots
        let moved = expected.remove(at: from)
        expected.insert(moved, at: to)
        return expected == canonicalSlots
    }
}
