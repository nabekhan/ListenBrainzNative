import Foundation
import ListenBrainzKit

/// The presentation-neutral subset of ListenBrainz's annual report used by the
/// native retrospective.  It deliberately keeps release-group and release
/// identities separate: a Year in Music "album" is a release group, while a
/// recording may point at one concrete release for artwork.
struct YearInMusicReport: Hashable, Sendable {
    enum Source: Hashable, Sendable { case current, archive }

    let username: String?
    let year: Int
    let source: Source
    let totals: Totals
    let listeningDays: [ListeningDay]
    let topArtists: [RankedArtist]
    /// Releases that ListenBrainz identifies as new work from this listener's
    /// top artists. This is a discovery list, not a ranked listening chart.
    let newReleasesOfTopArtists: [NewRelease]
    let topReleaseGroups: [ReleaseGroup]
    let topReleases: [Release]
    let topRecordings: [TopRecording]
    /// Read-only annual playlist snapshots embedded in the Year in Music
    /// aggregate. They never imply that the canonical playlist was loaded.
    let annualPlaylists: [AnnualPlaylistSnapshot]
    /// The weekday ListenBrainz identifies as the user's most active music day.
    let mostActiveWeekday: Weekday?
    /// ListenBrainz genre tags, retained as display-only labels rather than
    /// treated as a canonical genre taxonomy.
    let topGenres: [Genre]
    /// Release-year listening grouped into decades. These are release dates,
    /// not the dates on which the user listened.
    let releaseDecades: [ReleaseDecade]
    /// The server-calculated top artists in each month of this report year.
    /// This is intentionally presentation-neutral so it can reuse the native
    /// artist-evolution chart without issuing a second statistics request.
    let artistEvolution: ArtistEvolutionActivity?

    var isEmpty: Bool {
        totals.listenCount == 0
            && listeningDays.allSatisfy { $0.listenCount == 0 }
            && topArtists.isEmpty
            && newReleasesOfTopArtists.isEmpty
            && topReleaseGroups.isEmpty
            && topReleases.isEmpty
            && topRecordings.isEmpty
            && annualPlaylists.isEmpty
            && !totals.hasNewArtistCount
            && mostActiveWeekday == nil
            && topGenres.isEmpty
            && releaseDecades.isEmpty
            && (artistEvolution?.isEmpty ?? true)
    }

    var hasIdentityContent: Bool {
        totals.hasNewArtistCount
            || mostActiveWeekday != nil
            || !topGenres.isEmpty
            || !releaseDecades.isEmpty
    }

    struct Totals: Hashable, Sendable {
        let listenCount: Int
        let artistCount: Int
        let recordingCount: Int
        let releaseGroupCount: Int
        let newArtistCount: Int
        /// ListenBrainz reports seconds, potentially with fractional values.
        let listeningTime: TimeInterval
        /// `false` means this archive did not provide the metric; its numeric
        /// storage value must never be presented as a zero.
        let hasArtistCount: Bool
        let hasRecordingCount: Bool
        let hasReleaseCount: Bool
        let hasListeningTime: Bool
        let hasNewArtistCount: Bool

        init(
            listenCount: Int,
            artistCount: Int,
            recordingCount: Int,
            releaseGroupCount: Int,
            newArtistCount: Int,
            listeningTime: TimeInterval,
            hasArtistCount: Bool = true,
            hasRecordingCount: Bool = true,
            hasReleaseCount: Bool = true,
            hasListeningTime: Bool = true,
            hasNewArtistCount: Bool = true
        ) {
            self.listenCount = listenCount; self.artistCount = artistCount
            self.recordingCount = recordingCount; self.releaseGroupCount = releaseGroupCount
            self.newArtistCount = newArtistCount; self.listeningTime = listeningTime
            self.hasArtistCount = hasArtistCount; self.hasRecordingCount = hasRecordingCount
            self.hasReleaseCount = hasReleaseCount; self.hasListeningTime = hasListeningTime
            self.hasNewArtistCount = hasNewArtistCount
        }
    }

    struct Weekday: Hashable, Sendable {
        let name: String
        let order: Int

        var localizedName: String {
            switch order {
            case 0: String(localized: "Monday")
            case 1: String(localized: "Tuesday")
            case 2: String(localized: "Wednesday")
            case 3: String(localized: "Thursday")
            case 4: String(localized: "Friday")
            case 5: String(localized: "Saturday")
            case 6: String(localized: "Sunday")
            default: name
            }
        }
    }

    struct Genre: Identifiable, Hashable, Sendable {
        let name: String
        let listenCount: Int
        let percentage: Double?
        let hasListenCount: Bool

