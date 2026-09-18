import Foundation

enum CoverArtArchiveURL {
    static func release(_ mbid: UUID) -> URL? {
        URL(string: "https://coverartarchive.org/release/\(mbid.uuidString.lowercased())/front-500")
    }

    static func releaseGroup(_ mbid: UUID) -> URL? {
        URL(string: "https://coverartarchive.org/release-group/\(mbid.uuidString.lowercased())/front-500")
    }
}

struct Account: Hashable, Sendable {
    let username: String
    let token: String

    var isAuthenticated: Bool { !token.isEmpty }
}
struct RecordingIdentity: Hashable, Codable, Sendable {
    let mbid: UUID?
    let msid: UUID?
}

struct Recording: Identifiable, Hashable, Codable, Sendable {
    let identity: RecordingIdentity
    let title: String
    let artistName: String
    let artistMBIDs: [UUID]
    let releaseTitle: String?
    let releaseMBID: UUID?
    let releaseGroupMBID: UUID?
    let artworkReleaseMBID: UUID?
    let durationMilliseconds: Int?
    let source: String?

    var id: String {
        if let mbid = identity.mbid { return "mbid:\(mbid.uuidString)" }
        if let msid = identity.msid { return "msid:\(msid.uuidString)" }
        return "unmapped:\(artistName):\(title):\(releaseTitle ?? "")"
    }

    var artworkURL: URL? {
        guard let id = artworkReleaseMBID ?? releaseMBID else { return nil }
        return CoverArtArchiveURL.release(id)
    }
}

struct Listen: Identifiable, Hashable, Codable, Sendable {
    let recording: Recording
    let listenedAt: Date
    let insertedAt: Date?
    let isPlayingNow: Bool

    // A mapped recording can legitimately have more than one MSID at the same
    // second. Keep that source identity in the listen key so overlapping pages
    // do not discard a distinct submitted listen.
    var id: String {
        let sourceIdentity = recording.identity.msid?.uuidString ?? recording.id
        return "\(sourceIdentity):\(listenedAt.timeIntervalSince1970):\(isPlayingNow)"
    }
}

/// The ListenBrainz listens endpoint uses strict, second-granular bounds.
/// A local day is therefore `(start - 1 second, nextStart)`, which includes
/// a listen exactly at local midnight and remains correct across DST changes.
struct HistoryDayBounds: Hashable, Sendable {
    let day: Date
    let earliest: Date
    let latest: Date

    init(day: Date, calendar: Calendar = .autoupdatingCurrent) {
        let start = calendar.startOfDay(for: day)
        self.day = start
        self.earliest = start.addingTimeInterval(-1)
        self.latest = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }
}

struct PinnedRecording: Identifiable, Hashable, Sendable {
    let rowID: Int
    let created: Date
    let pinnedUntil: Date?
    let blurb: String?
    let username: String?
    let recording: Recording
    let isCurrent: Bool

    var id: Int { rowID }
}

struct RankedArtist: Identifiable, Hashable, Codable, Sendable {
    let mbid: UUID?
    let name: String
    let listenCount: Int

    var id: String { mbid?.uuidString ?? "artist:\(name)" }
}

struct RankedRelease: Identifiable, Hashable, Codable, Sendable {
    let mbid: UUID?
    let name: String
    let artistName: String
    let artistMBIDs: [UUID]
    let listenCount: Int

    var id: String { mbid?.uuidString ?? "release:\(artistName):\(name)" }
    var artworkURL: URL? {
        guard let mbid else { return nil }
        return CoverArtArchiveURL.release(mbid)
    }

    var releaseSeed: ReleaseSeed? {
        guard let mbid else { return nil }
        return ReleaseSeed(
            mbid: mbid,
            title: name,
            artistName: artistName,
            artistMBIDs: artistMBIDs,
            releaseGroupMBID: nil,
            releaseDate: nil,
            primaryType: nil,
            artworkReleaseMBID: mbid
        )
    }
}

struct RankedRecording: Identifiable, Hashable, Codable, Sendable {
    let mbid: UUID?
    let releaseMBID: UUID?
    let title: String
    let artistName: String
    let artistMBIDs: [UUID]
    let releaseTitle: String?
    let listenCount: Int

    var id: String { mbid?.uuidString ?? "recording:\(artistName):\(title)" }
    var recording: Recording {
        Recording(
            identity: .init(mbid: mbid, msid: nil),
            title: title,
            artistName: artistName,
            artistMBIDs: artistMBIDs,
            releaseTitle: releaseTitle,
            releaseMBID: releaseMBID,
            releaseGroupMBID: nil,
            artworkReleaseMBID: releaseMBID,
            durationMilliseconds: nil,
            source: nil
        )
    }
}

