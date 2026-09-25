import Foundation
import Observation

@MainActor
@Observable
final class FollowingPinsModel {
    let username: String
    private let provider: any FollowingPinsProviding
    private let cache: EntityDetailCache<FollowingPinsPageKey, FollowingPinsPage>
    private let pageSize: Int
    private var requestID: UUID?
    private var didLoad = false

    private(set) var pins: [PinnedRecording] = []
    private(set) var phase: FollowingPinsPhase = .idle
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    private(set) var refreshMessage: String?
    private(set) var loadMoreError: String?
    private var nextOffset = 0

    init(
        username: String,
        provider: (any FollowingPinsProviding)? = nil,
        cache: EntityDetailCache<FollowingPinsPageKey, FollowingPinsPage> = FollowingPinsCaches.pages,
        pageSize: Int = 25
    ) {
        self.username = username
        self.provider = provider ?? ListenBrainzFollowingPinsProvider()
        self.cache = cache
        self.pageSize = max(1, pageSize)
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        await fetch(offset: 0, force: false, appending: false)
    }

    func refresh() async {
        guard !isLoadingMore, phase != .loading else { return }
        didLoad = true
        await fetch(offset: 0, force: true, appending: false)
    }

    func loadMore() async {
        guard phase == .ready, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        await fetch(offset: nextOffset, force: false, appending: true)
    }

    func cancel() {
        requestID = nil
        isLoadingMore = false
        if phase == .loading {
            didLoad = false
            phase = pins.isEmpty ? .idle : .ready
        }
    }

    private func fetch(offset: Int, force: Bool, appending: Bool) async {
        let key = FollowingPinsPageKey(username: username, count: pageSize, offset: offset)
        var hadStale = false
        if !force, let cached = await cache.value(for: key) {
            apply(cached.value, appending: appending)
            if cached.isFresh {
                phase = .ready
                return
            }
            hadStale = !pins.isEmpty
        } else {
            hadStale = !pins.isEmpty
        }
        if !appending {
            phase = pins.isEmpty ? .loading : .ready
            refreshMessage = nil
            loadMoreError = nil
        }
        let id = UUID()
        requestID = id
        do {
            let page = try await provider.page(username: username, count: pageSize, offset: offset)
            try Task.checkCancellation()
            guard requestID == id else { return }
            apply(page, appending: appending)
            phase = .ready
            refreshMessage = nil
            await cache.save(page, for: key)
        } catch is CancellationError {
            guard requestID == id else { return }
            if pins.isEmpty { phase = .idle }
        } catch {
            guard requestID == id else { return }
            if appending { loadMoreError = error.localizedDescription; phase = .ready }
            else if hadStale { refreshMessage = String(localized: "Couldn’t refresh. Showing saved pins."); phase = .ready }
            else { phase = .failed(error.localizedDescription) }
        }
    }

    private func apply(_ page: FollowingPinsPage, appending: Bool) {
        if appending {
            var seen = Set(pins.map(\.followingPinIdentity))
            pins.append(contentsOf: page.pins.filter { seen.insert($0.followingPinIdentity).inserted })
        } else {
            var seen = Set<FollowingPinIdentity>()
            pins = page.pins.filter { seen.insert($0.followingPinIdentity).inserted }
        }
        nextOffset = page.offset + page.serverCount
        hasMore = page.serverCount >= pageSize
        if !hasMore { loadMoreError = nil }
    }

}