        var id: String { name.normalizedIdentity }
    }

    struct ReleaseDecade: Identifiable, Hashable, Sendable {
        let decade: Int
        let listenCount: Int

        var id: Int { decade }
        var label: String { String(localized: "\(decade.calendarYearText)s") }
    }

    struct ListeningDay: Identifiable, Hashable, Sendable {
        /// UTC midnight for the reported calendar date, keeping a leap day
        /// distinct from either neighboring day regardless of device timezone.
        let day: Date
        let listenCount: Int
        let sourceTimeRange: String?

        var id: Date { day }
    }

    struct ReleaseGroup: Identifiable, Hashable, Sendable {
        let releaseGroupMBID: UUID?
        let title: String
        let artistName: String
        let artistMBIDs: [UUID]
        let listenCount: Int
        let coverArtArchiveID: Int?
        /// This is a concrete *release* ID used by CAA, never a release group ID.
        let artworkReleaseMBID: UUID?

        var id: String {
            if let releaseGroupMBID { return "release-group:\(releaseGroupMBID.uuidString)" }
            return "release-group-unmapped:\(artistName.lowercased()):\(title.lowercased())"
        }

        var artworkURL: URL? {
            if let artworkReleaseMBID { return CoverArtArchiveURL.release(artworkReleaseMBID) }
            if let releaseGroupMBID { return CoverArtArchiveURL.releaseGroup(releaseGroupMBID) }
            return nil
        }

        var searchSeed: SearchReleaseGroup? {
            guard let releaseGroupMBID else { return nil }
            return SearchReleaseGroup(
                mbid: releaseGroupMBID,
                title: title,
                artistName: artistName,
                primaryType: nil,
                firstReleaseDate: nil
            )
        }
    }

    /// A current Year in Music discovery item. The release-group MBID is the
    /// only identity that may navigate to a release-group screen. A concrete
    /// release MBID is retained as legacy source identity, while the CAA
    /// release MBID is artwork identity only.
    struct NewRelease: Identifiable, Hashable, Sendable {
        let releaseGroupMBID: UUID?
        let concreteReleaseMBID: UUID?
        let title: String
        let artistName: String
        let artistMBIDs: [UUID]
        let coverArtArchiveID: Int?
        let artworkReleaseMBID: UUID?

        var id: String {
            if let releaseGroupMBID { return "new-release-group:\(releaseGroupMBID.uuidString)" }
            if let concreteReleaseMBID { return "new-release:\(concreteReleaseMBID.uuidString)" }
            return "new-release-unmapped:\(artistName.normalizedIdentity):\(title.normalizedIdentity)"
        }

        var artworkURL: URL? {
            if let artworkReleaseMBID { return CoverArtArchiveURL.release(artworkReleaseMBID) }
            if let releaseGroupMBID { return CoverArtArchiveURL.releaseGroup(releaseGroupMBID) }
            return nil
        }

        var detailDestination: SearchReleaseGroup? {
            guard let releaseGroupMBID else { return nil }
            return SearchReleaseGroup(
                mbid: releaseGroupMBID,
                title: title,
                artistName: artistName,
                primaryType: nil,
                firstReleaseDate: nil
            )
        }
    }

    struct Release: Hashable, Sendable {
        let releaseMBID: UUID?
        let title: String
        let artistName: String
        let artistMBIDs: [UUID]
        let listenCount: Int
        let coverArtArchiveID: Int?
        let artworkReleaseMBID: UUID?
        let providedArtworkURL: URL?

        var artworkURL: URL? {
            providedArtworkURL
                ?? artworkReleaseMBID.flatMap(CoverArtArchiveURL.release)
                ?? releaseMBID.flatMap(CoverArtArchiveURL.release)
        }
        var seed: ReleaseSeed? {
            guard let releaseMBID else { return nil }
            return ReleaseSeed(mbid: releaseMBID, title: title, artistName: artistName, artistMBIDs: artistMBIDs, releaseGroupMBID: nil, releaseDate: nil, primaryType: nil, artworkReleaseMBID: artworkReleaseMBID ?? releaseMBID)
        }
    }

    struct TopRecording: Identifiable, Hashable, Sendable {
        let recording: Recording
        let listenCount: Int
        let coverArtArchiveID: Int?

        var id: String { recording.id }
        var artworkURL: URL? { recording.artworkURL }
        var detailDestination: Recording? {
            guard recording.identity.mbid != nil else { return nil }
            return recording
        }
    }