struct ListeningSnapshot: Codable, Sendable {
    var recentListens: [Listen]
    var playingNow: Listen?
    var listenCount: Int?
    var topArtists: [RankedArtist]
    var topReleases: [RankedRelease]
    var topRecordings: [RankedRecording]
    var savedAt: Date

    static let empty = ListeningSnapshot(
        recentListens: [],
        playingNow: nil,
        listenCount: nil,
        topArtists: [],
        topReleases: [],
        topRecordings: [],
        savedAt: .distantPast
    )
}

struct UserProfileSnapshot: Sendable {
    var recentListens: [Listen]
    var playingNow: Listen?
    var listenCount: Int?
    var topArtists: [RankedArtist]
    var hasLoadedOverview: Bool
    var hasLoadedTopArtists: Bool
    var savedAt: Date

    static let empty = UserProfileSnapshot(
        recentListens: [],
        playingNow: nil,
        listenCount: nil,
        topArtists: [],
        hasLoadedOverview: false,
        hasLoadedTopArtists: false,
        savedAt: .distantPast
    )
}

enum RecordingFeedback: Int, Sendable {
    case hate = -1
    case none = 0
    case love = 1
}

/// Feedback that trains ListenBrainz recommendations. This is intentionally
/// distinct from the recording-level Love/Hate state above.
enum RecommendationRating: String, CaseIterable, Hashable, Sendable {
    case hate
    case dislike
    case like
    case love
}

enum ListeningActivityPeriod: String, CaseIterable, Identifiable, Sendable {
    case thisWeek
    case thisMonth
    case thisYear
    case lastWeek
    case lastMonth
    case lastYear
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .thisYear: "This Year"
        case .lastWeek: "Last Week"
        case .lastMonth: "Last Month"
        case .lastYear: "Last Year"
        case .allTime: "All Time"
        }
    }

    var accessibilityLabel: String { title }
}

struct ListeningActivity: Hashable, Sendable {
    let period: ListeningActivityPeriod
    let from: Date
    let to: Date
    let lastUpdated: Date
    let buckets: [Bucket]

    struct Bucket: Identifiable, Hashable, Sendable {
        let label: String
        let from: Date
        let to: Date
        let listenCount: Int

        var id: String {
            "\(from.timeIntervalSince1970):\(to.timeIntervalSince1970):\(label)"
        }
    }

    var totalListens: Int { buckets.reduce(into: 0) { $0 += $1.listenCount } }
    var busiestBucket: Bucket? { buckets.max { $0.listenCount < $1.listenCount } }
}

enum ListeningActivityLoadState: Equatable {
    case idle
    case loading
    case loaded(ListeningActivity)
    case failed(String)
}

enum ListeningWeekday: String, CaseIterable, Identifiable, Hashable, Sendable {
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    case sunday = "Sunday"

    var id: Self { self }

    var shortTitle: String {
        String(rawValue.prefix(3))
    }
}

/// ListenBrainz's server-calculated listening distribution. The API reports
/// UTC weekdays/hours, so this deliberately never applies the device timezone.
struct DailyActivity: Hashable, Sendable {
    struct Hour: Hashable, Sendable {
        let hour: Int
        let listenCount: Int
    }

    struct Cell: Identifiable, Hashable, Sendable {
        let weekday: ListeningWeekday
        let hour: Int
        let listenCount: Int

        var id: String { "\(weekday.rawValue)-\(hour)" }
    }

    let period: ListeningActivityPeriod
    let from: Date
    let to: Date
    let lastUpdated: Date
    /// Always Monday through Sunday, with 24 cells (00:00–23:00 UTC) each.
    let cells: [Cell]

    init(
        period: ListeningActivityPeriod,
        from: Date,
        to: Date,
        lastUpdated: Date,
        dailyActivity: [String: [Hour]]
    ) {
        self.period = period
        self.from = from
        self.to = to
        self.lastUpdated = lastUpdated

        var counts: [ListeningWeekday: [Int: Int]] = [:]
        for weekday in ListeningWeekday.allCases {
            for value in dailyActivity[weekday.rawValue] ?? [] where (0 ..< 24).contains(value.hour) {
                // Be defensive if an upstream payload contains duplicates or
                // malformed negative counts: combine valid samples and leave
                // the visualization in a meaningful, non-negative state.
                let count = max(0, value.listenCount)
                var weekdayCounts = counts[weekday, default: [:]]
                let current = weekdayCounts[value.hour, default: 0]
                weekdayCounts[value.hour] = current.addingReportingOverflow(count).overflow
                    ? Int.max
                    : current + count
                counts[weekday] = weekdayCounts
            }
        }

        self.cells = ListeningWeekday.allCases.flatMap { weekday in
            (0 ..< 24).map { hour in
                Cell(weekday: weekday, hour: hour, listenCount: counts[weekday]?[hour, default: 0] ?? 0)
            }
        }
    }

