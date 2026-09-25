import Foundation
import ListenBrainzKit

protocol SocialProviding: Sendable {
    func followers(of username: String) async throws -> [SearchUser]
    func following(of username: String) async throws -> [SearchUser]
    func similarUsers(to username: String) async throws -> [SimilarListener]
    func compatibility(between viewer: String, and username: String) async throws -> Double?
    func follow(username: String) async throws
    func unfollow(username: String) async throws
}

struct ListenBrainzSocialProvider: SocialProviding {
    private let client: LBClient
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        client = LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    func followers(of username: String) async throws -> [SearchUser] {
        try await read(.socialFollowers(readScope, user: username)) {
            try await client.social.followers(username: username).map(SearchUser.init)
        }
    }

    func following(of username: String) async throws -> [SearchUser] {
        try await read(.socialFollowing(readScope, user: username)) {
            try await client.social.following(username: username).map(SearchUser.init)
        }
    }

    func similarUsers(to username: String) async throws -> [SimilarListener] {
        try await read(.similarUsers(readScope, user: username)) {
            try await client.core.userSimilarUsers(username: username).map {
                SimilarListener(user: SearchUser(username: $0.userName), similarity: $0.similarity)
            }
        }
    }

    func compatibility(between viewer: String, and username: String) async throws -> Double? {
        do {
            return try await read(.compatibility(readScope, viewer: viewer, user: username)) {
                try await client.core.userSimilarTo(username: viewer, other: username).similarity
            }
        } catch LBError.notFound {
            return nil
        }
    }

    func follow(username: String) async throws {
        do {
            _ = try await perform { try await client.social.follow(username: username) }
        } catch LBError.badRequest {
            throw SocialProviderError.followRejected
        } catch LBError.invalidAuth {
            throw SocialProviderError.invalidAuthentication
        }
    }

    func unfollow(username: String) async throws {
        do {
            _ = try await perform { try await client.social.unfollow(username: username) }
        } catch LBError.invalidAuth {
            throw SocialProviderError.invalidAuthentication
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
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }
}

enum SocialProviderError: LocalizedError {
    case followRejected
    case invalidAuthentication

    var errorDescription: String? {
        switch self {
        case .followRejected:
            String(localized: "ListenBrainz could not follow this listener. The relationship may already exist.")
        case .invalidAuthentication:
            String(localized: "Your ListenBrainz token no longer authorizes social changes.")
        }
    }
}
