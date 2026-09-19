import Foundation
import ListenBrainzKit

protocol TopListenersProviding: Sendable {
    func topListeners(for entity: TopListenersEntity) async throws -> TopListeners?
}

private struct LiveTopListenersTransport: Sendable {
    let client: LBClient

    func topListeners(for entity: TopListenersEntity) async throws -> LBTopListeners? {
        switch entity.kind {
        case .artist:
            try await client.stats.artistListeners(mbid: entity.mbid, range: .allTime)
        case .releaseGroup:
            try await client.stats.releaseGroupListeners(mbid: entity.mbid, range: .allTime)
        }
    }
}

struct ListenBrainzTopListenersProvider: TopListenersProviding {
    private let transport: @Sendable (TopListenersEntity) async throws -> LBTopListeners?
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        let transport = LiveTopListenersTransport(client: LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        ))
        self.transport = { try await transport.topListeners(for: $0) }
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated(),
        transport: @escaping @Sendable (TopListenersEntity) async throws -> LBTopListeners?
    ) {
        self.gate = gate
        self.readScope = readScope
        self.transport = transport
    }

    func topListeners(for entity: TopListenersEntity) async throws -> TopListeners? {
        let response: LBTopListeners? = try await gate.read(
            for: .topListeners(readScope, kind: entity.kind.rawValue, mbid: entity.mbid, range: "all_time")
        ) {
            try await transport(entity)
        } deferralForError: { error in
            guard case let LBError.rateLimited(resetIn) = error else { return nil }
            return .seconds(max(resetIn, 1))
        }
        guard let response else { return nil }
        return TopListeners(
            entity: entity,
            listeners: response.listeners.map { TopListener(username: $0.userName, listenCount: $0.listenCount) },
            totalListenCount: response.totalListenCount
        )
    }
}

enum TopListenersCaches {
    static let values = EntityDetailCache<TopListenersCacheKey, TopListeners>(
        timeToLive: 5 * 60,
        maximumEntryCount: 100
    )
}