    var totalListens: Int {
        cells.reduce(into: 0) { total, cell in
            let addition = total.addingReportingOverflow(cell.listenCount)
            total = addition.overflow ? Int.max : addition.partialValue
        }
    }
    var maximumListenCount: Int { cells.map(\.listenCount).max() ?? 0 }
    var isEmpty: Bool { maximumListenCount == 0 }

    func cell(weekday: ListeningWeekday, hour: Int) -> Cell? {
        guard (0 ..< 24).contains(hour) else { return nil }
        return cells[ListeningWeekday.allCases.firstIndex(of: weekday)! * 24 + hour]
    }
}

enum DailyActivityLoadState: Equatable {
    case idle
    case loading
    case loaded(DailyActivity)
    case unavailable
    case failed(String)
}

struct DailyActivityCacheKey: Hashable, Sendable {
    let username: String
    let period: ListeningActivityPeriod

    init(username: String, period: ListeningActivityPeriod) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.period = period
    }
}

/// ListenBrainz's server-calculated distribution of listens by each
/// recording's original release year.
struct EraActivity: Hashable, Sendable {
    /// MusicBrainz partial dates use ordinary four-digit Common Era years.
    /// Keeping this boundary in the domain model prevents corrupt upstream
    /// metadata from creating an effectively unbounded chart.
    private static let supportedReleaseYears = 1000 ... 9999
    private static let maximumFilledDecadeCount = 100

    struct Year: Identifiable, Hashable, Sendable {
        let year: Int
        let listenCount: Int

        var id: Int { year }
    }

    struct Decade: Identifiable, Hashable, Sendable {
        let year: Int
        let listenCount: Int

        var id: Int { year }
        var title: String { "\(year)s" }
    }

    let period: ListeningActivityPeriod
    let from: Date
    let to: Date
    let lastUpdated: Date
    let years: [Year]

    init(
        period: ListeningActivityPeriod,
        from: Date,
        to: Date,
        lastUpdated: Date,
        years: [Year]
    ) {
        self.period = period
        self.from = from
        self.to = to
        self.lastUpdated = lastUpdated

        var normalized: [Int: Int] = [:]
        for value in years where Self.supportedReleaseYears.contains(value.year) {
            normalized[value.year] = Self.saturatedSum(
                normalized[value.year, default: 0],
                max(value.listenCount, 0)
            )
        }
        self.years = normalized
            .map { Year(year: $0.key, listenCount: $0.value) }
            .sorted { $0.year < $1.year }
    }

    var totalListens: Int {
        years.reduce(0) { Self.saturatedSum($0, $1.listenCount) }
    }

    var decades: [Decade] {
        guard let firstYear = years.first?.year, let lastYear = years.last?.year else { return [] }
        let firstDecade = Self.decade(containing: firstYear)
        let lastDecade = Self.decade(containing: lastYear)
        var totals: [Int: Int] = [:]
        for value in years {
            let decade = Self.decade(containing: value.year)
            totals[decade] = Self.saturatedSum(totals[decade, default: 0], value.listenCount)
        }
        let decadeCount = ((lastDecade - firstDecade) / 10) + 1
        if decadeCount > Self.maximumFilledDecadeCount {
            return totals.keys.sorted().map {
                Decade(year: $0, listenCount: totals[$0, default: 0])
            }
        }
        return stride(from: firstDecade, through: lastDecade, by: 10).map {
            Decade(year: $0, listenCount: totals[$0, default: 0])
        }
    }

    var leadingDecade: Decade? {
        decades.max {
            if $0.listenCount == $1.listenCount { return $0.year < $1.year }
            return $0.listenCount < $1.listenCount
        }
    }

    var isEmpty: Bool { totalListens == 0 }

    func years(in decade: Int) -> [Year] {
        let start = Self.decade(containing: decade)
        guard Self.supportedReleaseYears.contains(start),
              Self.supportedReleaseYears.contains(start + 9)
        else { return [] }
        let counts = Dictionary(uniqueKeysWithValues: years.map { ($0.year, $0.listenCount) })
        return (start ... start + 9).map { Year(year: $0, listenCount: counts[$0, default: 0]) }
    }

    func listenCount(in decade: Int) -> Int {
        years(in: decade).reduce(0) { Self.saturatedSum($0, $1.listenCount) }
    }

    private static func decade(containing year: Int) -> Int {
        (year / 10) * 10
    }

    private static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }
}

enum EraActivityLoadState: Equatable {
    case idle
    case loading
    case loaded(EraActivity)
    case unavailable
    case failed(String)
}

struct EraActivityCacheKey: Hashable, Sendable {
    let username: String
    let period: ListeningActivityPeriod

    init(username: String, period: ListeningActivityPeriod) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.period = period
    }
}

