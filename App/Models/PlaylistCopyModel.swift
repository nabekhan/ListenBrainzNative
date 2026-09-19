import Foundation
import Observation

struct PlaylistCopyReconciliationRecord: Codable, Equatable, Sendable {
    let username: String
    let sourceMBID: UUID
    let attemptedAt: Date
    var destinationMBID: UUID?
}

/// A durable, token-free safety barrier for the non-idempotent copy endpoint.
/// A successful replay always creates another playlist, so an attempt remains
/// blocked across launches until its destination is verified canonically.
@MainActor
@Observable
final class PlaylistCopyReconciliationJournal {
    static let shared = PlaylistCopyReconciliationJournal(defaults: .standard)

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let storageKey: String
    private var records: [String: PlaylistCopyReconciliationRecord]

    init(
        defaults: UserDefaults? = nil,
        storageKey: String = "listenbrainz.playlist-copy.unresolved.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        records = Self.load(defaults: defaults, storageKey: storageKey)
    }

    func record(username: String, sourceMBID: UUID) -> PlaylistCopyReconciliationRecord? {
        records[key(username: username, sourceMBID: sourceMBID)]
    }

    func requiresInspection(username: String, sourceMBID: UUID) -> Bool {
        record(username: username, sourceMBID: sourceMBID) != nil
    }

    func beginAttempt(username: String, sourceMBID: UUID, at date: Date) {
        let normalizedUsername = Self.normalized(username)
        records[key(username: normalizedUsername, sourceMBID: sourceMBID)] = .init(
            username: normalizedUsername,
            sourceMBID: sourceMBID,
            attemptedAt: date,
            destinationMBID: nil
        )
        persist()
    }

    func markDestination(username: String, sourceMBID: UUID, destinationMBID: UUID) {
        let recordKey = key(username: username, sourceMBID: sourceMBID)
        guard var value = records[recordKey] else { return }
        value.destinationMBID = destinationMBID
        records[recordKey] = value
        persist()
    }

    func resolveConfirmed(username: String, sourceMBID: UUID) {
        records.removeValue(forKey: key(username: username, sourceMBID: sourceMBID))
        persist()
    }

    private func key(username: String, sourceMBID: UUID) -> String {
        "\(Self.normalized(username)):\(sourceMBID.uuidString.lowercased())"
    }

