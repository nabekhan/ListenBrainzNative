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
    let mode: FeedMode
    /// Feed timestamps are server-side Unix seconds, so cache at that precision.
    let beforeTimestamp: Int?
    let count: Int
}

struct FeedModeState: Equatable {
    var events: [FeedEvent] = []
    var phase: FeedPhase = .idle
    var nextTimestamp: Date?
    var hasMore = false
    var isLoadingMore = false
    var loadMoreError: String?
    var refreshMessage: String?
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

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
