import Foundation
import ListenBrainzKit

protocol ManualMappingProviding: Sendable {
    func submit(msid: UUID, mbid: UUID) async throws
}

protocol ManualMappingTransport: Sendable {
    func submitManualMapping(msid: UUID, mbid: UUID) async throws
}

struct ListenBrainzManualMappingTransport: ManualMappingTransport {
    private let client: LBClient

    init(token: String) {
        client = LBClient(token: token, userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)")
    }

    func submitManualMapping(msid: UUID, mbid: UUID) async throws {
        try await client.metadata.submitManualMapping(msid: msid, mbid: mbid)
    }
}

/// A one-shot mapping writer. It deliberately has no read, retry, or refresh API:
/// a transport that started cannot prove whether a cancellation reached the server.
struct ManualMappingProvider: ManualMappingProviding {
    private let transport: any ManualMappingTransport
    private let gate: RequestGate

    init(token: String, gate: RequestGate = .shared) {
        transport = ListenBrainzManualMappingTransport(token: token)
        self.gate = gate
    }

    init(gate: RequestGate, transport: some ManualMappingTransport) {
        self.transport = transport
        self.gate = gate
    }

    func submit(msid: UUID, mbid: UUID) async throws {
        let attempt = ManualMappingAttemptState()
        do {
            try await gate.perform {
                await attempt.markTransportStarted()
                try await transport.submitManualMapping(msid: msid, mbid: mbid)
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch let error as LBError {
            switch error {
            case .invalidAuth, .noToken: throw ProviderError.invalidToken
            case .invalidJSON, .invalidParam, .badRequest, .forbidden, .notFound:
                throw ProviderError.manualMappingRejected
            case .invalidResponse, .noContent, .unknownError:
                throw ProviderError.manualMappingOutcomeUnknown
            case .rateLimited:
                throw error
            }
        } catch is CancellationError {
            guard await attempt.didStartTransport else { throw CancellationError() }
            throw ProviderError.manualMappingOutcomeUnknown
        } catch {
            // Once the request has entered its transport, no local error can
            // distinguish a rejected request from a response lost in transit.
            throw ProviderError.manualMappingOutcomeUnknown
        }
    }
}

private actor ManualMappingAttemptState {
    private(set) var didStartTransport = false

    func markTransportStarted() {
        didStartTransport = true
    }
}
