import Foundation
import ListenBrainzKit

enum GeneratedArtworkRequest: Hashable, Sendable {
    case statistics(
        username: String,
        range: LBStatsArtRange,
        dimension: Int = 3,
        layout: LBArtGridLayout = .one,
        imageSize: Int = 924,
        options: LBArtGridOptions = .nativeDefault
    )
    case artist(
        mbid: UUID,
        dimension: Int = 3,
        layout: LBArtGridLayout = .one,
        imageSize: Int = 924,
        options: LBArtGridOptions = .nativeDefault
    )
    case playlist(
        mbid: UUID,
        dimension: Int,
        layout: LBArtGridLayout
    )

    var scope: GeneratedArtworkScope {
        if case .playlist = self { return .authenticated }
        return .anonymous
    }
}

enum GeneratedArtworkScope: Hashable, Sendable {
    case anonymous
    case authenticated
}

struct GeneratedArtworkDocument: Equatable, Sendable {
    let request: GeneratedArtworkRequest
    let svg: String
}

extension ListeningActivityPeriod {
    var artRange: LBStatsArtRange {
        switch self {
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        case .thisYear: .thisYear
        case .lastWeek: .week
        case .lastMonth: .month
        case .lastYear: .year
        case .allTime: .allTime
        }
    }
}

func playlistArtworkRequest(
    mbid: UUID,
    trackCount: Int
) -> GeneratedArtworkRequest? {
    switch trackCount {
    case 6...:
        .playlist(mbid: mbid, dimension: 3, layout: .one)
    case 4...:
        .playlist(mbid: mbid, dimension: 2, layout: .zero)
    case 1...:
        .playlist(mbid: mbid, dimension: 1, layout: .zero)
    default:
        nil
    }
}
