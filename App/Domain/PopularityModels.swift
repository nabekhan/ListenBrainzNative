import Foundation

/// Canonical MusicBrainz entity types supported by ListenBrainz's popularity API.
/// Release and release group deliberately remain separate identities.
enum PopularityEntityKind: String, Hashable, Sendable {
    case artist
    case recording
    case release
    case releaseGroup
}

struct PopularityEntity: Hashable, Sendable {
    let kind: PopularityEntityKind
    let mbid: UUID
}

/// Daily-rebuilt global ListenBrainz context for one canonical entity.
/// `nil` is an unknown/missing value, not a count of zero.
struct GlobalPopularity: Hashable, Sendable {
    let entity: PopularityEntity
    let totalListenCount: Int?
    let totalUserCount: Int?
}
