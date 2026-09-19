import CryptoKit
import Darwin
import Foundation
import ListenBrainzKit
import Observation

/// A radio save is non-idempotent. This record deliberately contains no mix
/// content, title, prompt, or credential: it only prevents a second create
/// until the owner has inspected their canonical playlist list.
private struct RadioPlaylistSaveRecord: Codable, Sendable {
    let attemptedAt: Date
}

@MainActor
@Observable
final class RadioPlaylistSaveJournal {
    static let shared: RadioPlaylistSaveJournal = {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return .init(storageUnavailable: true)
        }
        return .init(
            directoryURL: root.appending(path: "Brainz/radio-playlist-saves-v1", directoryHint: .isDirectory)
        )
    }()

    @ObservationIgnored private let directoryURL: URL?
    @ObservationIgnored private let storageUnavailable: Bool
    private var loadedKeys: Set<String> = []
    private var unreadableKeys: Set<String> = []
    private var records: [String: RadioPlaylistSaveRecord] = [:]

    /// A nil directory is an in-memory journal for focused tests. Production
    /// always supplies the Application Support directory above.
    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL
        storageUnavailable = false
    }

    private init(storageUnavailable: Bool) {
        directoryURL = nil
        self.storageUnavailable = storageUnavailable
    }

    func requiresRecovery(username: String) -> Bool {
        let key = Self.key(username)
        loadIfNeeded(username: username)
        return storageUnavailable || unreadableKeys.contains(key)
    }

    func requiresReview(username: String) -> Bool {
        let key = Self.key(username)
        loadIfNeeded(username: username)
        return storageUnavailable || unreadableKeys.contains(key) || records[key] != nil
    }

    /// Returns only after the replay barrier is on stable storage. The caller
    /// must not dispatch the non-idempotent POST when this returns false.
    func begin(username: String, at date: Date) -> Bool {
        let key = Self.key(username)
        loadIfNeeded(username: username)
        guard !storageUnavailable, !unreadableKeys.contains(key), records[key] == nil else { return false }
        let record = RadioPlaylistSaveRecord(attemptedAt: date)
        guard persist(record, username: username) else {
            unreadableKeys.insert(key)
            return false
        }
        records[key] = record
        return true
    }

    /// Clears a definite result or a barrier the user reconciled against a
    /// fresh canonical list. A failed clear remains blocked.
    func resolveAfterReview(username: String) -> Bool {
        let key = Self.key(username)
        loadIfNeeded(username: username)
        guard !storageUnavailable, !unreadableKeys.contains(key), remove(username: username) else {
            return false
        }
        records.removeValue(forKey: key)
        loadedKeys.insert(key)
        return true
    }

    func cancelBeforeDispatch(username: String) -> Bool {
        resolveAfterReview(username: username)
    }

    /// Corrupt state may be discarded only after a fresh canonical review.
    func resetRecovery(username: String) -> Bool {
        let key = Self.key(username)
        loadIfNeeded(username: username)
        guard unreadableKeys.contains(key), !storageUnavailable, let url = fileURL(username: username) else {
            return false
        }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: url.path()) {
                try manager.removeItem(at: url)
                try Self.syncDirectory(url.deletingLastPathComponent())
            }
            guard !manager.fileExists(atPath: url.path()) else { return false }
            unreadableKeys.remove(key)
            records.removeValue(forKey: key)
            loadedKeys.insert(key)
            return true
        } catch {
            return false
        }
    }

    private func loadIfNeeded(username: String) {
        let key = Self.key(username)
        guard !loadedKeys.contains(key) else { return }
        loadedKeys.insert(key)
        guard !storageUnavailable, let url = fileURL(username: username),
            FileManager.default.fileExists(atPath: url.path())
        else { return }
        do {
            records[key] = try JSONDecoder().decode(RadioPlaylistSaveRecord.self, from: Data(contentsOf: url))
        } catch {
            unreadableKeys.insert(key)
        }
    }

    private func persist(_ record: RadioPlaylistSaveRecord, username: String) -> Bool {
        guard let url = fileURL(username: username) else {
            return directoryURL == nil && !storageUnavailable
        }
        do {
            try Self.writeDurably(JSONEncoder().encode(record), to: url)
            return true
        } catch {
            return false
        }
    }

    private func remove(username: String) -> Bool {
        guard let url = fileURL(username: username) else {
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

    private func fileURL(username: String) -> URL? {
        directoryURL?.appending(path: "\(Self.key(username)).json")
    }

    private static func key(_ username: String) -> String {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
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
                try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path())
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
                fileURL.path.withCString { destination in Darwin.rename(source, destination) }
            }
            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
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
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

protocol RadioPlaylistSaveProviding: Sendable {
    func save(metadata: PlaylistMetadataDraft, recordingMBIDs: [UUID], ownerUsername: String) async throws -> UUID
}

protocol RadioPlaylistSaveTransport: Sendable {
    func create(metadata: LBPlaylistMutationMetadata, recordingMBIDs: [UUID]) async throws -> UUID
}

private struct LiveRadioPlaylistSaveTransport: RadioPlaylistSaveTransport {
    let client: LBClient

    func create(metadata: LBPlaylistMutationMetadata, recordingMBIDs: [UUID]) async throws -> UUID {
        try await client.core.createPlaylist(metadata: metadata, recordingMBIDs: recordingMBIDs)
    }
}

/// A non-retrying populated-playlist creation boundary. Once the POST reaches
/// transport, all cancellation and transport failures are indeterminate.
struct ListenBrainzRadioPlaylistSaveProvider: RadioPlaylistSaveProviding {
    private let transport: any RadioPlaylistSaveTransport
    private let gate: RequestGate
    private let detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail>
    private let profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage>

    init(
        token: String,
        gate: RequestGate = .shared,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        transport = LiveRadioPlaylistSaveTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            ))
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    init(
        transport: some RadioPlaylistSaveTransport,
        gate: RequestGate,
        detailCache: EntityDetailCache<PlaylistDetailCacheKey, PlaylistDetail> = EntityDetailCaches.playlists,
        profilePageCache: EntityDetailCache<ProfilePlaylistPageKey, ProfilePlaylistPage> = ProfilePlaylistCaches.pages
    ) {
        self.transport = transport
        self.gate = gate
        self.detailCache = detailCache
        self.profilePageCache = profilePageCache
    }

    func save(metadata: PlaylistMetadataDraft, recordingMBIDs: [UUID], ownerUsername: String) async throws -> UUID {
        guard !recordingMBIDs.isEmpty else { throw PlaylistMutationProviderError.rejected }
        let draft = try metadata.normalized(ownerUsername: ownerUsername)
        let transportMetadata = LBPlaylistMutationMetadata(
            title: draft.title,
            annotation: draft.optionalAnnotation,
            isPublic: false,
            collaborators: []
        )
        let attempt = MutationAttemptState()
        do {
            let result = try await gate.perform({
                await attempt.markTransportStarted()
                return try await transport.create(metadata: transportMetadata, recordingMBIDs: recordingMBIDs)
            }) { error in
                guard case LBError.rateLimited(let resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            await detailCache.removeAll()
            await profilePageCache.removeAll()
            return result
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.noToken {
            await detailCache.removeAll()
            await profilePageCache.removeAll()
            throw PlaylistMutationProviderError.invalidAuthentication
        } catch LBError.forbidden {
            throw PlaylistMutationProviderError.notOwner
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam {
            throw PlaylistMutationProviderError.rejected
        } catch is CancellationError {
            if await attempt.didStartTransport {
                await detailCache.removeAll()
                await profilePageCache.removeAll()
                throw PlaylistMutationProviderError.indeterminateCreation
            }
            throw CancellationError()
        } catch {
            await detailCache.removeAll()
            await profilePageCache.removeAll()
            throw PlaylistMutationProviderError.indeterminateCreation
        }
    }

    private actor MutationAttemptState {
        private(set) var didStartTransport = false
        func markTransportStarted() { didStartTransport = true }
    }
}

enum RadioPlaylistSaveNotice: Identifiable, Equatable {
    case saved(SearchPlaylist)
    case failed(String)
    case needsReview(String)
    case reviewed

    var id: String {
        switch self {
        case .saved(let playlist): "saved:\(playlist.id)"
        case .failed(let message): "failed:\(message)"
        case .needsReview(let message): "review:\(message)"
        case .reviewed: "reviewed"
        }
    }
}

@MainActor
@Observable
final class RadioPlaylistSaveModel {
    let account: Account
    private let provider: any RadioPlaylistSaveProviding
    private let profileProvider: any ProfilePlaylistsProviding
    private let journal: RadioPlaylistSaveJournal
    @ObservationIgnored private let now: () -> Date

    private(set) var isSaving = false
    private(set) var isReviewing = false
    private(set) var notice: RadioPlaylistSaveNotice?
    private(set) var canResetAfterReview = false
    private(set) var reviewedPlaylists: [SearchPlaylist] = []

    init(
        account: Account,
        provider: (any RadioPlaylistSaveProviding)? = nil,
        profileProvider: (any ProfilePlaylistsProviding)? = nil,
        journal: RadioPlaylistSaveJournal = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzRadioPlaylistSaveProvider(token: account.token)
        self.profileProvider = profileProvider ?? ListenBrainzProfilePlaylistsProvider(token: account.token)
        self.journal = journal
        self.now = now
    }

    var requiresReview: Bool { journal.requiresReview(username: account.username) }
    var requiresStorageRecovery: Bool { journal.requiresRecovery(username: account.username) }

    static func recordingMBIDs(in mix: RadioMix) -> [UUID] {
        // Preserve the radio sequence, including intentional repeated tracks.
        // Only canonical recording IDs can be submitted at playlist creation.
        mix.tracks.compactMap { $0.recording.identity.mbid }
    }

    static func excludedTrackCount(in mix: RadioMix) -> Int {
        mix.tracks.count - recordingMBIDs(in: mix).count
    }

    func save(_ mix: RadioMix) async {
        let recordingMBIDs = Self.recordingMBIDs(in: mix)
        guard account.isAuthenticated, !recordingMBIDs.isEmpty, !isSaving, !requiresReview else { return }
        guard journal.begin(username: account.username, at: now()) else {
            notice = .needsReview(
                "Playlist saving is paused because Brainz couldn’t secure its duplicate-prevention record. Check Owned Playlists before resetting it."
            )
            return
        }
        isSaving = true
        notice = nil
        canResetAfterReview = false
        reviewedPlaylists = []
        defer { isSaving = false }

        let metadata = PlaylistMetadataDraft(
            title: mix.title,
            annotation: mix.annotation ?? "",
            isPublic: false,
            collaborators: []
        )
        do {
            let playlistMBID = try await provider.save(
                metadata: metadata,
                recordingMBIDs: recordingMBIDs,
                ownerUsername: account.username
            )
            let normalized = try metadata.normalized(ownerUsername: account.username)
            let playlist = SearchPlaylist(
                title: normalized.title,
                creator: account.username,
                annotation: normalized.optionalAnnotation,
                identifier: "https://listenbrainz.org/playlist/\(playlistMBID.uuidString)",
                isPublic: false,
                lastModifiedAt: now(),
                createdAt: now(),
                collaborators: []
            )
            _ = journal.resolveAfterReview(username: account.username)
            notice = .saved(playlist)
        } catch is CancellationError {
            if !journal.cancelBeforeDispatch(username: account.username) {
                notice = .needsReview(
                    "The request was cancelled before it started, but Brainz couldn’t clear its safety record. Check Owned Playlists before resetting it."
                )
            }
        } catch let error as PlaylistMutationProviderError where !error.isIndeterminate {
            if journal.resolveAfterReview(username: account.username) {
                notice = .failed(error.localizedDescription)
            } else {
                notice = .needsReview(
                    "ListenBrainz rejected the save, but Brainz couldn’t clear its safety record. Check Owned Playlists before resetting it."
                )
            }
        } catch let error as ProviderError {
            if journal.resolveAfterReview(username: account.username) {
                notice = .failed(error.localizedDescription)
            } else {
                notice = .needsReview(
                    "The save did not start, but Brainz couldn’t clear its safety record. Check Owned Playlists before resetting it."
                )
            }
        } catch {
            notice = .needsReview(PlaylistMutationProviderError.indeterminateCreation.localizedDescription)
        }
    }

    /// A fresh canonical Owned Playlists request is the minimum honest review
    /// step. The durable record holds no title or tracks, so it cannot safely
    /// auto-match a candidate after relaunch; the user explicitly clears it.
    func reviewOwnedPlaylists() async {
        guard requiresReview, !isSaving, !isReviewing else { return }
        isReviewing = true
        notice = nil
        defer { isReviewing = false }
        do {
            let page = try await profileProvider.freshPage(
                username: account.username,
                category: .owned,
                offset: 0,
                count: 100
            )
            reviewedPlaylists = page.playlists
            canResetAfterReview = true
            notice = .reviewed
        } catch {
            reviewedPlaylists = []
            canResetAfterReview = false
            notice = .needsReview(
                "Couldn’t load Owned Playlists. Reconnect, then check the list before saving this mix again.")
        }
    }

    func resetAfterReview() {
        guard requiresReview, canResetAfterReview else { return }
        let resolved =
            requiresStorageRecovery
            ? journal.resetRecovery(username: account.username)
            : journal.resolveAfterReview(username: account.username)
        guard resolved else {
            notice = .needsReview(
                "Brainz couldn’t reset its safety record. Playlist saving remains paused so it can’t create a duplicate."
            )
            return
        }
        canResetAfterReview = false
        reviewedPlaylists = []
        notice = nil
    }

    func dismissNotice() { notice = nil }
}
