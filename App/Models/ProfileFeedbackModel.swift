import Foundation
import Observation

enum ProfileFeedbackPhase: Equatable {
    case idle
    case loading
    case refreshing
    case ready
    case failed(String)
}

struct ProfileFeedbackCategoryState: Equatable {
    var items: [ProfileFeedbackItem] = []
    var phase: ProfileFeedbackPhase = .idle
    var totalCount = 0
    var nextOffset = 0
    var hasMore = false
    var isLoadingMore = false
    var refreshMessage: String?
    var loadMoreError: String?
}

struct ProfileFeedbackPageKey: Hashable, Sendable {
    let username: String
    let category: ProfileFeedbackCategory
    let offset: Int
    let count: Int
}

enum ProfileFeedbackCaches {
    static let pages = EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage>(
        timeToLive: 10 * 60,
        maximumEntryCount: 100
    )
}

@MainActor
@Observable
final class ProfileFeedbackModel {
    let username: String

    private let provider: any ProfileFeedbackProviding
    private let cache: EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage>
    private let pageSize: Int
    private var requestIDs: [ProfileFeedbackCategory: UUID] = [:]

    private(set) var states: [ProfileFeedbackCategory: ProfileFeedbackCategoryState] = Dictionary(
        uniqueKeysWithValues: ProfileFeedbackCategory.allCases.map { ($0, .init()) }
    )

    init(
        username: String,
        provider: (any ProfileFeedbackProviding)? = nil,
        cache: EntityDetailCache<ProfileFeedbackPageKey, ProfileFeedbackPage> = ProfileFeedbackCaches.pages,
        pageSize: Int = 25
    ) {
        self.username = username
        self.provider = provider ?? ListenBrainzProfileFeedbackProvider()
        self.cache = cache
        self.pageSize = min(max(pageSize, 1), 1_000)
    }

    func state(for category: ProfileFeedbackCategory) -> ProfileFeedbackCategoryState {
        states[category] ?? .init()
    }

    /// Each category loads independently. Opening Loved never spends a second
    /// request on Hated until the listener selects it.
    func load(category: ProfileFeedbackCategory) async {
        guard state(for: category).phase == .idle else { return }
        var current = state(for: category)
        current.phase = .loading
        current.refreshMessage = nil
        current.loadMoreError = nil
        states[category] = current
        await fetch(category: category, offset: 0, force: false, appending: false)
    }

    func refresh(category: ProfileFeedbackCategory) async {
        var current = state(for: category)
        guard current.phase != .loading,
              current.phase != .refreshing,
              !current.isLoadingMore
        else { return }

        requestIDs[category] = UUID()
        current.phase = current.items.isEmpty ? .loading : .refreshing
        current.refreshMessage = nil
        current.loadMoreError = nil
        states[category] = current
        await fetch(category: category, offset: 0, force: true, appending: false)
    }

    func loadMore(category: ProfileFeedbackCategory) async {
        var current = state(for: category)
        guard current.phase == .ready, current.hasMore, !current.isLoadingMore else { return }
        current.isLoadingMore = true
        current.loadMoreError = nil
        states[category] = current
        await fetch(
            category: category,
            offset: current.nextOffset,
            force: false,
            appending: true
        )
    }

    func cancel(category: ProfileFeedbackCategory) {
        requestIDs.removeValue(forKey: category)
        var current = state(for: category)
        current.isLoadingMore = false
        if current.phase == .loading || current.phase == .refreshing {
            current.phase = current.items.isEmpty ? .idle : .ready
        }
        states[category] = current
    }

    func cancelAll() {
        for category in ProfileFeedbackCategory.allCases {
            cancel(category: category)
        }
    }

    private func fetch(
        category: ProfileFeedbackCategory,
        offset: Int,
        force: Bool,
        appending: Bool
    ) async {
        let key = ProfileFeedbackPageKey(
            username: username,
            category: category,
            offset: offset,
            count: pageSize
        )
        var hadStale = !state(for: category).items.isEmpty

        if !force, let cached = await cache.value(for: key) {
            apply(cached.value, to: category, appending: appending)
            if cached.isFresh {
                var current = state(for: category)
                current.phase = .ready
                current.isLoadingMore = false
                states[category] = current
                return
            }
            if !appending {
                var current = state(for: category)
                current.phase = .refreshing
                states[category] = current
            }
            hadStale = !state(for: category).items.isEmpty
        }

        let requestID = UUID()
        requestIDs[category] = requestID
        do {
            let page = try await provider.page(
                username: username,
                category: category,
                offset: offset,
                count: pageSize
            )
            try Task.checkCancellation()
            guard requestIDs[category] == requestID else { return }

            apply(page, to: category, appending: appending)
            var current = state(for: category)
            current.phase = .ready
            current.isLoadingMore = false
            current.refreshMessage = nil
            current.loadMoreError = nil
            states[category] = current
            await cache.save(page, for: key)
        } catch is CancellationError {
            guard requestIDs[category] == requestID else { return }
            var current = state(for: category)
            current.isLoadingMore = false
            current.phase = current.items.isEmpty ? .idle : .ready
            states[category] = current
        } catch {
            guard requestIDs[category] == requestID else { return }
            var current = state(for: category)
            current.isLoadingMore = false
            if appending {
                current.loadMoreError = error.localizedDescription
                current.phase = .ready
            } else if hadStale {
                current.refreshMessage = String(localized: "Couldn’t refresh. Showing saved ratings.")
                current.phase = .ready
            } else {
                current.phase = .failed(error.localizedDescription)
            }
            states[category] = current
        }
    }

    private func apply(
        _ page: ProfileFeedbackPage,
        to category: ProfileFeedbackCategory,
        appending: Bool
    ) {
        guard page.category == category else { return }
        var current = state(for: category)
        current.items = Self.deduplicated(appending ? current.items + page.items : page.items)
        current.nextOffset = page.offset + page.serverCount
        current.totalCount = max(page.totalCount, current.nextOffset)
        current.hasMore = page.serverCount > 0 && current.nextOffset < current.totalCount
        if !current.hasMore {
            current.loadMoreError = nil
        }
        states[category] = current
    }

    private static func deduplicated(_ items: [ProfileFeedbackItem]) -> [ProfileFeedbackItem] {
        var mbids = Set<UUID>()
        var msids = Set<UUID>()
        var result: [ProfileFeedbackItem] = []
        result.reserveCapacity(items.count)

        for item in items {
            let mbid = item.recording.identity.mbid
            let msid = item.recording.identity.msid
            if mbid.map(mbids.contains) == true || msid.map(msids.contains) == true {
                continue
            }
            if let mbid { mbids.insert(mbid) }
            if let msid { msids.insert(msid) }
            result.append(item)
        }
        return result
    }
}
