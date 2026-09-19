import Foundation

/// The useful, bounded artist context embedded in ListenBrainz's current
/// website/official-client artist response.
struct ArtistPageContext: Hashable, Sendable {
    let artistMBID: UUID
    let highlights: ArtistHighlights
    let similarArtists: SimilarArtists?
}

struct ArtistHighlights: Hashable, Sendable {
    static let maximumRecordingCount = 10
    static let maximumReleaseGroupCount = 10

    let artistMBID: UUID
    let recordings: [ArtistPopularRecording]
    let releaseGroups: [ArtistPopularReleaseGroup]

    var hasVisibleContent: Bool {
        !recordings.isEmpty || !releaseGroups.isEmpty
    }
}

struct ArtistPopularRecording: Identifiable, Hashable, Sendable {
    let recordingMBID: UUID
    let title: String
    let artistName: String
    let artistMBIDs: [UUID]
    let releaseTitle: String?
    let releaseMBID: UUID?
    let artworkReleaseMBID: UUID?
    let durationMilliseconds: Int?
    let totalListenCount: Int?
    let totalUserCount: Int?

    var id: UUID { recordingMBID }

    var recording: Recording {
        Recording(
            identity: .init(mbid: recordingMBID, msid: nil),
            title: title,
            artistName: artistName,
            artistMBIDs: artistMBIDs,
            releaseTitle: releaseTitle,
            releaseMBID: releaseMBID,
            releaseGroupMBID: nil,
            artworkReleaseMBID: artworkReleaseMBID ?? releaseMBID,
            durationMilliseconds: durationMilliseconds,
            source: nil
        )
    }

    var artworkURL: URL? { recording.artworkURL }
}

struct ArtistPopularReleaseGroup: Identifiable, Hashable, Sendable {
    let mbid: UUID
    let title: String
    let artistName: String
    let primaryType: String?
    let firstReleaseDate: String?
    let artworkReleaseMBID: UUID?
    let totalListenCount: Int?
    let totalUserCount: Int?

    var id: UUID { mbid }

    var releaseGroup: SearchReleaseGroup {
        SearchReleaseGroup(
            mbid: mbid,
            title: title,
            artistName: artistName,
            primaryType: primaryType,
            firstReleaseDate: firstReleaseDate
        )
    }

    var artworkURL: URL? {
        artworkReleaseMBID.map(CoverArtArchiveURL.release)
            ?? CoverArtArchiveURL.releaseGroup(mbid)
    }
}

enum ArtistHighlightsSelection: String, CaseIterable, Identifiable, Sendable {
    case tracks
    case releases

    var id: Self { self }
    var title: String { self == .tracks ? "Tracks" : "Releases" }
}

enum ArtistHighlightsPhase: Equatable {
    case idle
    case loading
    case loaded(ArtistHighlights)
    case unavailable
    case failed(String)
}
