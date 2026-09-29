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

    init(
        username: String,
        year: Int,
        month: Int,
        listens: [ArchivedListen],
        blankLineCount: Int,
        malformedLineCount: Int
    ) {
        self.username = username
        self.year = year
        self.month = month
        self.listens = listens
        self.blankLineCount = blankLineCount
        self.malformedLineCount = malformedLineCount
    }
}
