import Foundation

/// Canonical MusicBrainz entities whose published CritiqueBrainz reviews can
/// be summarized without account access.
enum CritiqueBrainzEntityKind: String, Hashable, Sendable {
    case artist
    case recording
    case releaseGroup = "release_group"
}

struct CritiqueBrainzEntity: Hashable, Sendable {
    let kind: CritiqueBrainzEntityKind
    let mbid: UUID

    var browseURL: URL {
        let path: String
        switch kind {
        case .artist: path = "artist"
        case .recording: path = "recording"
        case .releaseGroup: path = "release-group"
        }
        return URL(string: "https://critiquebrainz.org/\(path)/\(mbid.uuidString.lowercased())")!
    }
}

struct CritiqueBrainzReview: Identifiable, Hashable, Sendable {
    let id: UUID
    let author: String?
    let licenseID: String?
    let licenseURL: URL?
    let rating: Int?
    let text: String?
    let publishedAt: Date?

    var reviewURL: URL {
        URL(string: "https://critiquebrainz.org/review/\(id.uuidString.lowercased())")!
    }

}

struct CritiqueBrainzReviewSummary: Hashable, Sendable {
    let entity: CritiqueBrainzEntity
    let reviews: [CritiqueBrainzReview]
    let averageRating: Double?
    let ratingCount: Int?

    init(
        entity: CritiqueBrainzEntity,
        reviews: [CritiqueBrainzReview],
        averageRating: Double?,
        ratingCount: Int? = nil
    ) {
        self.entity = entity
        self.reviews = reviews
        self.averageRating = averageRating.flatMap { $0.isFinite && (1...5).contains($0) ? $0 : nil }
        self.ratingCount = ratingCount.flatMap { $0 > 0 ? $0 : nil }
    }

    var hasVisibleContent: Bool { !reviews.isEmpty || (averageRating != nil && ratingCount != nil) }
}

struct CritiqueBrainzReviewCacheKey: Hashable, Sendable {
    let entity: CritiqueBrainzEntity
}

enum CritiqueBrainzReviewPhase: Equatable {
    case idle
    case loading
    case loaded(CritiqueBrainzReviewSummary)
    case unavailable
    case failed(String)
}
