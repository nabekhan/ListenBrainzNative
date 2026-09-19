import Foundation
import ListenBrainzKit

protocol ReleaseDetailProviding: Sendable {
    func releaseGroup(mbid: UUID) async throws -> ReleaseGroupDetail?
}

protocol ConcreteReleaseDetailProviding: Sendable {
    func release(seed: ReleaseSeed) async throws -> ReleaseDetail
}

protocol PlaylistDetailProviding: Sendable {
    func playlist(mbid: UUID) async throws -> PlaylistDetail
}

struct ListenBrainzMediaDetailProvider: ReleaseDetailProviding, PlaylistDetailProviding {
    private let client: LBClient
    private let gate: RequestGate

    init(token: String, gate: RequestGate = .shared) {
        self.client = LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        self.gate = gate
    }

    func releaseGroup(mbid: UUID) async throws -> ReleaseGroupDetail? {
        try await perform {
            guard let value = try await client.metadata.releaseGroup(
                mbid: mbid,
                including: [LBMetaInclusion.artist, .tag]
            ) else { return nil }

            let artists = value.artist?.artists.map {
                RankedArtist(mbid: $0.id, name: $0.name, listenCount: 0)
            } ?? []
            var seenTags = Set<String>()
            let tags = (value.tag?.releaseGroup ?? [])
                .sorted { $0.voteCount > $1.voteCount }
                .compactMap { tag -> String? in
                    let trimmed = tag.tag.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    let key = trimmed.lowercased()
                    guard seenTags.insert(key).inserted else { return nil }
                    return trimmed
                }
            return ReleaseGroupDetail(
                mbid: mbid,
                title: value.releaseGroup.name,
                artistCreditName: value.artist?.name ?? "",
                artists: artists,
                releaseDate: value.releaseGroup.dateString,
                primaryType: value.releaseGroup.type?.rawValue,
                tags: tags,
                artworkReleaseMBID: value.releaseGroup.caaReleaseMbid
            )
        }
    }

    func playlist(mbid: UUID) async throws -> PlaylistDetail {
        do {
            return try await perform {
                let value = try await client.core.playlist(mbid: mbid)
                let metadata = value.metadata
                let tracks = value.tracks.enumerated().map { index, track in
                    let title = Self.nonempty(track.title) ?? "Unknown recording"
                    let artist = Self.nonempty(track.artistCreditName) ?? "Unknown artist"
                    let recording = Recording(
                        identity: .init(mbid: track.recordingMBID, msid: nil),
                        title: title,
                        artistName: artist,
                        artistMBIDs: track.artistMBIDs,
                        releaseTitle: Self.nonempty(track.releaseName),
                        releaseMBID: track.releaseMBID,
                        releaseGroupMBID: nil,
                        artworkReleaseMBID: track.caaReleaseMBID ?? track.releaseMBID,
                        durationMilliseconds: track.durationMilliseconds,
                        source: nil
                    )
                    return PlaylistTrack(
                        position: index + 1,
                        recording: recording,
                        addedAt: track.addedAt,
                        addedBy: Self.nonempty(track.addedBy)
                    )
                }
                return PlaylistDetail(
                    mbid: value.mbid,
                    title: metadata.title,
                    creator: metadata.creator,
                    annotation: Self.nonempty(metadata.annotation),
                    createdAt: metadata.date,
                    lastModifiedAt: metadata.lastModifiedAt,
                    isPublic: metadata.isPublic,
                    createdFor: Self.nonempty(metadata.createdFor),
                    collaborators: metadata.collaborators ?? [],
                    copiedFrom: Self.nonempty(metadata.copiedFrom),
                    tracks: tracks
                )
            }
        } catch LBError.notFound, LBError.forbidden {
            throw MediaDetailError.playlistUnavailable
        } catch LBError.invalidAuth, LBError.noToken {
            throw ProviderError.invalidToken
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

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct MusicBrainzReleaseDetailProvider: ConcreteReleaseDetailProviding {
    private let client: MusicBrainzSearchClient

    init(client: MusicBrainzSearchClient = .init()) {
        self.client = client
    }

    func release(seed: ReleaseSeed) async throws -> ReleaseDetail {
        try await client.release(mbid: seed.mbid, context: seed)
    }
}

enum MediaDetailError: LocalizedError, Sendable {
    case invalidPlaylistIdentifier
    case playlistUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPlaylistIdentifier:
            "This result does not contain a valid ListenBrainz playlist ID."
        case .playlistUnavailable:
            "This playlist is private, was removed, or is no longer available."
        }
    }
}

/// Access failures must not preserve previously cached private playlist data.
/// Transport/offline/rate-limit failures remain eligible for stale display.
enum PlaylistAccessFailurePolicy {
    static func reason(for error: any Error) -> PlaylistAccessLossReason? {
        if let error = error as? MediaDetailError {
            if case .playlistUnavailable = error { return .sourceVisibility }
        }
        if let error = error as? ProviderError {
            if case .invalidToken = error { return .authentication }
        }
        if let error = error as? ProfilePlaylistsProviderError {
            switch error {
            case .invalidAuthentication: return .authentication
            case .profileUnavailable: return .sourceVisibility
            }
        }
        if let error = error as? PlaylistMutationProviderError {
            switch error {
            case .invalidAuthentication: return .authentication
            case .notCollaborator, .playlistUnavailable: return .sourceVisibility
            default: return nil
            }
        }
        return nil
    }

    static func requiresPurge(_ error: any Error) -> Bool {
        reason(for: error) != nil
    }
}
