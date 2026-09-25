import Foundation
import Observation

@MainActor
@Observable
final class SessionModel {
    enum State: Equatable {
        case restoring
        case signedOut
        case active(Account)
    }

    private static let publicUsernameKey = "listenbrainz.username"

    private(set) var state: State = .restoring
    var isWorking = false
    var errorMessage: String?
    private var didRestore = false
    private let snapshotCache: SnapshotCache
    private let credentialStore: any CredentialStoring
    private let defaults: UserDefaults
    private let validateToken: @Sendable (String) async throws -> String

    init(
        snapshotCache: SnapshotCache = .shared,
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        defaults: UserDefaults = .standard,
        validateToken: @escaping @Sendable (String) async throws -> String = { token in
            try await ListenBrainzProvider(token: token).validateToken()
        }
    ) {
        self.snapshotCache = snapshotCache
        self.credentialStore = credentialStore
        self.defaults = defaults
        self.validateToken = validateToken
    }

    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        #if DEBUG
            if restoreFixtureAccount() { return }
        #endif
        let legacyUsername = publicUsername()
        do {
            switch try await credentialStore.load() {
            case .account(let credential):
                // An atomic record wins over the old public-browsing value.
                defaults.removeObject(forKey: Self.publicUsernameKey)
                state = .active(Account(username: credential.username, token: credential.token))
            case .legacyToken(let token):
                let username = try canonicalUsername(try await validateToken(token))
                try await invalidateSnapshots(usernames: [legacyUsername, username])
                try await credentialStore.save(StoredCredential(username: username, token: token))
                defaults.removeObject(forKey: Self.publicUsernameKey)
                state = .active(Account(username: username, token: token))
            case nil:
                if let legacyUsername {
                    state = .active(Account(username: legacyUsername, token: ""))
                } else {
                    state = .signedOut
                }
            }
        } catch {
            state = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func signIn(token rawToken: String) async {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Paste the user token from your ListenBrainz settings."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let username = try canonicalUsername(try await validateToken(token))
            try await invalidateSnapshotsBeforeActivating(username: username)
            try await credentialStore.save(StoredCredential(username: username, token: token))
            defaults.removeObject(forKey: Self.publicUsernameKey)
            state = .active(Account(username: username, token: token))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func browsePublicProfile(username rawUsername: String) async {
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            errorMessage = ProviderError.missingUsername.localizedDescription
            return
        }
        do {
            // Do this before making public state visible, including when the
            // requested username matches the previous authenticated account.
            try await invalidateSnapshots(usernames: [activeUsername, username])
            try await credentialStore.delete()
            defaults.set(username, forKey: Self.publicUsernameKey)
            state = .active(Account(username: username, token: ""))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            // Keep the credential active unless its username-keyed snapshot was
            // removed first. A termination between these steps must not leave
            // authenticated data behind an apparently signed-out session.
            try await invalidateSnapshots(usernames: [activeUsername])
            try await credentialStore.delete()
            defaults.removeObject(forKey: Self.publicUsernameKey)
            state = .signedOut
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Snapshot files are intentionally keyed only by username. A successful
    /// credential replacement must evict both identity candidates before the
    /// new account becomes observable, so an older token cannot restore data.
    func invalidateSnapshotsBeforeActivating(username: String) async throws {
        try await invalidateSnapshots(usernames: [activeUsername, username])
    }

    private var activeUsername: String? {
        guard case .active(let account) = state else { return nil }
        return account.username
    }

    private func publicUsername() -> String? {
        let username = defaults.string(forKey: Self.publicUsernameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return username?.isEmpty == false ? username : nil
    }

    private func canonicalUsername(_ username: String) throws -> String {
        let canonical = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { throw ProviderError.missingUsername }
        return canonical
    }

    private func invalidateSnapshots(usernames: [String?]) async throws {
        let candidates: Set<String> = Set(
            usernames.compactMap { username -> String? in
                guard let username else { return nil }
                let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            })
        for username in candidates {
            try await snapshotCache.invalidate(username: username)
        }
    }

    #if DEBUG
        private func restoreFixtureAccount() -> Bool {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-brainz-home-pin-demo")
                || arguments.contains("-brainz-home-pin-empty-demo")
                || arguments.contains("-brainz-home-pin-failure-demo")
            {
                state = .active(Account(username: "visual-home", token: ""))
                return true
            }
            if arguments.contains("-brainz-profile-playlists-demo")
                || arguments.contains("-brainz-profile-playlists-collab-demo")
                || arguments.contains("-brainz-playlist-edit-demo")
                || arguments.contains("-brainz-playlist-add-demo")
                || arguments.contains("-brainz-playlist-copy-demo")
                || arguments.contains("-brainz-playlist-delete-confirmation-demo")
                || arguments.contains("-brainz-playlist-delete-confirmed-demo")
                || arguments.contains("-brainz-playlist-delete-review-demo")
                || arguments.contains("-brainz-playlist-remove-demo")
                || arguments.contains("-brainz-playlist-remove-review-demo")
                || arguments.contains("-brainz-playlist-reorder-demo")
                || arguments.contains("-brainz-playlist-reorder-review-demo")
                || arguments.contains("-brainz-following-pins-demo")
                || arguments.contains("-brainz-following-pins-empty-demo")
                || arguments.contains("-brainz-following-pins-failure-demo")
                || arguments.contains("-brainz-generic-art-demo")
                || arguments.contains("-brainz-generic-art-unavailable-demo")
                || arguments.contains("-brainz-generic-art-failure-demo")
                || arguments.contains("-brainz-connected-services-demo")
                || arguments.contains("-brainz-connected-services-empty-demo")
                || arguments.contains("-brainz-connected-services-failure-demo")
                || arguments.contains("-brainz-log-listen-demo")
                || arguments.contains("-brainz-log-listen-playing-now-demo")
                || arguments.contains("-brainz-log-listen-success-demo")
                || arguments.contains("-brainz-log-listen-indeterminate-demo")
                || arguments.contains("-brainz-log-listen-error-demo")
                || arguments.contains("-brainz-log-listen-recovery-demo")
            {
                state = .active(Account(username: "visual-listener", token: "visual-token"))
                return true
            }
            if arguments.contains("-brainz-artist-evolution-demo")
                || arguments.contains("-brainz-artist-evolution-all-time-demo")
                || arguments.contains("-brainz-genre-activity-demo")
                || arguments.contains("-brainz-artist-origins-demo")
                || arguments.contains("-brainz-artist-origins-country-demo")
                || arguments.contains("-brainz-artist-activity-demo")
                || arguments.contains("-brainz-artist-activity-expanded-demo")
                || arguments.contains("-brainz-user-defining-artists-demo")
                || arguments.contains("-brainz-user-profile-albums-demo")
                || arguments.contains("-brainz-user-profile-tracks-demo")
                || arguments.contains("-brainz-home-tracks-demo")
                || arguments.contains("-brainz-fresh-releases-demo")
                || arguments.contains("-brainz-fresh-releases-filters-demo")
            {
                state = .active(Account(username: "visual-taste", token: "visual-taste"))
                return true
            }
            if arguments.contains("-brainz-popularity-detail-demo")
                || arguments.contains("-brainz-artist-tracks-demo")
                || arguments.contains("-brainz-artist-context-demo")
                || arguments.contains("-brainz-artist-context-failure-demo")
                || arguments.contains("-brainz-artist-highlights-demo")
                || arguments.contains("-brainz-artist-highlights-releases-demo")
                || arguments.contains("-brainz-artist-highlights-failure-demo")
                || arguments.contains("-brainz-top-listeners-demo")
                || arguments.contains("-brainz-top-listeners-expanded-demo")
                || arguments.contains("-brainz-critiquebrainz-reviews-demo")
                || arguments.contains("-brainz-critiquebrainz-reader-demo")
                || arguments.contains("-brainz-critiquebrainz-reviews-unavailable-demo")
                || arguments.contains("-brainz-critiquebrainz-reviews-failure-demo")
                || arguments.contains("-brainz-similar-artists-demo")
                || arguments.contains("-brainz-similar-artists-expanded-demo")
            {
                state = .active(Account(username: "visual-popularity", token: "visual-popularity"))
                return true
            }
            if arguments.contains("-brainz-year-in-music-demo")
                || arguments.contains("-brainz-year-in-music-tracks-demo")
                || arguments.contains("-brainz-year-in-music-identity-demo")
                || arguments.contains("-brainz-year-in-music-evolution-demo")
                || arguments.contains("-brainz-year-in-music-new-releases-demo")
                || arguments.contains("-brainz-year-in-music-playlists-demo")
                || arguments.contains("-brainz-year-in-music-playlist-detail-demo")
                || arguments.contains("-brainz-year-in-music-2021-demo")
                || arguments.contains("-brainz-year-in-music-2024-demo") {
                state = .active(Account(username: "visual-taste", token: "visual-taste"))
                return true
            }
            if arguments.contains("-brainz-radio-demo") {
                state = .active(Account(username: "visual-radio", token: "visual-radio"))
                return true
            }
            if arguments.contains("-brainz-taste-demo")
                || arguments.contains("-brainz-taste-heatmap-demo")
                || arguments.contains("-brainz-taste-release-groups-demo")
                || arguments.contains("-brainz-taste-tracks-demo")
                || arguments.contains("-brainz-year-in-music-teaser-demo")
                || arguments.contains("-brainz-taste-era-demo")
                || arguments.contains("-brainz-taste-era-zoom-demo")
                || arguments.contains("-brainz-taste-era-card-demo")
            {
                state = .active(Account(username: "visual-taste", token: "visual-taste"))
                return true
            }
            if arguments.contains("-brainz-history-demo")
                || arguments.contains("-brainz-history-day-demo")
            {
                state = .active(Account(username: "visual-history", token: "visual-history"))
                return true
            }
            if arguments.contains("-brainz-inspect-listen-demo")
                || arguments.contains("-brainz-inspect-listen-unmapped-demo")
            {
                state = .active(Account(username: "visual-inspection", token: "visual-inspection"))
                return true
            }
            if arguments.contains("-brainz-recording-share-demo")
                || arguments.contains("-brainz-external-source-demo")
            {
                state = .active(Account(username: "visual-qa", token: "visual-qa"))
                return true
            }
            return false
        }
    #endif
}
