import Foundation
import ListenBrainzKit

protocol FeedProviding: Sendable {
    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> FeedPage
}

protocol FeedTransport: Sendable {
    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> LBFeedPage
}

private struct LiveFeedTransport: FeedTransport {
    let client: LBClient

    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> LBFeedPage {
        switch mode {
        case .activity:
            try await client.feed.events(
                username: username,
                count: count,
                maxTimestamp: before,
                minTimestamp: minimumTimestamp
            )
        case .following:
            try await client.feed.followingListens(
                username: username,
                count: count,
                maxTimestamp: before,
                minTimestamp: minimumTimestamp
            )
        case .similar:
            try await client.feed.similarListens(
                username: username,
                count: count,
                maxTimestamp: before,
                minTimestamp: minimumTimestamp
            )
        }
    }
}

struct ListenBrainzFeedProvider: FeedProviding {
    private let transport: any FeedTransport
    private let gate: RequestGate

    init(token: String, gate: RequestGate = .shared) {
        transport = LiveFeedTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
    }

    init(transport: some FeedTransport, gate: RequestGate) {
        self.transport = transport
        self.gate = gate
    }

    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> FeedPage {
        let safeCount = min(max(count, 1), 1_000)
        return try await perform {
            let source = try await transport.page(
                username: username,
                mode: mode,
                before: before,
                minimumTimestamp: minimumTimestamp,
                count: safeCount
            )
            return Self.map(source)
        }
    }

    private func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await gate.perform(operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth {
            throw FeedProviderError.invalidAuthentication
        } catch LBError.forbidden {
            throw FeedProviderError.invalidAuthentication
        } catch LBError.noToken {
            throw FeedProviderError.invalidAuthentication
        }
    }

    private static func map(_ page: LBFeedPage) -> FeedPage {
        FeedPage(
            username: page.userID,
            serverCount: page.count,
            events: page.events.map(map)
        )
    }

    private static func map(_ event: LBFeedEvent) -> FeedEvent {
        let metadata = event.metadata
        let msid = metadata.recordingMsid ?? metadata.trackMetadata?.additionalInfo?.recordingMsid
        return FeedEvent(
            serverID: event.id,
            kind: .init(eventType: event.eventType),
            userName: event.userName,
            created: event.created,
            hidden: event.hidden,
            similarity: event.similarity,
            recording: metadata.trackMetadata.map { ListenBrainzProvider.map($0, msid: msid) },
            blurb: metadata.blurbContent,
            users: metadata.users ?? [],
            userName0: metadata.userName0,
            userName1: metadata.userName1,
            relationshipType: metadata.relationshipType,
            message: metadata.message,
            entityName: metadata.entityName,
            entityID: metadata.entityID,
            entityType: metadata.entityType,
            rating: metadata.rating,
            text: metadata.text,
            reviewMBID: metadata.reviewMBID,
            originalEventID: metadata.originalEventID,
            originalEventType: metadata.originalEventType,
            thankerUsername: metadata.thankerUsername,
            thankeeUsername: metadata.thankeeUsername
        )
    }
}

enum FeedProviderError: LocalizedError {
    case invalidAuthentication

    var errorDescription: String? {
        "Your ListenBrainz sign-in is no longer valid. Reconnect your token to open this private feed."
    }
}
