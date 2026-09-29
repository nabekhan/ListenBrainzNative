import Foundation

/// A listen read from an explicit, local ListenBrainz export. It deliberately
/// stays separate from live `Listen` values: an export is a dated snapshot, not
/// an incrementally refreshed History page.
struct ArchivedListen: Identifiable, Hashable, Sendable {
    /// Snapshot browsing only needs these three display fields. Keeping the
    /// full Recording and ListenInspection graphs for every row would make a
    /// large, otherwise valid export an avoidable resident-memory risk.
    let title: String
    let artistName: String
    let releaseTitle: String?
    let listenedAt: Date
    /// The one-based source line keeps legitimate duplicate listens distinct
    /// without inventing a remote identity or changing their archive order.
    let sourceLineNumber: Int

    var id: Int { sourceLineNumber }
}

struct ArchivedHistoryMonthDescriptor: Identifiable, Hashable, Sendable {
    let year: Int
    let month: Int
    let uncompressedByteCount: UInt64

    var id: String { "\(year)-\(month)" }
}

struct ArchivedHistoryCatalog: Hashable, Sendable {
    let username: String
    /// Newest first for a useful, bounded navigation surface. Opening the
    /// catalogue reads ZIP metadata and user.json only; it never parses months.
    let months: [ArchivedHistoryMonthDescriptor]
}

/// The result of reading exactly one month from one verified account export.
/// Counters make the source's tolerantly skipped blank or malformed JSONL rows
/// observable to a future UI without inventing replacement listen data.
struct ArchivedListenMonth: Hashable, Sendable {
    let username: String
    let year: Int
    let month: Int
    let listens: [ArchivedListen]
    let blankLineCount: Int
    let malformedLineCount: Int
    /// Includes valid, blank, and malformed JSONL rows. This is intentionally
    /// retained as a count only: a whole-archive search never needs to hold an
    /// unbounded index of the source file in memory.
    let processedLineCount: Int
    /// The exact bytes produced by the verified ZIP extraction. Keeping this
    /// separate from ZIP metadata lets aggregate scans enforce real work.
    let processedByteCount: UInt64

    init(
        username: String,
        year: Int,
        month: Int,
        listens: [ArchivedListen],
        blankLineCount: Int,
        malformedLineCount: Int,
        processedLineCount: Int? = nil,
        processedByteCount: UInt64 = 0
    ) {
        self.username = username
        self.year = year
        self.month = month
        self.listens = listens
        self.blankLineCount = blankLineCount
        self.malformedLineCount = malformedLineCount
        self.processedLineCount = processedLineCount ?? listens.count + blankLineCount + malformedLineCount
        self.processedByteCount = processedByteCount
    }
}

/// A local match carries its source month so duplicate line numbers in
/// different monthly files remain distinct without creating a remote identity.
struct ArchivedHistorySearchMatch: Identifiable, Hashable, Sendable {
    let listen: ArchivedListen
    let year: Int
    let month: Int

    var id: String { "\(year)-\(month)-\(listen.sourceLineNumber)" }
}

/// The bounded result of an explicit, device-only archive scan. Limit flags
/// are part of the model so the UI never presents a partial scan as complete.
struct ArchivedHistorySearchResult: Hashable, Sendable {
    let query: String
    let matches: [ArchivedHistorySearchMatch]
    let totalMonthCount: Int
    let scannedMonthCount: Int
    let malformedLineCount: Int
    let matchLimitReached: Bool
    let scanLimitReached: Bool

    var isPartial: Bool { matchLimitReached || scanLimitReached }
}
