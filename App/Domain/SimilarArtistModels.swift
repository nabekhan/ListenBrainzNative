import Foundation

struct SimilarArtist: Identifiable, Hashable, Sendable {
    let mbid: UUID
    let name: String
    let score: Double?

    var id: UUID { mbid }
    var rankedArtist: RankedArtist {
        RankedArtist(mbid: mbid, name: name, listenCount: 0)
    }
}

/// The small, server-ranked shelf returned with ListenBrainz's public artist page.
struct SimilarArtists: Hashable, Sendable {
    static let maximumCount = 18

    let sourceArtistMBID: UUID
    let artists: [SimilarArtist]

    init(sourceArtistMBID: UUID, artists: [SimilarArtist]) {
        self.sourceArtistMBID = sourceArtistMBID

        var seen: Set<UUID> = [sourceArtistMBID]
        self.artists = artists.compactMap { artist in
            guard seen.insert(artist.mbid).inserted else { return nil }
            let trimmedName = artist.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            return SimilarArtist(
                mbid: artist.mbid,
                name: String(trimmedName.prefix(500)),
                score: artist.score.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            )
        }
        .prefix(Self.maximumCount)
        .map { $0 }
    }

    var hasVisibleContent: Bool { !artists.isEmpty }
}

struct SimilarArtistsCacheKey: Hashable, Sendable {
    let artistMBID: UUID
}

enum SimilarArtistsPhase: Equatable {
    case idle
    case loading
    case loaded(SimilarArtists)
    case unavailable
    case failed(String)
}
