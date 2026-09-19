import Foundation
import ListenBrainzKit

protocol ConnectedServicesProviding: Sendable {
    func connectedServices(username: String) async throws -> ConnectedServices
}

struct ListenBrainzConnectedServicesProvider: ConnectedServicesProviding {
    private let transport: @Sendable (String) async throws -> [String]
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        let client = LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        transport = { try await client.core.userServices(username: $0) }
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated(),
        transport: @escaping @Sendable (String) async throws -> [String]
    ) {
        self.gate = gate
        self.readScope = readScope
        self.transport = transport
    }

    func connectedServices(username: String) async throws -> ConnectedServices {
        let identifiers: [String] = try await gate.read(
            for: .connectedServices(readScope, user: username)
        ) {
            try await transport(username)
        } deferralForError: { error in
            guard case let LBError.rateLimited(resetIn) = error else { return nil }
            return .seconds(max(resetIn, 1))
        }
        return ConnectedServices(identifiers: identifiers)
    }
}

enum ConnectedServicesCaches {
    static let values = EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices>(
        timeToLive: 5 * 60,
        maximumEntryCount: 20
    )
}