    private func persist() {
        guard let defaults else { return }
        let values = records.values.sorted {
            if $0.username == $1.username {
                return $0.sourceMBID.uuidString < $1.sourceMBID.uuidString
            }
            return $0.username < $1.username
        }
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(
        defaults: UserDefaults?,
        storageKey: String
    ) -> [String: PlaylistCopyReconciliationRecord] {
        guard let data = defaults?.data(forKey: storageKey),
              let values = try? JSONDecoder().decode(
                  [PlaylistCopyReconciliationRecord].self,
                  from: data
              )
        else { return [:] }

        return values.reduce(into: [:]) { result, value in
            let key = "\(normalized(value.username)):\(value.sourceMBID.uuidString.lowercased())"
            result[key] = value
        }
    }

    private static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum PlaylistCopyNotice: Identifiable, Equatable, Sendable {
    case confirmed(SearchPlaylist)
    case failed(id: UUID, message: String)
    case verificationNeeded(id: UUID, destinationMBID: UUID?, message: String)

    var id: String {
        switch self {
        case let .confirmed(playlist):
            "confirmed:\(playlist.id)"
        case let .failed(id, _):
            "failed:\(id.uuidString)"
        case let .verificationNeeded(id, _, _):
            "verification:\(id.uuidString)"
        }
    }
}

@MainActor
@Observable
final class PlaylistCopyModel {
    let account: Account
    let sourceMBID: UUID?
    private let provider: any PlaylistCopyProviding
    private let detailProvider: any PlaylistDetailProviding
    private let profileProvider: any ProfilePlaylistsProviding
    private let reconciliationJournal: PlaylistCopyReconciliationJournal
    @ObservationIgnored private let now: () -> Date

    private(set) var isCopying = false
    private(set) var isReconciling = false
    private(set) var sourceAccessLossReason: PlaylistAccessLossReason?
    private(set) var sourceAccessMessage: String?
    private(set) var notice: PlaylistCopyNotice?

    init(
        account: Account,
        sourceMBID: UUID?,
        provider: (any PlaylistCopyProviding)? = nil,
        detailProvider: (any PlaylistDetailProviding)? = nil,
        profileProvider: (any ProfilePlaylistsProviding)? = nil,
        reconciliationJournal: PlaylistCopyReconciliationJournal = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.account = account
        self.sourceMBID = sourceMBID
        self.provider = provider ?? ListenBrainzPlaylistCopyProvider(token: account.token)
        self.detailProvider = detailProvider ?? ListenBrainzMediaDetailProvider(token: account.token)
        self.profileProvider = profileProvider ?? ListenBrainzProfilePlaylistsProvider(token: account.token)
        self.reconciliationJournal = reconciliationJournal
        self.now = now
    }

    static func canCopy(account: Account, detail: PlaylistDetail?) -> Bool {
        account.isAuthenticated && detail != nil
    }

    func copy(_ source: PlaylistDetail) async {
        guard account.isAuthenticated,
              source.mbid == sourceMBID,
              !isCopying,
              !requiresReconciliation
        else { return }
        isCopying = true
        sourceAccessLossReason = nil
        sourceAccessMessage = nil
        notice = nil
        reconciliationJournal.beginAttempt(
            username: account.username,
            sourceMBID: source.mbid,
            at: now()
        )
        defer { isCopying = false }

        do {
            let copiedMBID = try await provider.copy(mbid: source.mbid)
            reconciliationJournal.markDestination(
                username: account.username,
                sourceMBID: source.mbid,
                destinationMBID: copiedMBID
            )
            try await confirmCanonicalDestination(mbid: copiedMBID)
        } catch is CancellationError {
            // A CancellationError from the mutation provider means RequestGate
            // never admitted the POST. Once a destination is known, however,
            // cancellation can only come from the follow-up GET and the durable
            // record must remain until that playlist is verified.
            if reconciliationRecord?.destinationMBID == nil {
                reconciliationJournal.resolveConfirmed(
                    username: account.username,
                    sourceMBID: source.mbid
                )
            } else {
                showVerificationNeeded(destinationMBID: reconciliationRecord?.destinationMBID)
            }
        } catch {
            if reconciliationRecord?.destinationMBID != nil {
                captureAuthenticationLossIfNeeded(error)
                showVerificationNeeded(destinationMBID: reconciliationRecord?.destinationMBID)
                return
            }

            if let providerError = error as? PlaylistMutationProviderError,
               providerError.isIndeterminate {
                notice = .verificationNeeded(
                    id: UUID(),
                    destinationMBID: nil,
                    message: providerError.localizedDescription
                )
                return
            }

            reconciliationJournal.resolveConfirmed(
                username: account.username,
                sourceMBID: source.mbid
            )
            captureSourceAccessLossIfNeeded(error)
            notice = .failed(id: UUID(), message: error.localizedDescription)
        }
    }

    /// Performs real network reconciliation. It never treats an already-loaded
    /// Profile list, or the absence of a match, as proof that replay is safe.
    func reconcileAfterOwnedPlaylistsRefresh() async {
        guard !isCopying,
              !isReconciling,
              let sourceMBID,
              let attempt = reconciliationRecord
        else { return }
        isReconciling = true
        sourceAccessLossReason = nil
        sourceAccessMessage = nil
        notice = nil
        defer { isReconciling = false }

        do {
            let destinationMBID: UUID
            if let knownDestination = attempt.destinationMBID {
                destinationMBID = knownDestination
            } else {
                let page: ProfilePlaylistPage
                do {
                    page = try await profileProvider.page(
                        username: account.username,
                        category: .owned,
                        offset: 0,
                        count: 100
                    )
                } catch {
                    captureSourceAccessLossIfNeeded(error)
                    throw error
                }
                guard let candidate = Self.reconciliationCandidate(
                    in: page.playlists,
                    sourceMBID: sourceMBID,
                    attemptedAt: attempt.attemptedAt
                ), let candidateMBID = candidate.playlistMBID
                else {
                    notice = .verificationNeeded(
                        id: UUID(),
                        destinationMBID: nil,
                        message: "No matching recent copy was verified in your newest Owned Playlists. Duplicate stays disabled so another playlist cannot be created accidentally."
                    )
                    return
                }
                destinationMBID = candidateMBID
                reconciliationJournal.markDestination(
                    username: account.username,
                    sourceMBID: sourceMBID,
                    destinationMBID: destinationMBID
                )
            }

            try await confirmCanonicalDestination(mbid: destinationMBID)
        } catch {
            captureAuthenticationLossIfNeeded(error)
            showVerificationNeeded(destinationMBID: reconciliationRecord?.destinationMBID)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    /// The durable record is cleared only after the user has been shown the
    /// canonically verified destination. This closes the crash window between
    /// a successful GET and presenting the result on screen.
    func acknowledgeConfirmedCopy() {
        guard case .confirmed = notice, let sourceMBID else { return }
        reconciliationJournal.resolveConfirmed(
            username: account.username,
            sourceMBID: sourceMBID
        )
        notice = nil
    }

    var requiresReconciliation: Bool {
        reconciliationRecord != nil
    }

    var reconciliationRecord: PlaylistCopyReconciliationRecord? {
        guard let sourceMBID else { return nil }
        return reconciliationJournal.record(
            username: account.username,
            sourceMBID: sourceMBID
        )
    }

    var sourceAccessWasLost: Bool {
        sourceAccessLossReason != nil
    }

    private func confirmCanonicalDestination(mbid: UUID) async throws {
        let detail = try await detailProvider.playlist(mbid: mbid)
        guard detail.mbid == mbid else { throw PlaylistCopyVerificationError.mismatchedDestination }
        guard Self.normalizedUsername(detail.creator) == Self.normalizedUsername(account.username) else {
            throw PlaylistCopyVerificationError.mismatchedOwner
        }
        guard let sourceMBID,
              detail.copiedFrom.flatMap({ UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }) == sourceMBID
        else {
            throw PlaylistCopyVerificationError.mismatchedSource
        }
        let canonical = Self.searchPlaylist(from: detail)
        notice = .confirmed(canonical)
    }

    private func captureSourceAccessLossIfNeeded(_ error: any Error) {
        guard let reason = PlaylistAccessFailurePolicy.reason(for: error) else { return }
        sourceAccessLossReason = reason
        sourceAccessMessage = error.localizedDescription
    }

    private func captureAuthenticationLossIfNeeded(_ error: any Error) {
        guard PlaylistAccessFailurePolicy.reason(for: error) == .authentication else { return }
        sourceAccessLossReason = .authentication
        sourceAccessMessage = error.localizedDescription
    }

    private func showVerificationNeeded(destinationMBID: UUID?) {
        let message: String
        if destinationMBID == nil {
            message = PlaylistMutationProviderError.indeterminateCopy.localizedDescription
        } else {
            message = "ListenBrainz created the copy, but its current details could not be loaded. Duplicate stays disabled until the returned playlist is verified."
        }
        notice = .verificationNeeded(
            id: UUID(),
            destinationMBID: destinationMBID,
            message: message
        )
    }

    private static func reconciliationCandidate(
        in playlists: [SearchPlaylist],
        sourceMBID: UUID,
        attemptedAt: Date
    ) -> SearchPlaylist? {
        // Clock skew can cause a safe false negative. A narrow five-second
        // allowance avoids accepting an unrelated older copy merely because it
        // has the same source provenance.
        let earliest = attemptedAt.addingTimeInterval(-5)
        return playlists
            .filter {
                $0.copiedFromMBID == sourceMBID
                    && ($0.createdAt.map { $0 >= earliest } ?? false)
            }
            .max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private static func searchPlaylist(from detail: PlaylistDetail) -> SearchPlaylist {
        SearchPlaylist(
            title: detail.title,
            creator: detail.creator,
            annotation: detail.annotation,
            identifier: detail.listenBrainzURL.absoluteString,
            isPublic: detail.isPublic,
            lastModifiedAt: detail.lastModifiedAt,
            createdAt: detail.createdAt,
            durationMilliseconds: detail.totalDurationMilliseconds,
            createdFor: detail.createdFor,
            collaborators: detail.collaborators,
            copiedFrom: detail.copiedFrom,
            recommendationType: nil,
            expiresAt: nil
        )
    }

    private static func normalizedUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private enum PlaylistCopyVerificationError: LocalizedError, Sendable {
    case mismatchedDestination
    case mismatchedOwner
    case mismatchedSource

    var errorDescription: String? {
        switch self {
        case .mismatchedDestination:
            "ListenBrainz returned details for a different playlist. The copy remains locked until it can be verified safely."
        case .mismatchedOwner:
            "The returned playlist is not owned by this account. The copy remains locked until it can be verified safely."
        case .mismatchedSource:
            "The returned playlist does not identify this source playlist. The copy remains locked until it can be verified safely."
        }
    }
}