/// ListenBrainz's server-calculated top artists across the buckets of a
/// selected statistics range. The initializer makes the sparse, unordered API
/// rows safe and deterministic for native charts.
struct ArtistEvolutionActivity: Hashable, Sendable {
    /// The ListenBrainz API emits English month names independent of the
    /// device locale, so these are protocol values rather than display text.
    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
    private static let supportedYears = 1000 ... 9999
    private static let maximumFilledYearCount = 100

    struct Row: Hashable, Sendable {
        let timeUnit: String
        let artistMBID: UUID?
        let artistName: String
        let listenCount: Int
    }

    struct Point: Identifiable, Hashable, Sendable {
        let timeUnit: String
        let listenCount: Int

        var id: String { timeUnit }
    }

    struct Artist: Identifiable, Hashable, Sendable {
        let mbid: UUID?
        let name: String
        let listenCount: Int
        let points: [Point]

        var id: String { mbid?.uuidString ?? "artist:\(name.lowercased())" }

        func listenCount(at timeUnit: String) -> Int {
            points.first { $0.timeUnit == timeUnit }?.listenCount ?? 0
        }

        var rankedArtist: RankedArtist {
            RankedArtist(mbid: mbid, name: name, listenCount: listenCount)
        }
    }

    let period: ListeningActivityPeriod
    let from: Date
    let to: Date
    let lastUpdated: Date
    let timeUnits: [String]
    let artists: [Artist]

    init(
        period: ListeningActivityPeriod,
        from: Date,
        to: Date,
        lastUpdated: Date,
        rows: [Row]
    ) {
        self.period = period
        self.from = from
        self.to = to
        self.lastUpdated = lastUpdated

        let preparedRows = rows.compactMap { row -> PreparedRow? in
            let name = row.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let timeUnit = Self.canonicalTimeUnit(row.timeUnit, for: period)
            else { return nil }
            return PreparedRow(
                timeUnit: timeUnit,
                artistMBID: row.artistMBID,
                artistName: name,
                normalizedName: name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                ).lowercased(),
                listenCount: max(0, row.listenCount)
            )
        }

        // If otherwise-identical rows occasionally omit an MBID, attach them
        // to it only when the normalized name maps to one unambiguous ID.
        var identifiersByName: [String: Set<UUID>] = [:]
        for row in preparedRows {
            if let mbid = row.artistMBID {
                identifiersByName[row.normalizedName, default: []].insert(mbid)
            }
        }

        var grouped: [ArtistKey: ArtistAccumulator] = [:]
        for row in preparedRows {
            let inferredMBID: UUID?
            if let mbid = row.artistMBID {
                inferredMBID = mbid
            } else if identifiersByName[row.normalizedName]?.count == 1 {
                inferredMBID = identifiersByName[row.normalizedName]?.first
            } else {
                inferredMBID = nil
            }
            let key = inferredMBID.map(ArtistKey.mbid) ?? .name(row.normalizedName)
            var accumulator = grouped[key, default: ArtistAccumulator(mbid: inferredMBID)]
            accumulator.nameCounts[row.artistName] = Self.saturatedSum(
                accumulator.nameCounts[row.artistName, default: 0],
                row.listenCount
            )
            accumulator.pointCounts[row.timeUnit] = Self.saturatedSum(
                accumulator.pointCounts[row.timeUnit, default: 0],
                row.listenCount
            )
            grouped[key] = accumulator
        }

        let observedTimeUnits = Set(preparedRows.map(\.timeUnit))
        let orderedTimeUnits = Self.orderedTimeUnits(observedTimeUnits, for: period)
        self.timeUnits = orderedTimeUnits
        self.artists = grouped.values.map { accumulator in
            let name = accumulator.nameCounts.keys.sorted { lhs, rhs in
                let leftCount = accumulator.nameCounts[lhs, default: 0]
                let rightCount = accumulator.nameCounts[rhs, default: 0]
                if leftCount == rightCount {
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                return leftCount > rightCount
            }.first ?? "Unknown artist"
            let points = orderedTimeUnits.map {
                Point(timeUnit: $0, listenCount: accumulator.pointCounts[$0, default: 0])
            }
            let total = points.reduce(0) { Self.saturatedSum($0, $1.listenCount) }
            return Artist(mbid: accumulator.mbid, name: name, listenCount: total, points: points)
        }.sorted { lhs, rhs in
            if lhs.listenCount == rhs.listenCount {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.listenCount > rhs.listenCount
        }
    }

    var totalListens: Int {
        artists.reduce(0) { Self.saturatedSum($0, $1.listenCount) }
    }

    var leadingArtist: Artist? { artists.first }
    var isEmpty: Bool { totalListens == 0 || timeUnits.isEmpty }

    func artists(limit: Int) -> [Artist] {
        Array(artists.prefix(max(0, limit)))
    }

    private static func canonicalTimeUnit(
        _ rawValue: String,
        for period: ListeningActivityPeriod
    ) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch period {
        case .thisWeek, .lastWeek:
            return ListeningWeekday.allCases.first {
                $0.rawValue.caseInsensitiveCompare(value) == .orderedSame
            }?.rawValue
        case .thisMonth, .lastMonth:
            guard let day = Int(value), (1 ... 31).contains(day) else { return nil }
            return String(day)
        case .thisYear, .lastYear:
            return monthNames.first {
                $0.caseInsensitiveCompare(value) == .orderedSame
            }
        case .allTime:
            guard let year = Int(value), supportedYears.contains(year) else { return nil }
            return String(year)
        }
    }

