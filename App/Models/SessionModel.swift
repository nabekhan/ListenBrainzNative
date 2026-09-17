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
