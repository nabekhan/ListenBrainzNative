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
    func thank(username: String, eventType: String, eventID: Int, blurb: String?) async throws
    func setHidden(username: String, eventType: String, eventID: Int, hidden: Bool) async throws
    func deleteEvent(username: String, eventType: String, eventID: Int) async throws
    func deletePin(rowID: Int) async throws
}

extension FeedProviding {
    func thank(username: String, eventType: String, eventID: Int, blurb: String?) async throws {
        throw FeedProviderError.actionUnavailable
    }

    func setHidden(username: String, eventType: String, eventID: Int, hidden: Bool) async throws {
        throw FeedProviderError.actionUnavailable
    }

    func deleteEvent(username: String, eventType: String, eventID: Int) async throws {
        throw FeedProviderError.actionUnavailable
    }

    func deletePin(rowID: Int) async throws {
        throw FeedProviderError.actionUnavailable
    }
}

protocol FeedTransport: Sendable {
    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> LBFeedPage
    func thank(username: String, eventType: String, eventID: Int, blurb: String?) async throws
    func setHidden(username: String, eventType: String, eventID: Int, hidden: Bool) async throws
    func deleteEvent(username: String, eventType: String, eventID: Int) async throws
    func deletePin(rowID: Int) async throws
}

extension FeedTransport {
    func thank(username: String, eventType: String, eventID: Int, blurb: String?) async throws {
        throw FeedProviderError.actionUnavailable
    }

    func setHidden(username: String, eventType: String, eventID: Int, hidden: Bool) async throws {
        throw FeedProviderError.actionUnavailable
    }

    func deleteEvent(username: String, eventType: String, eventID: Int) async throws {
        throw FeedProviderError.actionUnavailable
    }

    func deletePin(rowID: Int) async throws {
        throw FeedProviderError.actionUnavailable
    }
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

    func thank(username: String, eventType: String, eventID: Int, blurb: String?) async throws {
        _ = try await client.feed.thank(
            username: username,
            originalEventType: eventType,
            originalEventID: eventID,
            blurbContent: blurb
        )
    }

    func setHidden(username: String, eventType: String, eventID: Int, hidden: Bool) async throws {
        if hidden {
            _ = try await client.feed.hideEvent(username: username, eventType: eventType, eventID: eventID)
        } else {
            _ = try await client.feed.unhideEvent(username: username, eventType: eventType, eventID: eventID)
        }
    }

    func deleteEvent(username: String, eventType: String, eventID: Int) async throws {
        _ = try await client.feed.deleteEvent(username: username, eventType: eventType, eventID: eventID)
    }

    func deletePin(rowID: Int) async throws {
        _ = try await client.pins.delete(rowID: rowID)
    }
}

struct ListenBrainzFeedProvider: FeedProviding {
    private let transport: any FeedTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        transport = LiveFeedTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        transport: some FeedTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> FeedPage {
        let safeCount = min(max(count, 1), 1_000)
        return try await read(.feedPage(readScope, user: username, mode: mode.rawValue, before: before, minimum: minimumTimestamp, count: safeCount)) {
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

    func thank(username: String, eventType: String, eventID: Int, blurb: String?) async throws {
        let note = blurb?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note?.count ?? 0 <= 280 else { throw FeedProviderError.blurbTooLong }
        try await performAction { try await transport.thank(username: username, eventType: eventType, eventID: eventID, blurb: note?.isEmpty == true ? nil : note) }
    }

    func setHidden(username: String, eventType: String, eventID: Int, hidden: Bool) async throws {
        try await performAction { try await transport.setHidden(username: username, eventType: eventType, eventID: eventID, hidden: hidden) }
    }

    func deleteEvent(username: String, eventType: String, eventID: Int) async throws {
        try await performAction { try await transport.deleteEvent(username: username, eventType: eventType, eventID: eventID) }
    }

    func deletePin(rowID: Int) async throws {
        try await performAction { try await transport.deletePin(rowID: rowID) }
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
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.forbidden, LBError.noToken {
            throw FeedProviderError.invalidAuthentication
        }
    }

    private func performAction<Result: Sendable>(
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
        } catch LBError.noToken {
            throw FeedProviderError.invalidAuthentication
        } catch LBError.forbidden, LBError.badRequest, LBError.invalidParam,
                LBError.notFound, LBError.invalidJSON {
            throw FeedProviderError.actionRejected
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
    case actionUnavailable
    case actionRejected
    case blurbTooLong

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            String(localized: "Your ListenBrainz sign-in is no longer valid. Reconnect your token to open this private feed.")
        case .actionUnavailable:
            String(localized: "This feed action is unavailable right now.")
        case .actionRejected:
            String(localized: "ListenBrainz couldn’t apply this action. It may no longer be available or permitted.")
        case .blurbTooLong:
            String(localized: "A thank-you note can be up to 280 characters.")
        }
    }
}