    private static func orderedTimeUnits(
        _ observed: Set<String>,
        for period: ListeningActivityPeriod
    ) -> [String] {
        switch period {
        case .thisWeek, .lastWeek:
            return ListeningWeekday.allCases.map(\.rawValue)
        case .thisMonth, .lastMonth:
            return (1 ... 31).map(String.init)
        case .thisYear, .lastYear:
            return monthNames
        case .allTime:
            let years = observed.compactMap(Int.init).sorted()
            guard let first = years.first, let last = years.last else { return [] }
            let span = (last - first) + 1
            if span > maximumFilledYearCount {
                return years.map(String.init)
            }
            return (first ... last).map(String.init)
        }
    }

    private static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }

    private struct PreparedRow {
        let timeUnit: String
        let artistMBID: UUID?
        let artistName: String
        let normalizedName: String
        let listenCount: Int
    }

    private enum ArtistKey: Hashable {
        case mbid(UUID)
        case name(String)
    }

    private struct ArtistAccumulator {
        let mbid: UUID?
        var nameCounts: [String: Int] = [:]
        var pointCounts: [String: Int] = [:]
    }
}

enum ArtistEvolutionLoadState: Equatable {
    case idle
    case loading
    case loaded(ArtistEvolutionActivity)
    case unavailable
    case failed(String)
}

struct ArtistEvolutionActivityCacheKey: Hashable, Sendable {
    let username: String
    let period: ListeningActivityPeriod

    init(username: String, period: ListeningActivityPeriod) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.period = period
    }
}

/// ListenBrainz's server-calculated top genres for each UTC hour. The source
/// response is intentionally not treated as a complete distribution: it only
/// contains the server's top genres for an hour.
struct GenreActivity: Hashable, Sendable {
    struct Row: Hashable, Sendable {
        let genre: String
        let hour: Int
        let listenCount: Int
    }

    struct Genre: Identifiable, Hashable, Sendable {
        /// A normalized display-string key, not a stable ListenBrainz genre ID.
        let id: String
        let name: String
        let hourlyListenCounts: [Int]

        var totalListenCount: Int {
            hourlyListenCounts.reduce(0, Self.saturatedSum)
        }

        var peakHourlyListenCount: Int { hourlyListenCounts.max() ?? 0 }
        var isEmpty: Bool { totalListenCount == 0 }

        func listenCount(atUTCHour hour: Int) -> Int {
            guard hourlyListenCounts.indices.contains(hour) else { return 0 }
            return hourlyListenCounts[hour]
        }

        private static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
            let result = lhs.addingReportingOverflow(rhs)
            return result.overflow ? Int.max : result.partialValue
        }
    }

    let period: ListeningActivityPeriod
    let from: Date
    let to: Date
    let lastUpdated: Date
    let genres: [Genre]

    init(
        period: ListeningActivityPeriod,
        from: Date,
        to: Date,
        lastUpdated: Date,
        rows: [Row]
    ) {
        self.period = period
        self.from = from
        self.to = to
        self.lastUpdated = lastUpdated

        var grouped: [String: GenreAccumulator] = [:]
        for row in rows {
            let name = Self.normalizedDisplayName(row.genre)
            guard !name.isEmpty, (0 ..< 24).contains(row.hour) else { continue }

            let key = Self.normalizedKey(for: name)
            guard !key.isEmpty else { continue }
            var accumulator = grouped[key, default: GenreAccumulator()]
            let count = max(0, row.listenCount)
            accumulator.nameCounts[name] = Self.saturatedSum(
                accumulator.nameCounts[name, default: 0],
                count
            )
            accumulator.hourlyCounts[row.hour] = Self.saturatedSum(
                accumulator.hourlyCounts[row.hour],
                count
            )
            grouped[key] = accumulator
        }

        genres = grouped.map { key, accumulator in
            let name = accumulator.nameCounts.keys.sorted { lhs, rhs in
                let leftCount = accumulator.nameCounts[lhs, default: 0]
                let rightCount = accumulator.nameCounts[rhs, default: 0]
                if leftCount == rightCount {
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                return leftCount > rightCount
            }.first ?? key
            return Genre(id: key, name: name, hourlyListenCounts: accumulator.hourlyCounts)
        }.sorted { lhs, rhs in
            if lhs.totalListenCount == rhs.totalListenCount {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.totalListenCount > rhs.totalListenCount
        }
    }

    var totalListenCount: Int {
        genres.reduce(0) { Self.saturatedSum($0, $1.totalListenCount) }
    }

    var leadingGenre: Genre? { genres.first }
    var isEmpty: Bool { totalListenCount == 0 }

    private static func normalizedDisplayName(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func normalizedKey(for displayName: String) -> String {
        displayName.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
    }

    private static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }

    private struct GenreAccumulator {
        var nameCounts: [String: Int] = [:]
        var hourlyCounts = Array(repeating: 0, count: 24)
    }
}

enum GenreActivityLoadState: Equatable {
    case idle
    case loading
    case loaded(GenreActivity)
    case unavailable
    case failed(String)
}

struct GenreActivityCacheKey: Hashable, Sendable {
    let username: String
    let period: ListeningActivityPeriod

    init(username: String, period: ListeningActivityPeriod) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.period = period
    }
}

