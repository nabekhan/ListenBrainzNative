import Foundation
import Observation

@MainActor
@Observable
final class PinsModel {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }

    let account: Account
    private let provider: any PinProviding
    private(set) var currentPin: PinnedRecording?
    private(set) var history: [PinnedRecording] = []
    private(set) var totalCount = 0
    private(set) var phase: Phase = .idle
    private(set) var historyPhase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var isMutating = false
    var actionError: String?
    private var didLoadCurrent = false
    private var didLoadHistory = false
    private var isRefreshingCurrent = false
    private var isRefreshingHistory = false

    init(account: Account, provider: (any PinProviding)? = nil) {
        self.account = account
        self.provider = provider ?? ListenBrainzPinProvider(token: account.token)
    }

    var canLoadMore: Bool { history.count < totalCount }
    var canMutate: Bool { !isMutating && !isRefreshingCurrent && !isRefreshingHistory && !isLoadingMore }

    func load() async {
        guard !didLoadCurrent else { return }
        didLoadCurrent = true
        await refreshCurrent()
    }

    func refresh() async {
        await refreshCurrent()
        if didLoadHistory {
            await refreshHistory()
        }
    }

    /// Refreshes only the current pin. Pin history stays lazy unless its own
    /// screen explicitly asks for it.
    func refreshCurrent() async {
        guard !isRefreshingCurrent, !isMutating else { return }
        isRefreshingCurrent = true
        defer { isRefreshingCurrent = false }
        phase = .loading
        do {
            let newCurrent = try await provider.currentPin(username: account.username)
            currentPin = newCurrent
            if didLoadHistory {
                history = markCurrent(history, current: newCurrent)
            }
            phase = .ready
        } catch is CancellationError {
            didLoadCurrent = false
            phase = currentPin == nil ? .idle : .ready
        } catch {
            if currentPin == nil {
                phase = .failed(error.localizedDescription)
            } else {
                phase = .ready
                actionError = error.localizedDescription
            }
        }
    }

    func loadHistory() async {
        guard !didLoadHistory else { return }
        didLoadHistory = true
        await refreshHistory()
    }

    func refreshHistory() async {
        guard !isRefreshingHistory, !isMutating else { return }
        isRefreshingHistory = true
        defer { isRefreshingHistory = false }
        historyPhase = .loading
        do {
            let firstPage = try await provider.pinHistory(username: account.username, count: 20, offset: 0)
            history = markCurrent(firstPage.pins, current: currentPin)
            totalCount = firstPage.totalCount
            historyPhase = .ready
        } catch is CancellationError {
            didLoadHistory = false
            historyPhase = history.isEmpty ? .idle : .ready
        } catch {
            historyPhase = history.isEmpty ? .failed(error.localizedDescription) : .ready
            actionError = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoadingMore, !isRefreshingHistory, !isMutating, canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await provider.pinHistory(username: account.username, count: 20, offset: history.count)
            let seen = Set(history.map(\.rowID))
            history.append(contentsOf: markCurrent(page.pins, current: currentPin).filter { !seen.contains($0.rowID) })
            totalCount = page.totalCount
        } catch is CancellationError {
            return
        } catch { actionError = error.localizedDescription }
    }

    func pin(_ recording: Recording, blurb: String?) async {
        guard account.isAuthenticated else { actionError = String(localized: "Sign in with a token to pin recordings."); return }
        guard blurb.map(\.count) ?? 0 <= 280 else { actionError = String(localized: "A pin note can be up to 280 characters."); return }
        guard canMutate else { return }
        isMutating = true
        defer { isMutating = false }
        let previousCurrent = currentPin
        let previousHistory = history
        let temporary = PinnedRecording(
            rowID: Int.min,
            created: .now,
            pinnedUntil: nil,
            blurb: blurb?.isEmpty == true ? nil : blurb,
            username: account.username,
            recording: recording,
            isCurrent: true
        )
        currentPin = temporary
        if didLoadHistory { history = markCurrent(history, current: temporary) }
        do {
            let newPin = try await provider.pin(recording, blurb: blurb)
            currentPin = newPin
            if didLoadHistory {
                history = markCurrent(history, current: newPin)
                if !history.contains(where: { $0.rowID == newPin.rowID }) {
                    history.insert(newPin, at: 0)
                    totalCount += 1
                }
            }
        } catch {
            currentPin = previousCurrent
            history = previousHistory
            actionError = error.localizedDescription
        }
    }

    func unpin() async {
        guard account.isAuthenticated, let previous = currentPin, canMutate else { return }
        isMutating = true
        defer { isMutating = false }
        currentPin = nil
        if didLoadHistory { history = markCurrent(history, current: nil) }
        do { try await provider.unpin() } catch {
            currentPin = previous
            if didLoadHistory { history = markCurrent(history, current: previous) }
            actionError = error.localizedDescription
        }
    }

    func updateBlurb(for pin: PinnedRecording, to blurb: String) async {
        guard account.isAuthenticated else { actionError = String(localized: "Sign in with a token to edit your pin."); return }
        guard blurb.count <= 280 else { actionError = String(localized: "A pin note can be up to 280 characters."); return }
        guard canMutate else { return }
        isMutating = true
        defer { isMutating = false }
        let previousCurrent = currentPin
        let previousHistory = history
        applyBlurb(blurb, rowID: pin.rowID)
        do { try await provider.updatePinBlurb(rowID: pin.rowID, blurb: blurb) } catch {
            currentPin = previousCurrent; history = previousHistory; actionError = error.localizedDescription
        }
    }

    func delete(_ pin: PinnedRecording) async {
        guard account.isAuthenticated else { actionError = String(localized: "Sign in with a token to delete pins."); return }
        guard canMutate else { return }
        isMutating = true
        defer { isMutating = false }
        let previousCurrent = currentPin
        let previousHistory = history
        let previousTotalCount = totalCount
        history.removeAll { $0.rowID == pin.rowID }
        if currentPin?.rowID == pin.rowID { currentPin = nil }
        totalCount = max(0, totalCount - 1)
        do { try await provider.deletePin(rowID: pin.rowID) } catch {
            currentPin = previousCurrent
            history = previousHistory
            totalCount = previousTotalCount
            actionError = error.localizedDescription
        }
    }

    private func markCurrent(_ pins: [PinnedRecording], current: PinnedRecording?) -> [PinnedRecording] {
        pins.map { pin in
            PinnedRecording(rowID: pin.rowID, created: pin.created, pinnedUntil: pin.pinnedUntil, blurb: pin.blurb, username: pin.username, recording: pin.recording, isCurrent: pin.rowID == current?.rowID)
        }
    }

    private func applyBlurb(_ blurb: String, rowID: Int) {
        func changed(_ pin: PinnedRecording) -> PinnedRecording {
            PinnedRecording(rowID: pin.rowID, created: pin.created, pinnedUntil: pin.pinnedUntil, blurb: blurb, username: pin.username, recording: pin.recording, isCurrent: pin.isCurrent)
        }
        if currentPin?.rowID == rowID, let currentPin { self.currentPin = changed(currentPin) }
        history = history.map { $0.rowID == rowID ? changed($0) : $0 }
    }
}