    struct AnnualPlaylistSnapshot: Identifiable, Hashable, Sendable {
        enum Kind: String, Hashable, Sendable {
            case discoveries
            case missedRecordings

            var title: String {
                switch self {
                case .discoveries: String(localized: "Top discoveries")
                case .missedRecordings: String(localized: "Tracks you missed")
                }
            }

            func explanation(year: Int) -> String {
                switch self {
                case .discoveries: String(localized: "Your top tracks first heard in \(year.calendarYearText).")
                case .missedRecordings: String(localized: "A discovery playlist based on similar listeners.")
                }
            }
        }

        struct Track: Identifiable, Hashable, Sendable {
            let index: Int
            let title: String
            let artistName: String
            let albumTitle: String?
            let durationMilliseconds: Int?
            let recording: Recording?

            var id: String { "\(index):\(title.normalizedIdentity):\(artistName.normalizedIdentity)" }
        }

        let kind: Kind
        let title: String?
        let externalURL: URL?
        let tracks: [Track]

        var id: Kind { kind }
    }

    /// Internal construction path for deterministic previews and tests. Live
    /// reports continue to enter through the schema-normalizing initializer.
    init(
        username: String?,
        year: Int,
        source: Source = .current,
        totals: Totals,
        listeningDays: [ListeningDay],
        topArtists: [RankedArtist],
        newReleasesOfTopArtists: [NewRelease] = [],
        topReleaseGroups: [ReleaseGroup],
        topReleases: [Release] = [],
        topRecordings: [TopRecording],
        annualPlaylists: [AnnualPlaylistSnapshot] = [],
        mostActiveWeekday: Weekday? = nil,
        topGenres: [Genre] = [],
        releaseDecades: [ReleaseDecade] = [],
        artistEvolution: ArtistEvolutionActivity? = nil
    ) {
        self.username = username
        self.year = year
        self.source = source
        self.totals = totals
        self.listeningDays = listeningDays
        self.topArtists = topArtists
        self.newReleasesOfTopArtists = newReleasesOfTopArtists
        self.topReleaseGroups = topReleaseGroups
        self.topReleases = topReleases
        self.topRecordings = topRecordings
        self.annualPlaylists = annualPlaylists
        self.mostActiveWeekday = mostActiveWeekday
        self.topGenres = topGenres
        self.releaseDecades = releaseDecades
        self.artistEvolution = artistEvolution
    }

    /// Maps only a report the API says exists.  `nil` is intentionally
    /// distinct from a legitimate report containing zero listens.
    init?(source sourceData: LBYearInMusic, requestedYear: Int, sourceKind: Source = .current) {
        guard sourceData.isAvailable else { return nil }
        let data = sourceData.data
        username = sourceData.userName?.trimmedNilIfEmpty
        year = sourceData.year ?? requestedYear
        source = sourceKind
        totals = .init(
            listenCount: Self.nonNegative(data.totalListenCount),
            artistCount: Self.nonNegative(data.totalArtistsCount),
            recordingCount: Self.nonNegative(data.totalRecordingsCount),
            releaseGroupCount: Self.nonNegative(data.totalReleaseGroupsCount ?? data.totalReleasesCount),
            newArtistCount: Self.nonNegative(data.totalNewArtistsDiscovered),
            listeningTime: Self.nonNegative(data.totalListeningTime),
            hasArtistCount: data.totalArtistsCount != nil,
            hasRecordingCount: data.totalRecordingsCount != nil,
            hasReleaseCount: data.totalReleaseGroupsCount != nil || data.totalReleasesCount != nil,
            hasListeningTime: data.totalListeningTime != nil,
            hasNewArtistCount: Self.nonNegativeValid(data.totalNewArtistsDiscovered) != nil
        )
        listeningDays = Self.mapListeningDays(data.listensPerDay, year: year)
        topArtists = Self.mapArtists(data.topArtists)
        newReleasesOfTopArtists = Self.mapNewReleases(data.newReleasesOfTopArtists)
        topReleaseGroups = Self.mapReleaseGroups(data.topReleaseGroups)
        topReleases = Self.mapReleases(data.topReleases, coverArtByReleaseMBID: data.topReleasesCoverArt)
        topRecordings = Self.mapRecordings(data.topRecordings)
        annualPlaylists = Self.mapAnnualPlaylists(
            discoveries: data.topDiscoveriesPlaylist,
            missedRecordings: data.topMissedRecordingsPlaylist
        )
        mostActiveWeekday = Self.mapWeekday(data.dayOfWeek)
        topGenres = Self.mapGenres(data.topGenres)
        releaseDecades = Self.mapReleaseDecades(data.mostListenedYear, reportYear: year)
        artistEvolution = Self.mapArtistEvolution(data.artistEvolutionActivity, year: year)
    }

