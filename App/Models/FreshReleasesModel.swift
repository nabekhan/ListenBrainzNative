import Foundation
import Observation

@MainActor
@Observable
final class FreshReleasesModel {
    let account: Account
    private let provider: any ListeningProvider
    private var requestIDs: [FreshReleaseQuery: UUID] = [:]
    private var inFlight: [FreshReleaseQuery: Task<[FreshRelease], Error>] = [:]
    private(set) var states: [FreshReleaseQuery: FreshReleasesLoadState] = [:]

    init(account: Account, provider: (any ListeningProvider)? = nil) {
        self.account = account
        self.provider = provider ?? ListenBrainzProvider(token: account.token)
    }

    func state(for scope: FreshReleaseScope) -> FreshReleasesLoadState {
        state(for: .default(for: scope))
    }

    func state(for query: FreshReleaseQuery) -> FreshReleasesLoadState {
        states[query] ?? .idle
    }

    func isLoading(scope: FreshReleaseScope) -> Bool {
        isLoading(query: .default(for: scope))
    }

    func isLoading(query: FreshReleaseQuery) -> Bool { state(for: query) == .loading }

    func load(scope: FreshReleaseScope, retrying: Bool = false) async {
        await load(query: .default(for: scope), retrying: retrying)
    }

    func load(query: FreshReleaseQuery, retrying: Bool = false) async {
        switch state(for: query) {
        case .loaded:
            return
        case .failed where !retrying:
            return
        case .loading:
            if let task = inFlight[query], let requestID = requestIDs[query] {
                await resolve(task, requestID: requestID, for: query)
            }
            return
        case .idle, .failed:
            states[query] = .loading
        }

        let requestID = UUID()
        requestIDs[query] = requestID
        let provider = provider
        let username = account.username
        let task = Task { try await provider.freshReleases(username: username, query: query) }
        inFlight[query] = task
        await resolve(task, requestID: requestID, for: query)
    }

    func refresh(scope: FreshReleaseScope) async {
        await refresh(query: .default(for: scope))
    }

    func refresh(query: FreshReleaseQuery) async {
        guard !isLoading(query: query) else { return }
        states[query] = .idle
        await load(query: query, retrying: true)
    }

    private func resolve(_ task: Task<[FreshRelease], Error>, requestID: UUID, for query: FreshReleaseQuery) async {
        do {
            let releases = try await task.value
            guard requestIDs[query] == requestID else { return }
            states[query] = .loaded(releases)
            inFlight[query] = nil
            requestIDs[query] = nil
        } catch {
            guard requestIDs[query] == requestID else { return }
            // The request task is owned by the model, not by an individual
            // SwiftUI caller. Always retire its bookkeeping when it ends;
            // otherwise a cancelled waiter can leave this exact query stuck
            // in `.loading` forever.
            states[query] = error is CancellationError ? .idle : .failed(error.localizedDescription)
            inFlight[query] = nil
            requestIDs[query] = nil
        }
    }
}
