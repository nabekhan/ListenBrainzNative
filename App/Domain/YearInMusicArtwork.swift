import Foundation
import ListenBrainzKit

/// The explicit options that identify a generated Year in Music image.
/// Usernames are normalized here so visually identical requests share one cache
/// entry and one paced ListenBrainz request.
struct YearInMusicArtworkOptions: Hashable, Sendable {
    let username: String
    let year: Int
    let variant: LBYearInMusicArtVariant
    let anonymous: Bool?

    init(
        username: String,
        year: Int,
        variant: LBYearInMusicArtVariant = .overview,
        anonymous: Bool? = nil
    ) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.year = year
        self.variant = variant
        self.anonymous = anonymous
    }
}

/// A validated raw SVG returned by ListenBrainz. Rendering and sharing remain
/// deliberately separate from fetching so neither can cause a network request.
struct YearInMusicArtwork: Equatable, Sendable {
    let options: YearInMusicArtworkOptions
    let svg: String

    init(options: YearInMusicArtworkOptions, source: LBYearInMusicArtwork) {
        self.options = options
        svg = source.svg
    }
}
