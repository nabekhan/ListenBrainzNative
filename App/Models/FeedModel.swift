import Foundation
import Observation

enum FeedPhase: Equatable {
    case idle
    case loading
    case refreshing
    case ready
    case requiresAuthentication
    case failed(String)
}

struct FeedPageKey: Hashable, Sendable {
    let username: String
    let scope: RequestGate.ReadScope
    let mode: FeedMode
    /// Feed timestamps are server-side Unix seconds, so cache at that precision.
    let beforeTimestamp: Int?
    let count: Int

    init(
        username: String,
        scope: RequestGate.ReadScope,
        mode: FeedMode,
        beforeTimestamp: Int?,
        count: Int
    ) {
        self.username = username
        self.scope = scope
        self.mode = mode
        self.beforeTimestamp = beforeTimestamp
        self.count = count
    }
}

struct FeedModeState: Equatable {
    var events: [FeedEvent] = []
    var phase: FeedPhase = .idle
    var nextTimestamp: Date?
    var hasMore = false
    var isLoadingMore = false
    var loadMoreError: String?
    var refreshMessage: String?
    var pendingEventIDs: Set<String> = []
    var thankedEventIDs: Set<String> = []
}

struct FeedActionAlert: Identifiable {
    enum Kind: Equatable { case confirmation, error }
    let kind: Kind
    let message: String
    let id = UUID()
}

private struct RemovedFeedEvent {
    let event: FeedEvent
    let previousID: String?
    let nextID: String?
}

enum FeedCaches {
    static let pages = EntityDetailCache<FeedPageKey, FeedPage>(
        timeToLive: 5 * 60,
        maximumEntryCount: 100
    )
}

@MainActor
@Observable
final class FeedModel {
    let account: Account

    private let provider: any FeedProviding
    private let cache: EntityDetailCache<FeedPageKey, FeedPage>
    private let activityPageSize: Int
    private let listeningPageSize: Int
    private let now: @Sendable () -> Date

    private(set) var states: [FeedMode: FeedModeState] = Dictionary(
        uniqueKeysWithValues: FeedMode.allCases.map { ($0, FeedModeState()) }
    )

    private var requestIDs: [FeedMode: UUID] = [:]
    private var minimumTimestamps: [FeedMode: Date] = [:]
    var actionAlert: FeedActionAlert?

    init(
        account: Account,
        provider: (any FeedProviding)? = nil,
        cache: EntityDetailCache<FeedPageKey, FeedPage> = FeedCaches.pages,
        activityPageSize: Int = 25,
        listeningPageSize: Int = 40,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzFeedProvider(token: account.token)
        self.cache = cache
        self.activityPageSize = max(1, activityPageSize)
        self.listeningPageSize = max(1, listeningPageSize)
        self.now = now
    }

    func state(for mode: FeedMode) -> FeedModeState {
        states[mode] ?? FeedModeState()
    }

    func load(mode: FeedMode) async {
        guard account.isAuthenticated else {
            setRequiresAuthentication(for: mode)
            return
        }
        guard state(for: mode).phase == .idle else { return }
        await fetch(mode: mode, before: nil, force: false, appending: false)
    }

    func refresh(mode: FeedMode) async {
        guard account.isAuthenticated else {
            setRequiresAuthentication(for: mode)
            return
        }
        let current = state(for: mode)
        guard !current.isLoadingMore,
              current.phase != .loading,
              current.phase != .refreshing
        else { return }
        await fetch(mode: mode, before: nil, force: true, appending: false)
    }

    func loadMore(mode: FeedMode) async {
        guard account.isAuthenticated else {
            setRequiresAuthentication(for: mode)
            return
        }
        var current = state(for: mode)
        guard current.phase == .ready,
              current.hasMore,
              !current.isLoadingMore,
              let before = current.nextTimestamp
        else { return }

        current.isLoadingMore = true
        current.loadMoreError = nil
        states[mode] = current
        defer {
            var state = state(for: mode)
            state.isLoadingMore = false
            states[mode] = state
        }
        await fetch(mode: mode, before: before, force: false, appending: true)
    }

    func canThank(_ event: FeedEvent, in mode: FeedMode) -> Bool {
        mode == .activity && !event.hidden && !isOwner(event) && event.supportsThank
    }

    func canHide(_ event: FeedEvent, in mode: FeedMode) -> Bool {
        guard mode == .activity, event.supportsHide else { return false }
        if event.kind == .notification { return isOwner(event) }
        return !isOwner(event)
    }

    func canDelete(_ event: FeedEvent, in mode: FeedMode) -> Bool {
        mode == .activity && isOwner(event) && (event.supportsGenericDelete || event.supportsPinDelete)
    }

    func isPending(_ event: FeedEvent, in mode: FeedMode) -> Bool {
        state(for: mode).pendingEventIDs.contains(event.id)
    }

