import Foundation
import Observation

@MainActor
@Observable
final class FreshReleasesModel {
    let account: Account
    private let provider: any ListeningProvider
    private var requestIDs: [FreshReleaseScope: UUID] = [:]
    private(set) var states: [FreshReleaseScope: FreshReleasesLoadState] = [:]

    init(account: Account, provider: (any ListeningProvider)? = nil) {
        self.account = account
        self.provider = provider ?? ListenBrainzProvider(token: account.token)
    }

    func state(for scope: FreshReleaseScope) -> FreshReleasesLoadState {
        states[scope] ?? .idle
    }

    func isLoading(scope: FreshReleaseScope) -> Bool {
        state(for: scope) == .loading
    }

    func load(scope: FreshReleaseScope, retrying: Bool = false) async {
        switch state(for: scope) {
        case .loaded:
            return
        case .failed where !retrying:
            return
        case .idle, .loading, .failed:
            states[scope] = .loading
        }

        // A scope can be selected again before cancellation of its previous
        // SwiftUI task reaches the provider. The newer request owns the state;
        // a superseded task may finish, but cannot reset or overwrite it.
        let requestID = UUID()
        requestIDs[scope] = requestID
        do {
            let releases = try await provider.freshReleases(username: account.username, scope: scope)
            guard requestIDs[scope] == requestID else { return }
            states[scope] = .loaded(releases)
            requestIDs[scope] = nil
        } catch {
            guard requestIDs[scope] == requestID else { return }
            states[scope] = Task.isCancelled ? .idle : .failed(error.localizedDescription)
            requestIDs[scope] = nil
        }
    }

    func refresh(scope: FreshReleaseScope) async {
        guard !isLoading(scope: scope) else { return }
        states[scope] = .idle
        await load(scope: scope, retrying: true)
    }
}
