import Foundation
import Observation
import ListenBrainzKit

@MainActor
@Observable
final class ConnectedServicesModel {
    let account: Account

    private let scope: RequestGate.ReadScope
    private let provider: any ConnectedServicesProviding
    private let cache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices>
    private var requestID: UUID?
    private var didLoad = false

    private(set) var phase: ConnectedServicesPhase = .idle
    private(set) var refreshMessage: String?

    init(
        account: Account,
        provider: (any ConnectedServicesProviding)? = nil,
        cache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices> = ConnectedServicesCaches.values
    ) {
        self.account = account
        scope = .authenticated(token: account.token)
        self.provider = provider ?? ListenBrainzConnectedServicesProvider(token: account.token)
        self.cache = cache
    }

    init(
        account: Account,
        scope: RequestGate.ReadScope = .isolated(),
        provider: some ConnectedServicesProviding,
        cache: EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices> = ConnectedServicesCaches.values
    ) {
        self.account = account
        self.scope = scope
        self.provider = provider
        self.cache = cache
    }

    func load() async {
        guard requireAuthenticatedAccount() else { return }
        guard !didLoad else { return }
        didLoad = true
        await fetch(refreshing: false)
    }

    func refresh() async {
        guard requireAuthenticatedAccount() else { return }
        didLoad = true
        await fetch(refreshing: true)
    }

    func cancel() {
        requestID = nil
        if phase == .loading {
            phase = .idle
            didLoad = false
        }
    }

    private func fetch(refreshing: Bool) async {
        let key = ConnectedServicesCacheKey(username: account.username, scope: scope)
        var stale: ConnectedServices?
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
            let result = try await provider.connectedServices(username: account.username)
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
                phase = .failed(String(localized: "Your ListenBrainz sign-in needs attention. Sign in again to view connected services."))
                return
            }
            if stale != nil {
                refreshMessage = String(localized: "Couldn’t refresh your connected services. Showing the last saved list.")
            } else {
                phase = .failed(String(localized: "Check your connection and try again."))
            }
        }
    }

    private func requireAuthenticatedAccount() -> Bool {
        guard account.isAuthenticated else {
            refreshMessage = nil
            phase = .failed(String(localized: "Sign in to view the services linked to your ListenBrainz account."))
            return false
        }
        return true
    }

    private func isAuthenticationError(_ error: Error) -> Bool {
        guard let error = error as? LBError else { return false }
        switch error {
        case .invalidAuth, .noToken, .forbidden:
            return true
        default:
            return false
        }
    }
}
