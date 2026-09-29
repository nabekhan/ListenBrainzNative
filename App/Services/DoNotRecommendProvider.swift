import Foundation
import ListenBrainzKit

protocol DoNotRecommendProviding: Sendable {
    func entries(username: String, offset: Int, count: Int) async throws -> LBDoNotRecommendPage
    func addRecording(recordingMBID: UUID) async throws
    func removeRecording(recordingMBID: UUID) async throws
}

protocol DoNotRecommendTransport: Sendable {
    func entries(username: String, offset: Int, count: Int) async throws -> LBDoNotRecommendPage
    func add(entity: LBDoNotRecommendEntity, entityMBID: UUID) async throws -> LBDoNotRecommendStatus
    func remove(entity: LBDoNotRecommendEntity, entityMBID: UUID) async throws -> LBDoNotRecommendStatus
}

private struct LiveDoNotRecommendTransport: DoNotRecommendTransport {
    let client: LBClient

    func entries(username: String, offset: Int, count: Int) async throws -> LBDoNotRecommendPage {
        try await client.doNotRecommend.entries(user: username, count: count, offset: offset)
    }

    func add(entity: LBDoNotRecommendEntity, entityMBID: UUID) async throws -> LBDoNotRecommendStatus {
        try await client.doNotRecommend.add(entity: entity, entityMBID: entityMBID)
    }

    func remove(entity: LBDoNotRecommendEntity, entityMBID: UUID) async throws -> LBDoNotRecommendStatus {
        try await client.doNotRecommend.remove(entity: entity, entityMBID: entityMBID)
    }
}

/// A narrow boundary for ListenBrainz do-not-recommend preferences.
///
/// It intentionally does not join `ListeningProvider`: this preference is
/// neither recording feedback nor recommendation feedback, and UI callers may
/// avoid its paginated read entirely when they only need an explicit action.
struct ListenBrainzDoNotRecommendProvider: DoNotRecommendProviding {
    private let transport: any DoNotRecommendTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        transport = LiveDoNotRecommendTransport(client: LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        ))
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        transport: some DoNotRecommendTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func entries(username: String, offset: Int = 0, count: Int = 25) async throws -> LBDoNotRecommendPage {
        let safeOffset = max(offset, 0)
        let safeCount = min(max(count, 0), 1_000)
        return try await read(
            .doNotRecommendEntries(readScope, user: username, offset: safeOffset, count: safeCount)
        ) {
            try await transport.entries(username: username, offset: safeOffset, count: safeCount)
        }
    }

    func addRecording(recordingMBID: UUID) async throws {
        try await mutate {
            let status = try await transport.add(entity: .recording, entityMBID: recordingMBID)
            guard status.status.lowercased() == "ok" else { throw DoNotRecommendProviderError.invalidMutationResponse }
        }
    }

    func removeRecording(recordingMBID: UUID) async throws {
        try await mutate {
            let status = try await transport.remove(entity: .recording, entityMBID: recordingMBID)
            guard status.status.lowercased() == "ok" else { throw DoNotRecommendProviderError.invalidMutationResponse }
        }
    }

    private func read<Result: Sendable>(
        _ key: RequestGate.ReadKey,
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await gate.read(for: key, operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch LBError.invalidAuth, LBError.noToken, LBError.forbidden {
            throw DoNotRecommendProviderError.invalidAuthentication
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.notFound {
            throw DoNotRecommendProviderError.userNotFound
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CancellationError {
            throw error
        } catch let error as DoNotRecommendProviderError {
            throw error
        } catch {
            throw DoNotRecommendProviderError.unavailable
        }
    }

    private func mutate(
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        do {
            try await gate.perform(operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch LBError.invalidAuth, LBError.noToken, LBError.forbidden {
            throw DoNotRecommendProviderError.invalidAuthentication
        } catch LBError.badRequest, LBError.invalidParam, LBError.invalidJSON, LBError.notFound {
            throw DoNotRecommendProviderError.actionRejected
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CancellationError {
            throw error
        } catch let error as DoNotRecommendProviderError {
            throw error
        } catch {
            throw DoNotRecommendProviderError.unavailable
        }
    }
}

enum DoNotRecommendProviderError: LocalizedError, Equatable {
    case invalidAuthentication
    case userNotFound
    case actionRejected
    case invalidMutationResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            String(localized: "Your ListenBrainz sign-in is no longer valid. Reconnect your token to update this preference.")
        case .userNotFound:
            String(localized: "ListenBrainz couldn’t find this user’s preferences.")
        case .actionRejected, .invalidMutationResponse, .unavailable:
            String(localized: "ListenBrainz couldn’t update this preference. Try again.")
        }
    }
}

#if DEBUG
struct DoNotRecommendPreviewProvider: DoNotRecommendProviding {
    func entries(username: String, offset: Int, count: Int) async throws -> LBDoNotRecommendPage {
        .init(entries: [], totalCount: 0, count: 0, offset: offset, userID: username)
    }

    func addRecording(recordingMBID: UUID) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    func removeRecording(recordingMBID: UUID) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }
}
#endif