    func hasThanked(_ event: FeedEvent, in mode: FeedMode) -> Bool {
        state(for: mode).thankedEventIDs.contains(event.id)
    }

    @discardableResult
    func thank(_ event: FeedEvent, in mode: FeedMode, blurb: String?) async -> Bool {
        guard canThank(event, in: mode), let serverID = event.serverID,
              beginAction(event, in: mode)
        else { return false }
        defer { endAction(event, in: mode) }
        do {
            try await provider.thank(username: account.username, eventType: event.kind.rawValue, eventID: serverID, blurb: blurb)
            if eventStillExists(event, in: mode) {
                var state = state(for: mode)
                state.thankedEventIDs.insert(event.id)
                states[mode] = state
            }
            actionAlert = .init(kind: .confirmation, message: "Thank-you sent.")
            await cache.removeAll()
            return true
        } catch {
            actionAlert = .init(kind: .error, message: error.localizedDescription)
            return false
        }
    }

    func setHidden(_ event: FeedEvent, in mode: FeedMode, hidden: Bool) async {
        guard canHide(event, in: mode), let serverID = event.serverID,
              beginAction(event, in: mode)
        else { return }
        setHiddenLocally(event, in: mode, hidden: hidden)
        defer { endAction(event, in: mode) }
        do {
            try await provider.setHidden(username: account.username, eventType: event.kind.rawValue, eventID: serverID, hidden: hidden)
            await cache.removeAll()
        } catch {
            setHiddenLocally(event, in: mode, hidden: !hidden)
            actionAlert = .init(kind: .error, message: error.localizedDescription)
        }
    }

    func delete(_ event: FeedEvent, in mode: FeedMode) async {
        guard canDelete(event, in: mode), let serverID = event.serverID,
              beginAction(event, in: mode)
        else { return }
        let removed = removeLocally(event, in: mode)
        defer { endAction(event, in: mode) }
        do {
            if event.supportsPinDelete {
                try await provider.deletePin(rowID: serverID)
            } else {
                try await provider.deleteEvent(username: account.username, eventType: event.kind.rawValue, eventID: serverID)
            }
            await cache.removeAll()
        } catch {
            restore(removed, in: mode)
            actionAlert = .init(kind: .error, message: error.localizedDescription)
        }
    }

    private func fetch(
        mode: FeedMode,
        before: Date?,
        force: Bool,
        appending: Bool
    ) async {
        let count = pageSize(for: mode)
        let minimumTimestamp = minimumTimestamp(
            for: mode,
            resetting: force && !appending && before == nil
        )
        let key = FeedPageKey(
            username: Self.normalized(account.username),
            scope: .authenticated(token: account.token),
            mode: mode,
            beforeTimestamp: before.map { Int($0.timeIntervalSince1970) },
            count: count
        )

        if !force, let cached = await cache.value(for: key) {
            apply(cached.value, mode: mode, requestedBefore: before, appending: appending)
            if cached.isFresh {
                var ready = state(for: mode)
                ready.phase = .ready
                states[mode] = ready
                return
            }
        }

        var current = state(for: mode)
        if appending {
            // The tail stays usable while an older page is requested.
            current.phase = .ready
        } else {
            current.phase = current.events.isEmpty ? .loading : .refreshing
            current.refreshMessage = nil
        }
        states[mode] = current

        let requestID = UUID()
        requestIDs[mode] = requestID
        do {
            let page = try await provider.page(
                username: account.username,
                mode: mode,
                before: before,
                minimumTimestamp: minimumTimestamp,
                count: count
            )
            try Task.checkCancellation()
            guard requestIDs[mode] == requestID else { return }
            apply(page, mode: mode, requestedBefore: before, appending: appending)
            var completed = state(for: mode)
            completed.phase = .ready
            completed.refreshMessage = nil
            states[mode] = completed
            await cache.save(page, for: key)
        } catch is CancellationError {
            guard requestIDs[mode] == requestID else { return }
            var cancelled = state(for: mode)
            cancelled.phase = cancelled.events.isEmpty ? .idle : .ready
            states[mode] = cancelled
        } catch {
            guard requestIDs[mode] == requestID else { return }
            var failed = state(for: mode)
            if appending {
                failed.loadMoreError = error.localizedDescription
                failed.phase = .ready
            } else if failed.events.isEmpty {
                failed.phase = .failed(error.localizedDescription)
            } else {
                failed.refreshMessage = error.localizedDescription
                failed.phase = .ready
            }
            states[mode] = failed
        }
    }