struct FreshRelease: Identifiable, Hashable, Sendable {
    let releaseMBID: UUID?
    let releaseGroupMBID: UUID?
    let title: String
    let artistName: String
    let artistMBIDs: [UUID]
    let releaseDate: String?
    let primaryType: String?
    let secondaryType: String?
    let tags: [String]
    let confidence: Double?
    let listenCount: Int?
    let artworkReleaseMBID: UUID?
    let sourcePosition: Int

    var id: String {
        let identity: String
        if let releaseMBID {
            identity = "release:\(releaseMBID.uuidString)"
        } else if let releaseGroupMBID {
            identity = "release-group:\(releaseGroupMBID.uuidString)"
        } else {
            identity = "unmapped-release:\(artistName):\(title):\(releaseDate ?? "")"
        }
        return "\(identity):\(sourcePosition)"
    }

    var artworkURL: URL? {
        guard let artworkReleaseMBID else { return nil }
        return CoverArtArchiveURL.release(artworkReleaseMBID)
    }

    var typeDescription: String? {
        [primaryType, secondaryType].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    var discoveryContext: ReleaseDiscoveryContext? {
        guard !tags.isEmpty || confidence != nil || listenCount != nil else { return nil }
        return ReleaseDiscoveryContext(
            tags: tags,
            confidence: confidence,
            listenCount: listenCount
        )
    }

    var releaseDateValue: Date? {
        releaseDateValue(in: .autoupdatingCurrent)
    }

    func releaseDateValue(in timeZone: TimeZone) -> Date? {
        guard let releaseDate else { return nil }
        let components = releaseDate.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = timeZone
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        return dateComponents.date
    }

    var releaseDateDescription: String? {
        releaseDateValue?.formatted(.dateTime.month(.abbreviated).day().year()) ?? releaseDate
    }

    var isUpcoming: Bool {
        guard let releaseDateValue else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.compare(releaseDateValue, to: .now, toGranularity: .day) == .orderedDescending
    }

    var releaseMusicBrainzURL: URL? {
        guard let releaseMBID else { return nil }
        return URL(string: "https://musicbrainz.org/release/\(releaseMBID.uuidString)")
    }

    var releaseGroupMusicBrainzURL: URL? {
        guard let releaseGroupMBID else { return nil }
        return URL(string: "https://musicbrainz.org/release-group/\(releaseGroupMBID.uuidString)")
    }
}

/// A concrete MusicBrainz release (edition), deliberately distinct from a
/// release group. It is the canonical navigation identity for ordered tracks.
struct ReleaseSeed: Identifiable, Hashable, Sendable {
    let mbid: UUID
    let title: String
    let artistName: String
    let artistMBIDs: [UUID]
    let releaseGroupMBID: UUID?
    let releaseDate: String?
    let primaryType: String?
    let artworkReleaseMBID: UUID?
    let discoveryContext: ReleaseDiscoveryContext?

    var id: UUID { mbid }
    var artworkURL: URL? { CoverArtArchiveURL.release(artworkReleaseMBID ?? mbid) }
    var musicBrainzURL: URL { URL(string: "https://musicbrainz.org/release/\(mbid.uuidString)")! }

    init(
        mbid: UUID,
        title: String,
        artistName: String,
        artistMBIDs: [UUID],
        releaseGroupMBID: UUID?,
        releaseDate: String?,
        primaryType: String?,
        artworkReleaseMBID: UUID?,
        discoveryContext: ReleaseDiscoveryContext? = nil
    ) {
        self.mbid = mbid
        self.title = title
        self.artistName = artistName
        self.artistMBIDs = artistMBIDs
        self.releaseGroupMBID = releaseGroupMBID
        self.releaseDate = releaseDate
        self.primaryType = primaryType
        self.artworkReleaseMBID = artworkReleaseMBID
        self.discoveryContext = discoveryContext
    }

