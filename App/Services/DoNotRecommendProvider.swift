import Foundation
import ListenBrainzKit

protocol DoNotRecommendProviding: Sendable {
    func entries(username: String, offset: Int, count: Int) async throws -> RecommendationPreferencePage
    func add(entity: RecommendationPreferenceEntity, entityMBID: UUID, until: Date?) async throws
    func remove(entity: RecommendationPreferenceEntity, entityMBID: UUID) async throws
}

extension DoNotRecommendProviding {
    func addRecording(recordingMBID: UUID, until: Date? = nil) async throws {
        try await add(entity: .recording, entityMBID: recordingMBID, until: until)
    }

    func removeRecording(recordingMBID: UUID) async throws {
        try await remove(entity: .recording, entityMBID: recordingMBID)
    }
}

protocol DoNotRecommendTransport: Sendable {
    func entries(username: String, offset: Int, count: Int) async throws -> LBDoNotRecommendPage
    func add(entity: LBDoNotRecommendEntity, entityMBID: UUID, until: Date?) async throws -> LBDoNotRecommendStatus
    func remove(entity: LBDoNotRecommendEntity, entityMBID: UUID) async throws -> LBDoNotRecommendStatus
}

private struct LiveDoNotRecommendTransport: DoNotRecommendTransport {
    /// Listing active preferences is a public endpoint. Keep it deliberately
    /// separate from the authenticated mutation client.
    let publicClient: LBClient
    let mutationClient: LBClient

    func entries(username: String, offset: Int, count: Int) async throws -> LBDoNotRecommendPage {
        try await publicClient.doNotRecommend.entries(user: username, count: count, offset: offset)
    }

    func add(entity: LBDoNotRecommendEntity, entityMBID: UUID, until: Date?) async throws -> LBDoNotRecommendStatus {
        try await mutationClient.doNotRecommend.add(entity: entity, entityMBID: entityMBID, until: until)
    }

    func remove(entity: LBDoNotRecommendEntity, entityMBID: UUID) async throws -> LBDoNotRecommendStatus {
        try await mutationClient.doNotRecommend.remove(entity: entity, entityMBID: entityMBID)
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
        let userAgent = "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        transport = LiveDoNotRecommendTransport(
            publicClient: LBClient(token: "", userAgent: userAgent),
            mutationClient: LBClient(token: token, userAgent: userAgent)
        )
        self.gate = gate
        readScope = .anonymous
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

    func entries(username: String, offset: Int = 0, count: Int = 25) async throws -> RecommendationPreferencePage {
        let safeOffset = max(offset, 0)
        let safeCount = min(max(count, 1), 25)
        let raw = try await read(
            .doNotRecommendEntries(readScope, user: username, offset: safeOffset, count: safeCount)
        ) {
            try await transport.entries(username: username, offset: safeOffset, count: safeCount)
        }
        return try Self.validatedPage(
            raw,
            requestedUsername: username,
            requestedOffset: safeOffset,
            requestedCount: safeCount
        )
    }

    func add(entity: RecommendationPreferenceEntity, entityMBID: UUID, until: Date? = nil) async throws {
        try await mutate {
            let status = try await transport.add(
                entity: entity.listenBrainzValue,
                entityMBID: entityMBID,
                until: until
            )
            guard status.status.lowercased() == "ok" else { throw DoNotRecommendProviderError.invalidMutationResponse }
        }
    }

    func remove(entity: RecommendationPreferenceEntity, entityMBID: UUID) async throws {
        try await mutate {
            let status = try await transport.remove(
                entity: entity.listenBrainzValue,
                entityMBID: entityMBID
            )
            guard status.status.lowercased() == "ok" else { throw DoNotRecommendProviderError.invalidMutationResponse }
        }
    }

    static func validatedPage(
        _ raw: LBDoNotRecommendPage,
        requestedUsername: String,
        requestedOffset: Int,
        requestedCount: Int
    ) throws -> RecommendationPreferencePage {
        let expectedUsername = normalizedUsername(requestedUsername)
        let returnedUsername = normalizedUsername(raw.userID)
        let (nextOffset, overflowed) = raw.offset.addingReportingOverflow(raw.count)

        guard !expectedUsername.isEmpty,
              returnedUsername == expectedUsername,
              raw.offset == requestedOffset,
              raw.offset >= 0,
              raw.count >= 0,
              raw.count == raw.entries.count,
              raw.count <= requestedCount,
              raw.totalCount >= 0,
              !overflowed,
              raw.totalCount >= nextOffset
        else { throw DoNotRecommendProviderError.invalidReadResponse }

        return RecommendationPreferencePage(
            username: requestedUsername,
            items: raw.entries.map {
                RecommendationPreference(
                    entity: $0.entity.preferenceValue,
                    entityMBID: $0.entityMBID,
                    createdAt: $0.created,
                    expiresAt: $0.until
                )
            },
            serverCount: raw.count,
            offset: raw.offset,
            totalCount: raw.totalCount
        )
    }

    private static func normalizedUsername(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
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
            throw DoNotRecommendProviderError.readUnavailable
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
            throw DoNotRecommendProviderError.mutationUnavailable
        }
    }
}

enum DoNotRecommendProviderError: LocalizedError, Equatable, Sendable {
    case invalidAuthentication
    case userNotFound
    case actionRejected
    case invalidReadResponse
    case invalidMutationResponse
    case readUnavailable
    case mutationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            String(localized: "Your ListenBrainz sign-in is no longer valid. Reconnect your token to update this preference.")
        case .userNotFound:
            String(localized: "ListenBrainz couldn’t find this user’s preferences.")
        case .invalidReadResponse, .readUnavailable:
            String(localized: "Couldn’t load recommendation preferences. Try again.")
        case .actionRejected, .invalidMutationResponse, .mutationUnavailable:
            String(localized: "ListenBrainz couldn’t update this preference. Try again.")
        }
    }
}

private extension RecommendationPreferenceEntity {
    var listenBrainzValue: LBDoNotRecommendEntity {
        switch self {
        case .artist: .artist
        case .release: .release
        case .releaseGroup: .releaseGroup
        case .recording: .recording
        }
    }
}

private extension LBDoNotRecommendEntity {
    var preferenceValue: RecommendationPreferenceEntity {
        switch self {
        case .artist: .artist
        case .release: .release
        case .releaseGroup: .releaseGroup
        case .recording: .recording
        }
    }
}

#if DEBUG
struct DoNotRecommendPreviewProvider: DoNotRecommendProviding {
    func entries(username: String, offset: Int, count: Int) async throws -> RecommendationPreferencePage {
        .init(username: username, items: [], serverCount: 0, offset: offset, totalCount: 0)
    }

    func add(entity: RecommendationPreferenceEntity, entityMBID: UUID, until: Date?) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    func remove(entity: RecommendationPreferenceEntity, entityMBID: UUID) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }
}
#endif
