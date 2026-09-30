import Foundation
import ListenBrainzKit

protocol PlaylistServiceImportProviding: Sendable {
    func playlists(from service: PlaylistExternalService) async throws -> PlaylistServiceImportList
    func importPlaylist(_ playlist: PlaylistServiceImportItem) async throws -> UUID
}

protocol PlaylistServiceImportTransport: Sendable {
    func spotifyPlaylists() async throws -> LBSpotifyPlaylistImportList
    func importSpotifyPlaylist(id: String) async throws -> UUID
}

private struct LivePlaylistServiceImportTransport: PlaylistServiceImportTransport {
    let client: LBClient

    func spotifyPlaylists() async throws -> LBSpotifyPlaylistImportList {
        try await client.core.spotifyPlaylistsForImport()
    }

    func importSpotifyPlaylist(id: String) async throws -> UUID {
        try await client.core.importSpotifyPlaylist(spotifyPlaylistID: id)
    }
}

/// A bounded read plus one-shot mutation boundary for service imports.
///
/// The Spotify import endpoint is named as a GET but creates a ListenBrainz
/// playlist and has no idempotency key. Once transport starts, every failure
/// is therefore indeterminate and must never be retried automatically.
struct ListenBrainzPlaylistServiceImportProvider: PlaylistServiceImportProviding {
    private let transport: any PlaylistServiceImportTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        transport = LivePlaylistServiceImportTransport(client: LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        ))
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        transport: some PlaylistServiceImportTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func playlists(from service: PlaylistExternalService) async throws -> PlaylistServiceImportList {
        guard service == .spotify else {
            throw PlaylistServiceImportProviderError.unsupportedService
        }
        let result: LBSpotifyPlaylistImportList = try await gate.read(
            for: .playlistServiceImportList(readScope, service: service.rawValue)
        ) {
            try await transport.spotifyPlaylists()
        } deferralForError: { error in
            guard case let LBError.rateLimited(resetIn) = error else { return nil }
            return .seconds(max(resetIn, 1))
        }
        return PlaylistServiceImportList(
            service: .spotify,
            playlists: result.playlists.map(Self.map),
            isTruncated: result.isTruncated
        )
    }

    func importPlaylist(_ playlist: PlaylistServiceImportItem) async throws -> UUID {
        guard playlist.service == .spotify else {
            throw PlaylistServiceImportProviderError.unsupportedService
        }
        guard Self.isSafeSpotifyIdentifier(playlist.externalID) else {
            throw PlaylistServiceImportProviderError.invalidPlaylistIdentifier
        }

        let attempt = MutationAttemptState()
        do {
            return try await gate.perform({
                await attempt.markTransportStarted()
                return try await transport.importSpotifyPlaylist(id: playlist.externalID)
            }) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch {
            guard await attempt.didStartTransport else {
                if error is CancellationError {
                    throw PlaylistServiceImportProviderError.cancelledBeforeTransport
                }
                if let error = error as? URLError, error.code == .cancelled {
                    throw PlaylistServiceImportProviderError.cancelledBeforeTransport
                }
                throw error
            }
            throw PlaylistServiceImportProviderError.indeterminateImport
        }
    }

    private static func map(_ source: LBSpotifyPlaylistSummary) -> PlaylistServiceImportItem {
        let boundedTitle = bounded(source.title, maximumCharacters: 256)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PlaylistServiceImportItem(
            service: .spotify,
            externalID: source.id,
            title: boundedTitle.isEmpty
                ? String(localized: "Untitled Spotify playlist")
                : boundedTitle,
            summary: boundedOptional(source.description, maximumCharacters: 500),
            artworkURL: source.artworkURL,
            ownerName: boundedOptional(source.ownerName, maximumCharacters: 128),
            trackCount: source.trackCount.flatMap { (0...10_000).contains($0) ? $0 : nil },
            isPublic: source.isPublic,
            isCollaborative: source.isCollaborative
        )
    }

    private static func bounded(_ value: String, maximumCharacters: Int) -> String {
        String(value.prefix(maximumCharacters))
    }

    private static func boundedOptional(_ value: String?, maximumCharacters: Int) -> String? {
        guard let value else { return nil }
        let bounded = bounded(value, maximumCharacters: maximumCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.isEmpty ? nil : bounded
    }

    private static func isSafeSpotifyIdentifier(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122)
        }
    }

    private actor MutationAttemptState {
        private(set) var didStartTransport = false

        func markTransportStarted() {
            didStartTransport = true
        }
    }
}

enum PlaylistServiceImportProviderError: Error, Equatable, Sendable {
    case unsupportedService
    case invalidPlaylistIdentifier
    case cancelledBeforeTransport
    case indeterminateImport
}

enum PlaylistServiceImportCaches {
    static let values = EntityDetailCache<PlaylistServiceImportCacheKey, PlaylistServiceImportList>(
        timeToLive: 10 * 60,
        maximumEntryCount: 20
    )
}
