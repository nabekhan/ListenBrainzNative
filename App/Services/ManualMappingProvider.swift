import Foundation
import ListenBrainzKit

protocol ManualMappingProviding: Sendable {
    func submit(msid: UUID, mbid: UUID) async throws
}

protocol ManualMappingTransport: Sendable {
    func submitManualMapping(msid: UUID, mbid: UUID) async throws
}

struct ManualMappingIdentity: Sendable, Equatable {
    let msid: UUID
    let mbid: UUID
}

protocol ManualMappingStatusProviding: Sendable {
    func savedMapping(msid: UUID) async throws -> ManualMappingIdentity?
}

protocol ManualMappingStatusTransport: Sendable {
    func getManualMapping(msid: UUID) async throws -> ManualMappingIdentity
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

struct ListenBrainzManualMappingStatusTransport: ManualMappingStatusTransport {
    private let client: LBClient

    init(token: String) {
        client = LBClient(token: token, userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)")
    }

    func getManualMapping(msid: UUID) async throws -> ManualMappingIdentity {
        let mapping = try await client.metadata.getManualMapping(msid: msid)
        return ManualMappingIdentity(msid: mapping.msid, mbid: mapping.mbid)
    }
}

/// An explicit, coalesced status read. A missing server mapping is a valid
/// result, while every other failure remains visible and is never retried.
struct ManualMappingStatusProvider: ManualMappingStatusProviding {
    private let transport: any ManualMappingStatusTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        transport = ListenBrainzManualMappingStatusTransport(token: token)
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated(),
        transport: some ManualMappingStatusTransport
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func savedMapping(msid: UUID) async throws -> ManualMappingIdentity? {
        do {
            let mapping: ManualMappingIdentity = try await gate.read(
                for: .manualMapping(readScope, msid: msid)
            ) {
                try await transport.getManualMapping(msid: msid)
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            guard mapping.msid == msid else {
                throw ProviderError.manualMappingCheckUnavailable
            }
            return mapping
        } catch LBError.notFound {
            return nil
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.noToken {
            throw ProviderError.invalidToken
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.manualMappingCheckUnavailable
        }
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
