import Foundation
import Observation

struct LinkListensCacheKey: Hashable, Sendable {
    let username: String
}

enum LinkListensCaches {
    /// ListenBrainz currently rebuilds this source weekly. A short memory cache
    /// prevents repeated Settings navigation from re-reading the same data,
    /// while pull to refresh always remains available.
    static let pages = EntityDetailCache<LinkListensCacheKey, LinkListensPage>(
        timeToLive: 30 * 60,
        maximumEntryCount: 12
    )
}

@MainActor
@Observable
final class LinkListensModel {
    enum Phase: Equatable {
        case idle
        case loading
        case refreshing
        case loaded
        case failed(String)
    }

    let account: Account
    private let provider: any LinkListensProviding
    private let cache: EntityDetailCache<LinkListensCacheKey, LinkListensPage>
    private var requestID: UUID?

    private(set) var phase: Phase = .idle
    private(set) var page = LinkListensPage(
        listens: [],
        totalDataCount: 0,
        lastUpdated: nil
    )
    private(set) var refreshMessage: String?

    init(
        account: Account,
        provider: (any LinkListensProviding)? = nil,
        cache: EntityDetailCache<LinkListensCacheKey, LinkListensPage> = LinkListensCaches.pages
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzLinkListensProvider()
        self.cache = cache
    }

    var groups: [LinkListensGroup] { LinkListensGroup.make(from: page.listens) }
    var retainedCount: Int { page.listens.count }
    var isBusy: Bool { phase == .loading || phase == .refreshing }

    func load() async {
        guard phase == .idle else { return }
        let key = cacheKey
        if let cached = await cache.value(for: key) {
            page = cached.value
            phase = cached.isFresh ? .loaded : .refreshing
            guard !cached.isFresh else { return }
        } else {
            phase = .loading
        }
        await fetch(key: key)
    }

    func refresh() async {
        guard !isBusy else { return }
        phase = retainedCount == 0 ? .loading : .refreshing
        refreshMessage = nil
        await fetch(key: cacheKey)
    }

    func cancel() {
        requestID = nil
        if isBusy {
            phase = retainedCount == 0 ? .idle : .loaded
        }
    }

    func removeMapped(msid: UUID) async {
        let previousCount = page.listens.count
        let remaining = page.listens.filter { $0.recording.identity.msid != msid }
        guard remaining.count != previousCount else { return }
        let removedSourceRows = max(page.sourceRowCounts[msid] ?? 1, 1)
        var remainingSourceRowCounts = page.sourceRowCounts
        remainingSourceRowCounts.removeValue(forKey: msid)

        page = .init(
            listens: remaining,
            totalDataCount: max(page.totalDataCount - removedSourceRows, remaining.count),
            lastUpdated: page.lastUpdated,
            sourceRowCounts: remainingSourceRowCounts
        )
        refreshMessage = nil
        await cache.save(page, for: cacheKey)
    }

    private var cacheKey: LinkListensCacheKey {
        .init(username: account.username)
    }

    private func fetch(key: LinkListensCacheKey) async {
        let currentRequestID = UUID()
        requestID = currentRequestID
        do {
            let loaded = try await provider.unmatchedListens(username: account.username)
            try Task.checkCancellation()
            guard requestID == currentRequestID else { return }

            page = loaded
            phase = .loaded
            refreshMessage = nil
            requestID = nil
            await cache.save(loaded, for: key)
        } catch is CancellationError {
            guard requestID == currentRequestID else { return }
            requestID = nil
            phase = retainedCount == 0 ? .idle : .loaded
        } catch {
            guard requestID == currentRequestID else { return }
            requestID = nil
            if retainedCount == 0 {
                phase = .failed(error.localizedDescription)
            } else {
                phase = .loaded
                refreshMessage = String(
                    localized: "Couldn’t refresh unmatched listens. Showing the previous list."
                )
            }
        }
    }
}

struct LinkListensGroup: Identifiable, Hashable {
    private struct Key: Hashable {
        let title: String
        let artistName: String
    }

    let title: String
    let artistName: String
    let listens: [Listen]

    var id: String { "\(artistName)\u{0}\(title)" }

    static func make(from listens: [Listen]) -> [Self] {
        Dictionary(grouping: listens) {
            Key(
                title: $0.recording.releaseTitle?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty ?? String(localized: "No release"),
                artistName: $0.recording.artistName
            )
        }
        .map {
            .init(
                title: $0.key.title,
                artistName: $0.key.artistName,
                listens: $0.value.sorted { $0.listenedAt > $1.listenedAt }
            )
        }
        .sorted {
            let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
