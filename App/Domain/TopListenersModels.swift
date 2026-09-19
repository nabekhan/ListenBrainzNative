import Foundation

enum TopListenersEntityKind: String, Hashable, Sendable {
    case artist
    case releaseGroup = "release-group"
}

struct TopListenersEntity: Hashable, Sendable {
    let kind: TopListenersEntityKind
    let mbid: UUID
}

struct TopListener: Identifiable, Hashable, Sendable {
    let username: String
    let listenCount: Int

    var id: String { username.lowercased() }
    var user: SearchUser { SearchUser(username: username) }
}

/// The server returns a small ranked sample, not every listener for an entity.
struct TopListeners: Hashable, Sendable {
    let entity: TopListenersEntity
    let listeners: [TopListener]
    let totalListenCount: Int?

    init(entity: TopListenersEntity, listeners: [TopListener], totalListenCount: Int?) {
        self.entity = entity
        self.listeners = Self.normalized(listeners)
        self.totalListenCount = totalListenCount.flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func normalized(_ rows: [TopListener]) -> [TopListener] {
        var bestByUser: [String: TopListener] = [:]
        for row in rows {
            let username = row.username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty, row.listenCount >= 0 else { continue }
            let normalized = TopListener(username: username, listenCount: row.listenCount)
            let key = normalized.id
            if bestByUser[key].map(\.listenCount) ?? -1 < normalized.listenCount {
                bestByUser[key] = normalized
            }
        }
        return bestByUser.values.sorted {
            $0.listenCount == $1.listenCount ? $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending : $0.listenCount > $1.listenCount
        }
    }
}

struct TopListenersCacheKey: Hashable, Sendable {
    let entity: TopListenersEntity
    let scope: RequestGate.ReadScope
    /// The first native surface deliberately requests the all-time range.
    let range: String = "all_time"
}

enum TopListenersPhase: Equatable {
    case idle
    case loading
    case loaded(TopListeners)
    case unavailable
    case failed(String)
}