    init?(recording: Recording) {
        guard let mbid = recording.releaseMBID else { return nil }
        self.init(
            mbid: mbid,
            title: recording.releaseTitle ?? "Unknown release",
            artistName: recording.artistName,
            artistMBIDs: recording.artistMBIDs,
            releaseGroupMBID: recording.releaseGroupMBID,
            releaseDate: nil,
            primaryType: nil,
            artworkReleaseMBID: recording.artworkReleaseMBID ?? mbid,
            discoveryContext: nil
        )
    }

    init?(freshRelease: FreshRelease) {
        guard let mbid = freshRelease.releaseMBID else { return nil }
        self.init(
            mbid: mbid,
            title: freshRelease.title,
            artistName: freshRelease.artistName,
            artistMBIDs: freshRelease.artistMBIDs,
            releaseGroupMBID: freshRelease.releaseGroupMBID,
            releaseDate: freshRelease.releaseDate,
            primaryType: freshRelease.typeDescription,
            artworkReleaseMBID: freshRelease.artworkReleaseMBID ?? mbid,
            discoveryContext: freshRelease.discoveryContext
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.mbid == rhs.mbid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(mbid)
    }
}

/// ListenBrainz-specific discovery metadata carried alongside a canonical
/// MusicBrainz identity. It enriches presentation but never changes identity.
struct ReleaseDiscoveryContext: Hashable, Sendable {
    let tags: [String]
    let confidence: Double?
    let listenCount: Int?

    var hasVisibleContent: Bool {
        listenCount != nil || confidence != nil || !tags.isEmpty
    }
}

struct ReleaseDetail: Hashable, Sendable {
    let mbid: UUID
    let title: String
    let artistCreditName: String
    let releaseDate: String?
    let country: String?
    let status: String?
    let barcode: String?
    let packaging: String?
    let labels: [String]
    let releaseGroupMBID: UUID?
    let releaseGroupPrimaryType: String?
    let media: [ReleaseMedium]

    var artworkURL: URL? { CoverArtArchiveURL.release(mbid) }
    var trackCount: Int { media.reduce(0) { $0 + $1.tracks.count } }
    var totalDurationMilliseconds: Int? {
        let values = media.flatMap(\.tracks).compactMap(\.recording.durationMilliseconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}

struct ReleaseMedium: Identifiable, Hashable, Sendable {
    let position: Int
    let format: String?
    let title: String?
    let tracks: [ReleaseTrack]

    var id: String { "\(position):\(format ?? ""): \(title ?? "")" }
}

struct ReleaseTrack: Identifiable, Hashable, Sendable {
    let position: Int
    let number: String?
    let recording: Recording

    var id: String { "\(position):\(recording.id)" }
}

enum FreshReleaseScope: String, CaseIterable, Identifiable, Sendable {
    case forYou
    case all

    var id: Self { self }
    var title: String { self == .forYou ? "For You" : "All" }
}

enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case users
    case artists
    case releaseGroups
    case recordings
    case playlists

    var id: Self { self }
    var title: String {
        switch self {
        case .users: "Users"
        case .artists: "Artists"
        case .releaseGroups: "Albums"
        case .recordings: "Tracks"
        case .playlists: "Playlists"
        }
    }

    var minimumQueryLength: Int { self == .playlists ? 3 : 1 }
}

struct SearchReleaseGroup: Identifiable, Hashable, Sendable {
    let mbid: UUID
    let title: String
    let artistName: String
    let primaryType: String?
    let firstReleaseDate: String?

    var id: UUID { mbid }
    var musicBrainzURL: URL { URL(string: "https://musicbrainz.org/release-group/\(mbid.uuidString)")! }
}

struct ReleaseGroupDetail: Hashable, Sendable {
    let mbid: UUID
    let title: String
    let artistCreditName: String
    let artists: [RankedArtist]
    let releaseDate: String?
    let primaryType: String?
    let tags: [String]
    let artworkReleaseMBID: UUID?

    var artworkURL: URL? {
        if let artworkReleaseMBID {
            return CoverArtArchiveURL.release(artworkReleaseMBID)
        }
        return CoverArtArchiveURL.releaseGroup(mbid)
    }
}

struct SearchUser: Identifiable, Hashable, Sendable {
    let username: String
    var id: String { username.lowercased() }
    var listenBrainzURL: URL? {
        URL(string: "https://listenbrainz.org")?
            .appending(path: "user")
            .appending(path: username)
    }
}

struct SimilarListener: Identifiable, Hashable, Sendable {
    let user: SearchUser
    let similarity: Double