    private func apply(
        _ page: FeedPage,
        mode: FeedMode,
        requestedBefore: Date?,
        appending: Bool
    ) {
        var state = state(for: mode)
        let pageOldest = page.oldestCreated
        let cursorStrictlyAdvanced = requestedBefore.map { cursor in
            pageOldest.map { $0 < cursor } ?? false
        } ?? true

        // `max_ts` is strict and second-granular. A non-decreasing page would
        // otherwise keep requesting the same boundary forever, so preserve the
        // visible tail and stop rather than appending an ambiguous page.
        guard !appending || cursorStrictlyAdvanced else {
            state.hasMore = false
            state.loadMoreError = nil
            states[mode] = state
            return
        }

        if appending {
            var seen = Set(state.events.map(\.id))
            state.events.append(contentsOf: page.events.filter { seen.insert($0.id).inserted })
        } else {
            state.events = deduplicated(page.events)
        }

        state.nextTimestamp = pageOldest
        state.hasMore = page.serverCount >= pageSize(for: mode)
            && pageOldest != nil
            && cursorStrictlyAdvanced
        if !state.hasMore { state.loadMoreError = nil }
        states[mode] = state
    }

    private func deduplicated(_ events: [FeedEvent]) -> [FeedEvent] {
        var seen = Set<String>()
        return events.filter { seen.insert($0.id).inserted }
    }

    private func pageSize(for mode: FeedMode) -> Int {
        mode == .activity ? activityPageSize : listeningPageSize
    }

    private func minimumTimestamp(for mode: FeedMode, resetting: Bool) -> Date? {
        guard mode != .activity else { return nil }
        if resetting || minimumTimestamps[mode] == nil {
            minimumTimestamps[mode] = now().addingTimeInterval(-7 * 24 * 60 * 60)
        }
        return minimumTimestamps[mode]
    }

    private func setRequiresAuthentication(for mode: FeedMode) {
        var state = state(for: mode)
        state.phase = .requiresAuthentication
        state.hasMore = false
        state.isLoadingMore = false
        states[mode] = state
    }

    private func beginAction(_ event: FeedEvent, in mode: FeedMode) -> Bool {
        var state = state(for: mode)
        guard !state.pendingEventIDs.contains(event.id) else { return false }
        state.pendingEventIDs.insert(event.id)
        states[mode] = state
        return true
    }

    private func endAction(_ event: FeedEvent, in mode: FeedMode) {
        var state = state(for: mode)
        state.pendingEventIDs.remove(event.id)
        states[mode] = state
    }

    private func eventStillExists(_ event: FeedEvent, in mode: FeedMode) -> Bool {
        state(for: mode).events.contains { $0.id == event.id }
    }

    private func setHiddenLocally(_ event: FeedEvent, in mode: FeedMode, hidden: Bool) {
        var state = state(for: mode)
        guard let index = state.events.firstIndex(where: { $0.id == event.id }) else { return }
        let current = state.events[index]
        state.events[index] = FeedEvent(
            serverID: current.serverID,
            kind: current.kind,
            userName: current.userName,
            created: current.created,
            hidden: hidden,
            similarity: current.similarity,
            recording: current.recording,
            blurb: current.blurb,
            users: current.users,
            userName0: current.userName0,
            userName1: current.userName1,
            relationshipType: current.relationshipType,
            message: current.message,
            entityName: current.entityName,
            entityID: current.entityID,
            entityType: current.entityType,
            rating: current.rating,
            text: current.text,
            reviewMBID: current.reviewMBID,
            originalEventID: current.originalEventID,
            originalEventType: current.originalEventType,
            thankerUsername: current.thankerUsername,
            thankeeUsername: current.thankeeUsername
        )
        states[mode] = state
    }

    @discardableResult
    private func removeLocally(_ event: FeedEvent, in mode: FeedMode) -> RemovedFeedEvent? {
        var state = state(for: mode)
        guard let index = state.events.firstIndex(where: { $0.id == event.id }) else { return nil }
        let removed = RemovedFeedEvent(
            event: state.events[index],
            previousID: index > 0 ? state.events[index - 1].id : nil,
            nextID: index + 1 < state.events.count ? state.events[index + 1].id : nil
        )
        state.events.remove(at: index)
        states[mode] = state
        return removed
    }

    private func restore(_ removed: RemovedFeedEvent?, in mode: FeedMode) {
        guard let removed else { return }
        var state = state(for: mode)
        guard !state.events.contains(where: { $0.id == removed.event.id }) else { return }
        if let next = removed.nextID,
           let nextIndex = state.events.firstIndex(where: { $0.id == next }) {
            state.events.insert(removed.event, at: nextIndex)
        } else if let previous = removed.previousID,
                  let previousIndex = state.events.firstIndex(where: { $0.id == previous }) {
            state.events.insert(removed.event, at: previousIndex + 1)
        } else {
            state.events.append(removed.event)
        }
        states[mode] = state
    }

    private func isOwner(_ event: FeedEvent) -> Bool {
        Self.normalized(event.userName) == Self.normalized(account.username)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
