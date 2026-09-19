import Foundation
import ListenBrainzKit

protocol FollowingPinsProviding: Sendable {
    func page(username: String, count: Int, offset: Int) async throws -> FollowingPinsPage
}

private struct LiveFollowingPinsTransport: Sendable {
    let client: LBClient
    func page(username: String, count: Int, offset: Int) async throws -> LBFollowingPinsPage {
        try await client.pins.following(user: username, count: count, offset: offset)
    }
}

struct ListenBrainzFollowingPinsProvider: FollowingPinsProviding {
    private let transport: @Sendable (String, Int, Int) async throws -> LBFollowingPinsPage
    private let gate: RequestGate

    init(gate: RequestGate = .shared) {
        let transport = LiveFollowingPinsTransport(client: LBClient(
            token: "",
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        ))
        self.transport = { try await transport.page(username: $0, count: $1, offset: $2) }
        self.gate = gate
    }

    init(
        gate: RequestGate,
        transport: @escaping @Sendable (String, Int, Int) async throws -> LBFollowingPinsPage
    ) {
        self.gate = gate
        self.transport = transport
    }

    func page(username: String, count: Int, offset: Int) async throws -> FollowingPinsPage {
        let safeCount = min(max(count, 1), 1_000)
        let safeOffset = max(offset, 0)
        do {
            let source: LBFollowingPinsPage = try await gate.read(
                for: .followingPins(.anonymous, user: username, count: safeCount, offset: safeOffset)
            ) {
                try await transport(username, safeCount, safeOffset)
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            return FollowingPinsPage(
                username: source.userName ?? username,
                pins: source.pinnedRecordings.prefix(safeCount).map { ListenBrainzPinProvider.mapFollowing($0) },
                serverCount: min(max(0, source.count), safeCount),
                offset: safeOffset
            )
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }
}

extension ListenBrainzPinProvider {
    static func mapFollowing(_ pin: LBPinnedRecording) -> PinnedRecording {
        map(pin, isCurrent: true)
    }
}
