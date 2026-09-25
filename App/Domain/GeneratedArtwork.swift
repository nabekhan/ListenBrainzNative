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
    case custom(
        releaseMBIDs: [UUID],
        dimension: Int,
        layout: LBArtGridLayout,
        imageSize: Int = 924,
        background: LBArtGridBackground = .black,
        captions: Bool = false,
        skipMissing: Bool = false,
        showMissingCoverPlaceholder: Bool = true,
        coverArtSize: LBArtCoverSize = .large
    )

    var scope: GeneratedArtworkScope {
        if case .playlist = self { return .authenticated }
        return .anonymous
    }
}

struct CustomArtworkAlbum: Identifiable, Hashable, Sendable {
    let releaseMBID: UUID
    let title: String
    let artistName: String

    var id: UUID { releaseMBID }

    static func candidates(from releases: [RankedRelease]) -> [Self] {
        var seen: Set<UUID> = []
        return releases.compactMap { release in
            guard let releaseMBID = release.mbid,
                  seen.insert(releaseMBID).inserted
            else {
                return nil
            }
            return Self(
                releaseMBID: releaseMBID,
                title: release.name,
                artistName: release.artistName
            )
        }
    }
}

enum CustomArtworkLayoutPreset: String, CaseIterable, Identifiable, Sendable {
    case single
    case grid2
    case spotlightLeft3
    case spotlightRight3
    case grid3
    case feature4
    case split4
    case centered4
    case grid4
    case feature5

    var id: Self { self }

    var dimension: Int {
        switch self {
        case .single: 1
        case .grid2: 2
        case .spotlightLeft3, .spotlightRight3, .grid3: 3
        case .feature4, .split4, .centered4, .grid4: 4
        case .feature5: 5
        }
    }

    var layout: LBArtGridLayout {
        switch self {
        case .single, .grid2, .grid3, .grid4: .zero
        case .spotlightLeft3, .centered4, .feature5: .one
        case .spotlightRight3, .split4: .two
        case .feature4: .three
        }
    }

    var requiredCoverCount: Int {
        switch self {
        case .single: 1
        case .grid2: 4
        case .spotlightLeft3, .spotlightRight3: 6
        case .grid3: 9
        case .feature4: 8
        case .split4: 10
        case .centered4: 13
        case .grid4: 16
        case .feature5: 11
        }
    }

    static func available(for albumCount: Int) -> [Self] {
        allCases.filter { $0.requiredCoverCount <= albumCount }
    }

    static func preferred(for albumCount: Int) -> Self {
        if albumCount >= 6 { return .spotlightLeft3 }
        if albumCount >= 4 { return .grid2 }
        return .single
    }
}

enum CustomArtworkBackground: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case transparent

    var id: Self { self }

    var artValue: LBArtGridBackground {
        switch self {
        case .dark: .black
        case .light: .white
        case .transparent: .transparent
        }
    }
}

struct CustomArtworkDraft: Equatable, Sendable {
    let availableReleaseMBIDs: [UUID]
    var layout: CustomArtworkLayoutPreset
    var background: CustomArtworkBackground = .dark
    var captions = false
    var selectedReleaseMBIDs: [UUID]

    init(albumIDs: [UUID]) {
        var seen: Set<UUID> = []
        availableReleaseMBIDs = albumIDs.filter { seen.insert($0).inserted }
        layout = .preferred(for: availableReleaseMBIDs.count)
        selectedReleaseMBIDs = Array(
            availableReleaseMBIDs.prefix(layout.requiredCoverCount)
        )
    }

    var availableLayouts: [CustomArtworkLayoutPreset] {
        CustomArtworkLayoutPreset.available(for: availableReleaseMBIDs.count)
    }

    var canGenerate: Bool {
        selectedReleaseMBIDs.count == layout.requiredCoverCount
    }

    var remainingCoverCount: Int {
        max(0, layout.requiredCoverCount - selectedReleaseMBIDs.count)
    }

    mutating func selectLayout(_ value: CustomArtworkLayoutPreset) {
        guard availableLayouts.contains(value) else { return }
        layout = value
        selectedReleaseMBIDs = Array(
            selectedReleaseMBIDs.prefix(value.requiredCoverCount)
        )
        for id in availableReleaseMBIDs
        where selectedReleaseMBIDs.count < value.requiredCoverCount
            && !selectedReleaseMBIDs.contains(id) {
            selectedReleaseMBIDs.append(id)
        }
    }

    mutating func toggle(_ releaseMBID: UUID) {
        guard availableReleaseMBIDs.contains(releaseMBID) else { return }
        if let index = selectedReleaseMBIDs.firstIndex(of: releaseMBID) {
            selectedReleaseMBIDs.remove(at: index)
        } else if selectedReleaseMBIDs.count < layout.requiredCoverCount {
            selectedReleaseMBIDs.append(releaseMBID)
        }
    }

    mutating func moveSelection(
        fromOffsets offsets: IndexSet,
        toOffset destination: Int
    ) {
        let validOffsets = offsets.filter(selectedReleaseMBIDs.indices.contains)
        guard !validOffsets.isEmpty else { return }

        let moving = validOffsets.map { selectedReleaseMBIDs[$0] }
        var remaining = selectedReleaseMBIDs.enumerated().compactMap {
            validOffsets.contains($0.offset) ? nil : $0.element
        }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertion = min(
            max(0, destination - removedBeforeDestination),
            remaining.count
        )
        remaining.insert(contentsOf: moving, at: insertion)
        selectedReleaseMBIDs = remaining
    }

    var request: GeneratedArtworkRequest? {
        guard canGenerate else { return nil }
        return .custom(
            releaseMBIDs: selectedReleaseMBIDs,
            dimension: layout.dimension,
            layout: layout.layout,
            background: background.artValue,
            captions: captions
        )
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
