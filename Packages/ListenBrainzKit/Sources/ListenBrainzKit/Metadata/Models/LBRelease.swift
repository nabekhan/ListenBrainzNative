/// Contains metadata for a release group, with other related metadata if requested
public struct LBRelease: Decodable, Sendable {
    /// The single artist credit, and the artists involved in this release group
    public let artist: LBArtist?
    /// Tags for the artist(s) and release group
    public let tag: LBTags?
    /// Metadata for a particular release of this group
    public let release: LBReleaseGroupMeta?
    /// Metadata for this release group
    public let releaseGroup: LBReleaseGroupMeta
}
