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

    private(set) var state: State = .restoring
    var isWorking = false
    var errorMessage: String?
    private var didRestore = false

    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-brainz-profile-playlists-demo")
            || arguments.contains("-brainz-profile-playlists-collab-demo") {
            state = .active(Account(username: "visual-listener", token: "visual-token"))
            return
        }
        if arguments.contains("-brainz-artist-evolution-demo")
            || arguments.contains("-brainz-artist-evolution-all-time-demo")
            || arguments.contains("-brainz-genre-activity-demo") {
            state = .active(Account(username: "visual-taste", token: "visual-taste"))
            return
        }
        if arguments.contains("-brainz-popularity-detail-demo") {
            state = .active(Account(username: "visual-popularity", token: "visual-popularity"))
            return
        }
        if arguments.contains("-brainz-year-in-music-demo") {
            state = .active(Account(username: "visual-taste", token: "visual-taste"))
            return
        }
        if arguments.contains("-brainz-taste-demo")
            || arguments.contains("-brainz-taste-heatmap-demo")
            || arguments.contains("-brainz-year-in-music-teaser-demo")
            || arguments.contains("-brainz-taste-era-demo")
            || arguments.contains("-brainz-taste-era-zoom-demo")
            || arguments.contains("-brainz-taste-era-card-demo") {
            state = .active(Account(username: "visual-taste", token: "visual-taste"))
            return
        }
        if arguments.contains("-brainz-history-demo")
            || arguments.contains("-brainz-history-day-demo") {
            state = .active(Account(username: "visual-history", token: "visual-history"))
            return
        }
        #endif
        let username = UserDefaults.standard.string(forKey: "listenbrainz.username") ?? ""
        if !username.isEmpty {
            state = .active(Account(username: username, token: KeychainStore.loadToken() ?? ""))
        } else {
            state = .signedOut
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
            let username = try await ListenBrainzProvider(token: token).validateToken()
            try KeychainStore.saveToken(token)
            UserDefaults.standard.set(username, forKey: "listenbrainz.username")
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
            try KeychainStore.deleteToken()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        var cleanupError: String?
        if case let .active(previousAccount) = state {
            do {
                try await SnapshotCache.shared.invalidate(username: previousAccount.username)
            } catch {
                cleanupError = error.localizedDescription
            }
        }
        UserDefaults.standard.set(username, forKey: "listenbrainz.username")
        state = .active(Account(username: username, token: ""))
        errorMessage = cleanupError
    }

    func signOut() async {
        do {
            try KeychainStore.deleteToken()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        var cleanupError: String?
        if case let .active(account) = state {
            do {
                try await SnapshotCache.shared.invalidate(username: account.username)
            } catch {
                cleanupError = error.localizedDescription
            }
        }
        UserDefaults.standard.removeObject(forKey: "listenbrainz.username")
        state = .signedOut
        errorMessage = cleanupError
    }
}