    private static func mapArtistEvolution(
        _ source: [LBYearInMusic.Report.ArtistEvolutionEntry],
        year: Int
    ) -> ArtistEvolutionActivity? {
        guard (1000 ... 9999).contains(year) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let from = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let to = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return nil }

        let rows = source.compactMap { row -> ArtistEvolutionActivity.Row? in
            guard let timeUnit = row.timeUnit,
                  let artistName = row.artistName,
                  let listenCount = row.listenCount,
                  listenCount > 0
            else { return nil }
            return .init(
                timeUnit: timeUnit,
                artistMBID: row.artistMBID.flatMap(UUID.init(uuidString:)),
                artistName: artistName,
                listenCount: listenCount
            )
        }
        let activity = ArtistEvolutionActivity(
            period: .thisYear,
            from: from,
            to: to,
            lastUpdated: .distantPast,
            rows: rows
        )
        return activity.isEmpty ? nil : activity
    }

    private static func mapAnnualPlaylists(
        discoveries: LBYearInMusic.Report.Playlist?,
        missedRecordings: LBYearInMusic.Report.Playlist?
    ) -> [AnnualPlaylistSnapshot] {
        [
            mapAnnualPlaylist(discoveries, kind: .discoveries),
            mapAnnualPlaylist(missedRecordings, kind: .missedRecordings),
        ].compactMap { $0 }
    }

    private static func mapAnnualPlaylist(
        _ source: LBYearInMusic.Report.Playlist?,
        kind: AnnualPlaylistSnapshot.Kind
    ) -> AnnualPlaylistSnapshot? {
        guard let source else { return nil }
        let tracks = source.tracks.enumerated().compactMap { index, track -> AnnualPlaylistSnapshot.Track? in
            guard let title = track.title?.trimmedNilIfEmpty else { return nil }
            let artistName = track.creator?.trimmedNilIfEmpty ?? String(localized: "Unknown artist")
            let recordingMBID = track.identifiers?.compactMap(strictRecordingMBID).first
            let recording = recordingMBID.map { mbid in
                Recording(
                    identity: .init(mbid: mbid, msid: nil),
                    title: title,
                    artistName: artistName,
                    artistMBIDs: [],
                    releaseTitle: track.album?.trimmedNilIfEmpty,
                    releaseMBID: nil,
                    releaseGroupMBID: nil,
                    artworkReleaseMBID: nil,
                    durationMilliseconds: nonNegativeValid(track.duration),
                    source: "ListenBrainz"
                )
            }
            return .init(
                index: index,
                title: title,
                artistName: artistName,
                albumTitle: track.album?.trimmedNilIfEmpty,
                durationMilliseconds: nonNegativeValid(track.duration),
                recording: recording
            )
        }
        guard !tracks.isEmpty else { return nil }
        return .init(
            kind: kind,
            title: source.title?.trimmedNilIfEmpty,
            externalURL: strictPlaylistURL(identifier: source.identifier, legacyMBID: source.legacyMBID),
            tracks: tracks
        )
    }

    private static func strictPlaylistURL(identifier: String?, legacyMBID: String?) -> URL? {
        if let identifier,
           let mbid = strictPlaylistMBID(identifier) {
            return URL(string: "https://listenbrainz.org/playlist/\(mbid.uuidString.lowercased())")
        }
        guard let legacyMBID = legacyMBID?.trimmedNilIfEmpty,
              let mbid = UUID(uuidString: legacyMBID)
        else { return nil }
        return URL(string: "https://listenbrainz.org/playlist/\(mbid.uuidString.lowercased())")
    }

    private static func strictPlaylistMBID(_ identifier: String) -> UUID? {
        guard let source = URL(string: identifier),
              source.scheme?.lowercased() == "https",
              source.host?.lowercased() == "listenbrainz.org",
              source.user == nil,
              source.password == nil,
              source.port == nil,
              source.query == nil,
              source.fragment == nil
        else { return nil }
        let components = source.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "playlist" else { return nil }
        return UUID(uuidString: components[1])
    }

    private static func strictRecordingMBID(_ identifier: String) -> UUID? {
        guard let source = URL(string: identifier),
              source.scheme?.lowercased() == "https",
              source.host?.lowercased() == "musicbrainz.org",
              source.user == nil,
              source.password == nil,
              source.port == nil,
              source.query == nil,
              source.fragment == nil
        else { return nil }
        let components = source.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "recording" else { return nil }
        return UUID(uuidString: components[1])
    }

    private static func mapWeekday(_ source: String?) -> Weekday? {
        guard let normalized = source?.normalizedIdentity else { return nil }
        let weekdays = [
            ("Monday", ["monday", "mon"]),
            ("Tuesday", ["tuesday", "tue", "tues"]),
            ("Wednesday", ["wednesday", "wed"]),
            ("Thursday", ["thursday", "thu", "thur", "thurs"]),
            ("Friday", ["friday", "fri"]),
            ("Saturday", ["saturday", "sat"]),
            ("Sunday", ["sunday", "sun"]),
        ]
        guard let index = weekdays.firstIndex(where: { $0.1.contains(normalized) }) else { return nil }
        return Weekday(name: weekdays[index].0, order: index)
    }

    private static func mapGenres(_ source: [LBYearInMusic.Report.Genre]) -> [Genre] {
        struct Accumulator {
            var name: String
            var listenCount = 0
            var hasListenCount = false
            var percentage = 0.0
            var hasPercentage = false
        }

        var values: [String: Accumulator] = [:]
        for row in source {
            guard let name = row.name?.trimmedNilIfEmpty else { continue }
            let key = name.normalizedIdentity
            var value = values[key] ?? Accumulator(name: name)
            if preferred(name, over: value.name) { value.name = name }
            if let count = nonNegativeValid(row.count) {
                value.listenCount = saturatedSum(value.listenCount, count)
                value.hasListenCount = true
            }
            if let percentage = normalizedPercentage(row.countPercent) {
                value.percentage = min(100, value.percentage + percentage)
                value.hasPercentage = true
            }
            values[key] = value
        }
        return values.values.map { value in
            Genre(
                name: value.name,
                listenCount: value.listenCount,
                percentage: value.hasPercentage ? value.percentage : nil,
                hasListenCount: value.hasListenCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.listenCount != rhs.listenCount { return lhs.listenCount > rhs.listenCount }
            if lhs.percentage != rhs.percentage { return (lhs.percentage ?? 0) > (rhs.percentage ?? 0) }
            return lhs.name.normalizedIdentity < rhs.name.normalizedIdentity
        }
    }

    private static func mapReleaseDecades(_ source: [String: Int], reportYear: Int) -> [ReleaseDecade] {
        let minimumPlausibleReleaseYear = 1850
        // A retrospective must not imply listening to music released after
        // the report year, even when source metadata contains future dates.
        let maximumPlausibleReleaseYear = min(2100, reportYear)
        var counts: [Int: Int] = [:]
        for (rawYear, count) in source {
            guard let year = Int(rawYear.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (minimumPlausibleReleaseYear ... maximumPlausibleReleaseYear).contains(year)
            else { continue }
            let normalizedCount = nonNegative(count)
            guard normalizedCount > 0 else { continue }
            let decade = (year / 10) * 10
            counts[decade] = saturatedSum(counts[decade, default: 0], normalizedCount)
        }
        return counts.map { ReleaseDecade(decade: $0.key, listenCount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.listenCount != rhs.listenCount { return lhs.listenCount > rhs.listenCount }
                return lhs.decade > rhs.decade
            }
    }

    private static func mapReleases(
        _ source: [LBYearInMusic.Report.Release],
        coverArtByReleaseMBID: [String: String]
    ) -> [Release] {
        var normalizedCoverArt: [UUID: URL] = [:]
        for (identifier, rawURL) in coverArtByReleaseMBID {
            guard let mbid = UUID(uuidString: identifier),
                  let url = safeProvidedArtworkURL(rawURL) else { continue }
            normalizedCoverArt[mbid] = url
        }
        var releases: [Release] = []
        for row in source {
            guard let title = row.title?.trimmedNilIfEmpty else { continue }
            let artist = resolvedArtistName(row.artistName ?? row.artistCreditName, credits: row.artists)
            let releaseMBID = row.releaseMBID.flatMap(UUID.init(uuidString:))
            let artistMBIDs = normalizedUUIDs(row.artistMBIDs ?? row.artistCreditMBIDs)
            let artworkReleaseMBID = row.coverArtArchiveReleaseMBID.flatMap(UUID.init(uuidString:)) ?? releaseMBID
            releases.append(Release(
                releaseMBID: releaseMBID,
                title: title,
                artistName: artist,
                artistMBIDs: artistMBIDs,
                listenCount: nonNegative(row.listenCount),
                coverArtArchiveID: nonNegativeOptional(row.coverArtArchiveID),
                artworkReleaseMBID: artworkReleaseMBID,
                providedArtworkURL: releaseMBID.flatMap { normalizedCoverArt[$0] }
            ))
        }
        return releases.sorted {
            $0.listenCount == $1.listenCount
                ? $0.title.normalizedIdentity < $1.title.normalizedIdentity
                : $0.listenCount > $1.listenCount
        }
    }

    private static func safeProvidedArtworkURL(_ rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url
    }

    private static func mapListeningDays(
        _ source: [LBYearInMusic.Report.ListeningDay],
        year: Int
    ) -> [ListeningDay] {
        var counts: [Date: Int] = [:]
        var labels: [Date: String] = [:]
        for row in source {
            guard let day = calendarDay(from: row),
                  utcCalendar.component(.year, from: day) == year
            else { continue }
            counts[day] = saturatedSum(counts[day, default: 0], nonNegative(row.listenCount))
            if let label = row.timeRange?.trimmedNilIfEmpty {
                labels[day] = labels[day].map { min($0, label) } ?? label
            }
        }
        return counts.keys.sorted().map { day in
            ListeningDay(day: day, listenCount: counts[day, default: 0], sourceTimeRange: labels[day])
        }
    }

    private static func mapArtists(_ source: [LBYearInMusic.Report.Artist]) -> [RankedArtist] {
        struct Candidate { let mbid: UUID?; let name: String; let count: Int }
        enum Key: Hashable { case mbid(UUID), name(String) }
        var values: [Key: Candidate] = [:]
        var counts: [Key: Int] = [:]
        for row in source {
            guard let name = row.name?.trimmedNilIfEmpty else { continue }
            let candidate = Candidate(mbid: (row.mbid.flatMap(UUID.init(uuidString:)) ?? row.mbids?.compactMap(UUID.init(uuidString:)).first), name: name, count: nonNegative(row.listenCount))
            let key: Key = candidate.mbid.map(Key.mbid) ?? .name(name.normalizedIdentity)
            counts[key] = saturatedSum(counts[key, default: 0], candidate.count)
            if let old = values[key], preferred(candidate.name, over: old.name) { values[key] = candidate }
            else if values[key] == nil { values[key] = candidate }
        }
        return values.compactMap { key, value in
            counts[key].map { RankedArtist(mbid: value.mbid, name: value.name, listenCount: $0) }
        }
        .sorted(by: rankedArtistOrder)
    }

    private static func mapNewReleases(_ source: [LBYearInMusic.Report.Release]) -> [NewRelease] {
        enum Key: Hashable { case releaseGroup(UUID), fallback(String) }

        var releases: [NewRelease] = []
        var indexByKey: [Key: Int] = [:]

        for row in source {
            guard let title = row.title?.trimmedNilIfEmpty else { continue }
            let artistName = resolvedArtistName(row.artistCreditName ?? row.artistName, credits: row.artists)
            let releaseGroupMBID = row.releaseGroupMBID.flatMap(UUID.init(uuidString:))
            let concreteReleaseMBID = row.releaseMBID.flatMap(UUID.init(uuidString:))
            let key = releaseGroupMBID.map(Key.releaseGroup)
                ?? .fallback("\(artistName.normalizedIdentity):\(title.normalizedIdentity)")
            let artistMBIDs = normalizedUUIDs(
                (row.artistCreditMBIDs ?? row.artistMBIDs ?? [])
                    + (row.artists?.compactMap(\.mbid) ?? [])
            )
            let candidate = NewRelease(
                releaseGroupMBID: releaseGroupMBID,
                concreteReleaseMBID: concreteReleaseMBID,
                title: title,
                artistName: artistName,
                artistMBIDs: artistMBIDs,
                coverArtArchiveID: nonNegativeValid(row.coverArtArchiveID),
                artworkReleaseMBID: row.coverArtArchiveReleaseMBID.flatMap(UUID.init(uuidString:))
            )

            if let index = indexByKey[key] {
                releases[index] = merge(candidate, into: releases[index])
            } else {
                indexByKey[key] = releases.count
                releases.append(candidate)
            }
        }

        return releases
    }

    private static func mapReleaseGroups(_ source: [LBYearInMusic.Report.ReleaseGroup]) -> [ReleaseGroup] {
        enum Key: Hashable { case mbid(UUID), fallback(String) }
        var values: [Key: ReleaseGroup] = [:]
        for row in source {
            let title = row.name?.trimmedNilIfEmpty ?? String(localized: "Untitled release")
            let artist = resolvedArtistName(row.artistName, credits: row.artists)
            let mbid = row.mbid.flatMap(UUID.init(uuidString:))
            let key = mbid.map(Key.mbid)
                ?? .fallback("\(artist.normalizedIdentity):\(title.normalizedIdentity)")
            let candidate = ReleaseGroup(
                releaseGroupMBID: mbid,
                title: title,
                artistName: artist,
                artistMBIDs: normalizedUUIDs(row.artistMBIDs),
                listenCount: nonNegative(row.listenCount),
                coverArtArchiveID: nonNegativeOptional(row.coverArtArchiveID),
                artworkReleaseMBID: row.coverArtArchiveReleaseMBID.flatMap(UUID.init(uuidString:))
            )
            values[key] = merge(candidate, into: values[key])
        }
        return values.values.sorted { lhs, rhs in
            if lhs.listenCount != rhs.listenCount { return lhs.listenCount > rhs.listenCount }
            if lhs.artistName.normalizedIdentity != rhs.artistName.normalizedIdentity {
                return lhs.artistName.normalizedIdentity < rhs.artistName.normalizedIdentity
            }
            return lhs.title.normalizedIdentity < rhs.title.normalizedIdentity
        }
    }

    private static func mapRecordings(_ source: [LBYearInMusic.Report.Recording]) -> [TopRecording] {
        enum Key: Hashable { case mbid(UUID), fallback(String) }
        var values: [Key: TopRecording] = [:]
        for row in source {
            let title = row.trackName?.trimmedNilIfEmpty ?? String(localized: "Untitled recording")
            let artist = resolvedArtistName(row.artistName, credits: row.artists)
            let recordingMBID = row.recordingMBID.flatMap(UUID.init(uuidString:))
            let releaseMBID = row.releaseMBID.flatMap(UUID.init(uuidString:))
            let key = recordingMBID.map(Key.mbid)
                ?? .fallback("\(artist.normalizedIdentity):\(title.normalizedIdentity):\(releaseMBID?.uuidString ?? row.releaseName?.normalizedIdentity ?? "")")
            let candidate = TopRecording(
                recording: Recording(
                    identity: .init(mbid: recordingMBID, msid: nil),
                    title: title,
                    artistName: artist,
                    artistMBIDs: normalizedUUIDs(row.artistMBIDs),
                    releaseTitle: row.releaseName?.trimmedNilIfEmpty,
                    releaseMBID: releaseMBID,
                    releaseGroupMBID: nil,
                    artworkReleaseMBID: row.coverArtArchiveReleaseMBID.flatMap(UUID.init(uuidString:)) ?? releaseMBID,
                    durationMilliseconds: nil,
                    source: nil
                ),
                listenCount: nonNegative(row.listenCount),
                coverArtArchiveID: nonNegativeOptional(row.coverArtArchiveID)
            )
            values[key] = merge(candidate, into: values[key])
        }
        return values.values.sorted { lhs, rhs in
            if lhs.listenCount != rhs.listenCount { return lhs.listenCount > rhs.listenCount }
            if lhs.recording.artistName.normalizedIdentity != rhs.recording.artistName.normalizedIdentity {
                return lhs.recording.artistName.normalizedIdentity < rhs.recording.artistName.normalizedIdentity
            }
            return lhs.recording.title.normalizedIdentity < rhs.recording.title.normalizedIdentity
        }
    }

    private static func merge(_ candidate: ReleaseGroup, into existing: ReleaseGroup?) -> ReleaseGroup {
        guard let existing else { return candidate }
        let chosen = preferred(candidate.title, over: existing.title) ? candidate : existing
        return ReleaseGroup(
            releaseGroupMBID: existing.releaseGroupMBID ?? candidate.releaseGroupMBID,
            title: chosen.title,
            artistName: preferred(candidate.artistName, over: existing.artistName) ? candidate.artistName : existing.artistName,
            artistMBIDs: Array(Set(existing.artistMBIDs).union(candidate.artistMBIDs)).sorted { $0.uuidString < $1.uuidString },
            listenCount: saturatedSum(existing.listenCount, candidate.listenCount),
            coverArtArchiveID: [existing.coverArtArchiveID, candidate.coverArtArchiveID].compactMap { $0 }.min(),
            artworkReleaseMBID: [existing.artworkReleaseMBID, candidate.artworkReleaseMBID].compactMap { $0 }.sorted { $0.uuidString < $1.uuidString }.first
        )
    }

    private static func merge(_ candidate: NewRelease, into existing: NewRelease) -> NewRelease {
        // Keep the first server position and wording stable. Later duplicate
        // rows may still fill gaps in IDs or artwork metadata.
        NewRelease(
            releaseGroupMBID: existing.releaseGroupMBID ?? candidate.releaseGroupMBID,
            concreteReleaseMBID: existing.concreteReleaseMBID ?? candidate.concreteReleaseMBID,
            title: existing.title,
            artistName: existing.artistName,
            artistMBIDs: Array(Set(existing.artistMBIDs).union(candidate.artistMBIDs)).sorted { $0.uuidString < $1.uuidString },
            coverArtArchiveID: existing.coverArtArchiveID ?? candidate.coverArtArchiveID,
            artworkReleaseMBID: existing.artworkReleaseMBID ?? candidate.artworkReleaseMBID
        )
    }

    private static func merge(_ candidate: TopRecording, into existing: TopRecording?) -> TopRecording {
        guard let existing else { return candidate }
        let source = preferred(candidate.recording.title, over: existing.recording.title) ? candidate.recording : existing.recording
        let artist = preferred(candidate.recording.artistName, over: existing.recording.artistName) ? candidate.recording.artistName : existing.recording.artistName
        return TopRecording(
            recording: Recording(
                identity: existing.recording.identity.mbid == nil ? candidate.recording.identity : existing.recording.identity,
                title: source.title,
                artistName: artist,
                artistMBIDs: Array(Set(existing.recording.artistMBIDs).union(candidate.recording.artistMBIDs)).sorted { $0.uuidString < $1.uuidString },
                releaseTitle: source.releaseTitle ?? existing.recording.releaseTitle ?? candidate.recording.releaseTitle,
                releaseMBID: existing.recording.releaseMBID ?? candidate.recording.releaseMBID,
                releaseGroupMBID: nil,
                artworkReleaseMBID: existing.recording.artworkReleaseMBID ?? candidate.recording.artworkReleaseMBID,
                durationMilliseconds: nil,
                source: nil
            ),
            listenCount: saturatedSum(existing.listenCount, candidate.listenCount),
            coverArtArchiveID: [existing.coverArtArchiveID, candidate.coverArtArchiveID].compactMap { $0 }.min()
        )
    }

    private static func calendarDay(from row: LBYearInMusic.Report.ListeningDay) -> Date? {
        if let timestamp = row.from { return utcCalendar.startOfDay(for: timestamp) }
        guard let string = row.timeRange?.trimmedNilIfEmpty else { return nil }
        for formatter in dayFormatters where formatter.date(from: string) != nil {
            return formatter.date(from: string)
        }
        return nil
    }

    private static func resolvedArtistName(_ name: String?, credits: [LBYearInMusic.Report.ArtistCredit]?) -> String {
        if let name = name?.trimmedNilIfEmpty { return name }
        let credits = credits?.compactMap { credit -> String? in
            guard let name = credit.name?.trimmedNilIfEmpty else { return nil }
            return name + (credit.joinPhrase ?? "")
        }.joined()
        return credits?.trimmedNilIfEmpty ?? String(localized: "Unknown artist")
    }

    private static func normalizedUUIDs(_ values: [String]?) -> [UUID] {
        Array(Set((values ?? []).compactMap(UUID.init(uuidString:)))).sorted { $0.uuidString < $1.uuidString }
    }

    private static func nonNegative(_ value: Int?) -> Int { max(0, value ?? 0) }
    private static func nonNegativeValid(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }
    private static func nonNegativeOptional(_ value: Int?) -> Int? { value.map { max(0, $0) } }
    private static func nonNegative(_ value: Double?) -> TimeInterval {
        guard let value, value.isFinite else { return 0 }
        return max(0, value)
    }
    private static func normalizedPercentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return min(100, value)
    }
    private static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }
    private static func preferred(_ candidate: String, over existing: String) -> Bool {
        let comparison = candidate.normalizedIdentity.compare(existing.normalizedIdentity)
        return comparison == .orderedAscending || (comparison == .orderedSame && candidate < existing)
    }
    private static func rankedArtistOrder(_ lhs: RankedArtist, _ rhs: RankedArtist) -> Bool {
        if lhs.listenCount != rhs.listenCount { return lhs.listenCount > rhs.listenCount }
        if lhs.name.normalizedIdentity != rhs.name.normalizedIdentity { return lhs.name.normalizedIdentity < rhs.name.normalizedIdentity }
        return lhs.id < rhs.id
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let dayFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "dd MMMM yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.calendar = utcCalendar
            formatter.dateFormat = format
            return formatter
        }
    }()
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedIdentity: String {
        trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
    }
}
