import Foundation
import ListenBrainzKit

/// The presentation-neutral subset of ListenBrainz's annual report used by the
/// native retrospective.  It deliberately keeps release-group and release
/// identities separate: a Year in Music "album" is a release group, while a
/// recording may point at one concrete release for artwork.
struct YearInMusicReport: Hashable, Sendable {
    let username: String?
    let year: Int
    let totals: Totals
    let listeningDays: [ListeningDay]
    let topArtists: [RankedArtist]
    let topReleaseGroups: [ReleaseGroup]
    let topRecordings: [TopRecording]

    var isEmpty: Bool {
        totals.listenCount == 0
            && listeningDays.allSatisfy { $0.listenCount == 0 }
            && topArtists.isEmpty
            && topReleaseGroups.isEmpty
            && topRecordings.isEmpty
    }

    struct Totals: Hashable, Sendable {
        let listenCount: Int
        let artistCount: Int
        let recordingCount: Int
        let releaseGroupCount: Int
        let newArtistCount: Int
        /// ListenBrainz reports seconds, potentially with fractional values.
        let listeningTime: TimeInterval
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

    struct TopRecording: Identifiable, Hashable, Sendable {
        let recording: Recording
        let listenCount: Int
        let coverArtArchiveID: Int?

        var id: String { recording.id }
        var artworkURL: URL? { recording.artworkURL }
    }

    /// Internal construction path for deterministic previews and tests. Live
    /// reports continue to enter through the schema-normalizing initializer.
    init(
        username: String?,
        year: Int,
        totals: Totals,
        listeningDays: [ListeningDay],
        topArtists: [RankedArtist],
        topReleaseGroups: [ReleaseGroup],
        topRecordings: [TopRecording]
    ) {
        self.username = username
        self.year = year
        self.totals = totals
        self.listeningDays = listeningDays
        self.topArtists = topArtists
        self.topReleaseGroups = topReleaseGroups
        self.topRecordings = topRecordings
    }

    /// Maps only a report the API says exists.  `nil` is intentionally
    /// distinct from a legitimate report containing zero listens.
    init?(source: LBYearInMusic, requestedYear: Int) {
        guard source.isAvailable else { return nil }
        let data = source.data
        username = source.userName?.trimmedNilIfEmpty
        year = source.year ?? requestedYear
        totals = .init(
            listenCount: Self.nonNegative(data.totalListenCount),
            artistCount: Self.nonNegative(data.totalArtistsCount),
            recordingCount: Self.nonNegative(data.totalRecordingsCount),
            releaseGroupCount: Self.nonNegative(data.totalReleaseGroupsCount),
            newArtistCount: Self.nonNegative(data.totalNewArtistsDiscovered),
            listeningTime: Self.nonNegative(data.totalListeningTime)
        )
        listeningDays = Self.mapListeningDays(data.listensPerDay, year: year)
        topArtists = Self.mapArtists(data.topArtists)
        topReleaseGroups = Self.mapReleaseGroups(data.topReleaseGroups)
        topRecordings = Self.mapRecordings(data.topRecordings)
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
            let candidate = Candidate(mbid: row.mbid.flatMap(UUID.init(uuidString:)), name: name, count: nonNegative(row.listenCount))
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

    private static func mapReleaseGroups(_ source: [LBYearInMusic.Report.ReleaseGroup]) -> [ReleaseGroup] {
        enum Key: Hashable { case mbid(UUID), fallback(String) }
        var values: [Key: ReleaseGroup] = [:]
        for row in source {
            let title = row.name?.trimmedNilIfEmpty ?? "Untitled release"
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
            let title = row.trackName?.trimmedNilIfEmpty ?? "Untitled recording"
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
        return credits?.trimmedNilIfEmpty ?? "Unknown artist"
    }

    private static func normalizedUUIDs(_ values: [String]?) -> [UUID] {
        Array(Set((values ?? []).compactMap(UUID.init(uuidString:)))).sorted { $0.uuidString < $1.uuidString }
    }

    private static func nonNegative(_ value: Int?) -> Int { max(0, value ?? 0) }
    private static func nonNegativeOptional(_ value: Int?) -> Int? { value.map { max(0, $0) } }
    private static func nonNegative(_ value: Double?) -> TimeInterval {
        guard let value, value.isFinite else { return 0 }
        return max(0, value)
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
