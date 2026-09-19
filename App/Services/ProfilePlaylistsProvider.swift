import Foundation
import ListenBrainzKit

enum ProfilePlaylistCategory: String, CaseIterable, Hashable, Sendable {
    case owned
    case collaborating
}

/// A metadata-only page from either of the playlist categories shown on a
/// listener profile. Deliberately does not contain playlist tracks: those are
/// fetched only after a user opens a playlist.
struct ProfilePlaylistPage: Equatable, Sendable {
    let username: String
    let category: ProfilePlaylistCategory
    let playlists: [SearchPlaylist]
    let requestedCount: Int?
    let offset: Int?
    let totalCount: Int?
}

protocol ProfilePlaylistsProviding: Sendable {
    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage

    /// A canonical read that must start after the caller requests it. Mutation
    /// recovery uses this instead of joining an equivalent read that may have
    /// begun before the mutation was dispatched.
    func freshPage(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage
}

extension ProfilePlaylistsProviding {
    func freshPage(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        try await page(username: username, category: category, offset: offset, count: count)
    }
}

protocol ProfilePlaylistsTransport: Sendable {
    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> LBPlaylistPage
}

private struct LiveProfilePlaylistsTransport: ProfilePlaylistsTransport {
    let client: LBClient

    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> LBPlaylistPage {
        switch category {
        case .owned:
            try await client.core.userPlaylistsPage(username: username, count: count, offset: offset)
        case .collaborating:
            try await client.core.userPlaylistsCollaboratorPage(username: username, count: count, offset: offset)
        }
    }
}

struct ListenBrainzProfilePlaylistsProvider: ProfilePlaylistsProviding {
    private let transport: any ProfilePlaylistsTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        transport = LiveProfilePlaylistsTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        transport: some ProfilePlaylistsTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func page(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        let safeOffset = max(offset, 0)
        let safeCount = min(max(count, 1), 100)
        do {
            return try await gate.read(
                for: .profilePlaylists(
                    readScope, user: username, category: category.rawValue, offset: safeOffset, count: safeCount)
            ) {
                let source = try await transport.page(
                    username: username,
                    category: category,
                    offset: safeOffset,
                    count: safeCount
                )
                return Self.map(source, username: username, category: category)
            } deferralForError: { error in
                guard case LBError.rateLimited(let resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.forbidden, LBError.noToken {
            throw ProfilePlaylistsProviderError.invalidAuthentication
        } catch LBError.notFound {
            throw ProfilePlaylistsProviderError.profileUnavailable
        }
    }

    func freshPage(
        username: String,
        category: ProfilePlaylistCategory,
        offset: Int,
        count: Int
    ) async throws -> ProfilePlaylistPage {
        let safeOffset = max(offset, 0)
        let safeCount = min(max(count, 1), 100)
        do {
            return try await gate.perform {
                let source = try await transport.page(
                    username: username,
                    category: category,
                    offset: safeOffset,
                    count: safeCount
                )
                return Self.map(source, username: username, category: category)
            } deferralForError: { error in
                guard case LBError.rateLimited(let resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.invalidAuth, LBError.forbidden, LBError.noToken {
            throw ProfilePlaylistsProviderError.invalidAuthentication
        } catch LBError.notFound {
            throw ProfilePlaylistsProviderError.profileUnavailable
        }
    }

    private static func map(
        _ source: LBPlaylistPage,
        username: String,
        category: ProfilePlaylistCategory
    ) -> ProfilePlaylistPage {
        .init(
            username: username,
            category: category,
            playlists: source.playlists.map {
                SearchPlaylist(
                    title: $0.title,
                    creator: $0.creator,
                    annotation: $0.annotation,
                    identifier: $0.identifier,
                    isPublic: $0.isPublic,
                    lastModifiedAt: $0.lastModifiedAt,
                    createdAt: $0.date,
                    durationMilliseconds: $0.duration,
                    createdFor: $0.createdFor,
                    collaborators: $0.collaborators ?? [],
                    copiedFrom: $0.copiedFrom,
                    recommendationType: $0.recommendationType,
                    expiresAt: $0.expiresAt
                )
            },
            requestedCount: source.requestedCount,
            offset: source.offset,
            totalCount: source.playlistCount
        )
    }
}

enum ProfilePlaylistsProviderError: LocalizedError {
    case invalidAuthentication
    case profileUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            "Your ListenBrainz sign-in is no longer valid. Reconnect your token to view private playlists."
        case .profileUnavailable:
            "ListenBrainz could not find playlists for this listener."
        }
    }
}