    var id: String { user.id }
    var normalizedSimilarity: Double { min(max(similarity, 0), 1) }
}

struct SearchPlaylist: Identifiable, Hashable, Sendable {
    let title: String
    let creator: String
    let annotation: String?
    let identifier: String
    let isPublic: Bool
    /// The playlist's ListenBrainz creation date, when the server provides it.
    let createdAt: Date?
    /// Duration reported by ListenBrainz in milliseconds, when known.
    let durationMilliseconds: Int?
    let lastModifiedAt: Date?
    /// The user this generated playlist was made for, if applicable.
    let createdFor: String?
    /// Usernames that can collaborate on this playlist.
    let collaborators: [String]
    let recommendationType: String?
    let expiresAt: Date?

    init(
        title: String,
        creator: String,
        annotation: String?,
        identifier: String,
        isPublic: Bool,
        lastModifiedAt: Date?,
        createdAt: Date? = nil,
        durationMilliseconds: Int? = nil,
        createdFor: String? = nil,
        collaborators: [String] = [],
        recommendationType: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.title = title
        self.creator = creator
        self.annotation = annotation
        self.identifier = identifier
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.durationMilliseconds = durationMilliseconds
        self.lastModifiedAt = lastModifiedAt
        self.createdFor = createdFor
        self.collaborators = collaborators
        self.recommendationType = recommendationType
        self.expiresAt = expiresAt
    }

    var id: String { identifier }
    var playlistMBID: UUID? {
        guard let source = URL(string: identifier),
              source.scheme?.lowercased() == "https",
              source.host?.lowercased() == "listenbrainz.org",
              source.user == nil,
              source.password == nil,
              source.port == nil || source.port == 443,
              source.query == nil,
              source.fragment == nil
        else { return nil }

        let components = source.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              components[0].lowercased() == "playlist"
        else { return nil }
        return UUID(uuidString: components[1])
    }

    var listenBrainzURL: URL? {
        guard let playlistMBID else { return nil }
        return URL(string: "https://listenbrainz.org/playlist/\(playlistMBID.uuidString)")
    }
}

struct RecommendedRecording: Identifiable, Hashable, Sendable {
    let recording: Recording
    let score: Double
    let lastListenedAt: Date?

    var id: String { recording.id }
}

struct RecordingRecommendationPage: Hashable, Sendable {
    let username: String
    let lastUpdated: Date
    let offset: Int
    let serverCount: Int
    let totalCount: Int
    let recommendations: [RecommendedRecording]

    var nextOffset: Int { offset + serverCount }
}

struct PlaylistDetail: Hashable, Sendable {
    let mbid: UUID
    let title: String
    let creator: String
    let annotation: String?
    let createdAt: Date?
    let lastModifiedAt: Date?
    let isPublic: Bool
    let createdFor: String?
    let collaborators: [String]
    let copiedFrom: String?
    let tracks: [PlaylistTrack]

    var listenBrainzURL: URL {
        URL(string: "https://listenbrainz.org/playlist/\(mbid.uuidString)")!
    }

    var totalDurationMilliseconds: Int? {
        let durations = tracks.compactMap(\.recording.durationMilliseconds)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +)
    }
}

struct PlaylistTrack: Identifiable, Hashable, Sendable {
    let position: Int
    let recording: Recording
    let addedAt: Date?
    let addedBy: String?

    var id: String { "\(position):\(recording.id)" }
}

enum SearchResult: Identifiable, Hashable, Sendable {
    case user(SearchUser)
    case artist(RankedArtist)
    case releaseGroup(SearchReleaseGroup)
    case recording(Recording)
    case playlist(SearchPlaylist)

    var id: String {
        switch self {
        case let .user(value): "user:\(value.id)"
        case let .artist(value): "artist:\(value.id)"
        case let .releaseGroup(value): "release-group:\(value.id.uuidString)"
        case let .recording(value): "recording:\(value.id)"
        case let .playlist(value): "playlist:\(value.id)"
        }
    }

    var title: String {
        switch self {
        case let .user(value): value.username
        case let .artist(value): value.name
        case let .releaseGroup(value): value.title
        case let .recording(value): value.title
        case let .playlist(value): value.title
        }
    }

    var subtitle: String? {
        switch self {
        case .user: "ListenBrainz user"
        case let .artist(value): value.listenCount > 0 ? "\(value.listenCount.formatted()) of your listens" : "MusicBrainz artist"
        case let .releaseGroup(value): [value.artistName.nilIfEmpty, value.firstReleaseDate, value.primaryType]
                .compactMap { $0 }
                .joined(separator: " · ")
        case let .recording(value): [value.artistName.nilIfEmpty, value.releaseTitle]
                .compactMap { $0 }
                .joined(separator: " · ")
        case let .playlist(value): "By \(value.creator)"
        }
    }
}

enum SearchLoadState: Equatable {
    case idle
    case waiting
    case loading
    case loaded
    case failed(String)
}

enum FreshReleasesLoadState: Equatable {
    case idle
    case loading
    case loaded([FreshRelease])
    case failed(String)
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
