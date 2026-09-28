import Foundation

enum CommunityChartKind: String, CaseIterable, Identifiable, Sendable {
    case artists
    case releaseGroups
    case recordings

    var id: Self { self }

    var title: String {
        switch self {
        case .artists: String(localized: "Artists")
        case .releaseGroups: String(localized: "Albums")
        case .recordings: String(localized: "Tracks")
        }
    }

    var systemImage: String {
        switch self {
        case .artists: "music.mic"
        case .releaseGroups: "square.stack"
        case .recordings: "music.note"
        }
    }
}

struct CommunityChartQuery: Hashable, Sendable {
    let kind: CommunityChartKind
    let period: ListeningActivityPeriod
}

enum CommunityChartItem: Identifiable, Hashable, Sendable {
    case artist(RankedArtist)
    case releaseGroup(RankedReleaseGroup)
    case recording(RankedRecording)

    var id: String {
        switch self {
        case let .artist(value): "artist:\(value.id)"
        case let .releaseGroup(value): "release-group:\(value.id)"
        case let .recording(value): "recording:\(value.id)"
        }
    }

    var title: String {
        switch self {
        case let .artist(value): value.name
        case let .releaseGroup(value): value.name
        case let .recording(value): value.title
        }
    }

    var artistName: String? {
        switch self {
        case .artist: nil
        case let .releaseGroup(value): value.artistName
        case let .recording(value): value.artistName
        }
    }

    var listenCount: Int {
        switch self {
        case let .artist(value): value.listenCount
        case let .releaseGroup(value): value.listenCount
        case let .recording(value): value.listenCount
        }
    }
}

/// One bounded sitewide ranking response. Follow-up requests are possible only
/// when ListenBrainz returns a complete, internally consistent page contract.
struct CommunityChartPage: Equatable, Sendable {
    let items: [CommunityChartItem]
    let offset: Int
    let rawResultCount: Int
    let totalResultCount: Int?
    let nextOffset: Int?
    let lastUpdated: Date?

    init(
        items: [CommunityChartItem],
        offset: Int,
        rawResultCount: Int,
        totalResultCount: Int?,
        lastUpdated: Date?,
        allowsPagination: Bool
    ) {
        let safeOffset = max(offset, 0)
        let safeRawResultCount = max(rawResultCount, 0)
        let safeTotal = totalResultCount.flatMap { $0 >= 0 ? $0 : nil }
        let (candidateOffset, overflowed) = safeOffset.addingReportingOverflow(safeRawResultCount)

        self.items = items
        self.offset = safeOffset
        self.rawResultCount = safeRawResultCount
        self.totalResultCount = safeTotal
        self.lastUpdated = lastUpdated
        if allowsPagination,
           !overflowed,
           safeRawResultCount > 0,
           let safeTotal,
           candidateOffset < safeTotal {
            nextOffset = candidateOffset
        } else {
            nextOffset = nil
        }
    }
}

enum CommunityChartLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
