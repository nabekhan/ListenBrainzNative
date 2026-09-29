import Foundation
import ListenBrainzKit
import ZIPFoundation

enum ArchivedHistoryReaderError: Error, Equatable {
    case invalidArchive
    case usernameMismatch
    case monthUnavailable
    case limitExceeded
    case cancelled
    case invalidSearchQuery
}

/// The narrow app-facing boundary for an explicitly selected local export.
/// A future snapshot model can depend on this protocol without learning about
/// ZIPFoundation or the archive's on-disk format.
protocol ArchivedHistoryReading: Sendable {
    func catalog(
        from export: UserDataExportArchive,
        expectedUsername: String
    ) async throws -> ArchivedHistoryCatalog

    func readMonth(
        from export: UserDataExportArchive,
        expectedUsername: String,
        year: Int,
        month: Int
    ) async throws -> ArchivedListenMonth

    func search(
        in export: UserDataExportArchive,
        expectedUsername: String,
        query: String
    ) async throws -> ArchivedHistorySearchResult
}

/// Explicit limits for the small, read-only archive-browsing slice. They are
/// injected in tests and deliberately apply before decompression where possible.
struct ArchivedHistoryReaderPolicy: Sendable {
    let maximumEntryCount: Int
    let maximumCompressedBytes: UInt64
    let maximumUncompressedBytes: UInt64
    let maximumCompressionRatio: UInt64
    let maximumUserJSONBytes: UInt64
    let maximumMonthBytes: UInt64
    let maximumLineBytes: Int
    let maximumRecords: Int
    let maximumRetainedTextBytes: Int
    let maximumProcessedLines: Int
    let extractionBufferSize: Int
    let maximumSearchQueryBytes: Int
    let maximumSearchResults: Int
    let maximumSearchProcessedLines: Int
    let maximumSearchUncompressedBytes: UInt64

    static let `default` = ArchivedHistoryReaderPolicy(
        maximumEntryCount: 500,
        maximumCompressedBytes: 4 * 1_024 * 1_024 * 1_024,
        maximumUncompressedBytes: 8 * 1_024 * 1_024 * 1_024,
        maximumCompressionRatio: 100,
        maximumUserJSONBytes: 512 * 1_024,
        maximumMonthBytes: 512 * 1_024 * 1_024,
        maximumLineBytes: 1 * 1_024 * 1_024,
        // Fifty thousand listens is more than one listen per minute in a
        // 31-day month. Together with the retained-text budget, this keeps the
        // fully materialized snapshot comfortably bounded on iOS.
        maximumRecords: 50_000,
        maximumRetainedTextBytes: 24 * 1_024 * 1_024,
        maximumProcessedLines: 100_000,
        extractionBufferSize: 64 * 1_024,
        maximumSearchQueryBytes: 256,
        maximumSearchResults: 500,
        maximumSearchProcessedLines: 5_000_000,
        maximumSearchUncompressedBytes: 2 * 1_024 * 1_024 * 1_024
    )
}

/// A local-only archive reader. ZIPFoundation's `Archive` is not Sendable, so
/// all archive enumeration and extraction remains actor-isolated.
actor ArchivedHistoryReader {
    private let policy: ArchivedHistoryReaderPolicy

    init(policy: ArchivedHistoryReaderPolicy = .default) {
        self.policy = policy
    }

    func catalog(
        from export: UserDataExportArchive,
        expectedUsername: String
    ) throws -> ArchivedHistoryCatalog {
        let validated = try openValidatedArchive(
            from: export,
            expectedUsername: expectedUsername
        )
        let months = validated.entries.compactMap { path, entry in
            monthDescriptor(path: path, entry: entry)
        }
        .sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.month > $1.month
        }
        return ArchivedHistoryCatalog(username: validated.username, months: months)
    }

    func readMonth(
        from export: UserDataExportArchive,
        expectedUsername: String,
        year: Int,
        month: Int
    ) throws -> ArchivedListenMonth {
        guard validYear(year), (1 ... 12).contains(month) else {
            throw ArchivedHistoryReaderError.invalidArchive
        }

        do {
            let validated = try openValidatedArchive(
                from: export,
                expectedUsername: expectedUsername
            )

            let monthPath = "listens/\(year)/\(month).jsonl"
            guard let monthEntry = validated.entries[monthPath] else {
                throw ArchivedHistoryReaderError.monthUnavailable
            }
            return try decodeMonth(
                from: validated.archive,
                entry: monthEntry,
                username: validated.username,
                year: year,
                month: month
            )
        } catch is CancellationError {
            throw ArchivedHistoryReaderError.cancelled
        } catch let error as ArchivedHistoryReaderError {
            throw error
        } catch {
            throw ArchivedHistoryReaderError.invalidArchive
        }
    }

    /// Searches a verified export in newest-month-first order. The export is
    /// opened and account-checked once; each month's existing CRC-checked
    /// decoder runs sequentially, then is released before the next month.
    /// No index, network request, or archive-derived data is persisted.
    func search(
        in export: UserDataExportArchive,
        expectedUsername: String,
        query: String
    ) throws -> ArchivedHistorySearchResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query.utf8.count <= policy.maximumSearchQueryBytes else {
            throw ArchivedHistoryReaderError.invalidSearchQuery
        }

        do {
            let validated = try openValidatedArchive(from: export, expectedUsername: expectedUsername)
            let descriptors = validated.entries.compactMap { path, entry in
                monthDescriptor(path: path, entry: entry)
            }
            .sorted {
                if $0.year != $1.year { return $0.year > $1.year }
                return $0.month > $1.month
            }

            var matches: [ArchivedHistorySearchMatch] = []
            var scannedMonths = 0
            var processedLines = 0
            var scannedBytes: UInt64 = 0
            var malformedLines = 0
            var matchLimitReached = false
            var scanLimitReached = false

            for descriptor in descriptors {
                try Task.checkCancellation()
                guard let entry = validated.entries["listens/\(descriptor.year)/\(descriptor.month).jsonl"] else {
                    throw ArchivedHistoryReaderError.invalidArchive
                }

                // Do not start a month when its established decoder could push
                // the search beyond the global scan bounds. This keeps the cap
                // exact without weakening CRC validation or retaining a partial
                // decoder state.
                guard entry.uncompressedSize <= policy.maximumSearchUncompressedBytes,
                      policy.maximumProcessedLines <= policy.maximumSearchProcessedLines,
                      scannedBytes <= policy.maximumSearchUncompressedBytes - entry.uncompressedSize,
                      processedLines <= policy.maximumSearchProcessedLines - policy.maximumProcessedLines
                else {
                    scanLimitReached = true
                    break
                }

                let month = try decodeMonth(
                    from: validated.archive,
                    entry: entry,
                    username: validated.username,
                    year: descriptor.year,
                    month: descriptor.month,
                    maximumBytes: policy.maximumSearchUncompressedBytes - scannedBytes
                )
                scannedMonths += 1
                scannedBytes += month.processedByteCount
                processedLines += month.processedLineCount
                malformedLines += month.malformedLineCount

                for listen in month.listens.reversed() {
                    try Task.checkCancellation()
                    guard matchesListen(listen, query: query) else { continue }
                    guard matches.count < policy.maximumSearchResults else {
                        matchLimitReached = true
                        break
                    }
                    matches.append(.init(listen: listen, year: descriptor.year, month: descriptor.month))
                }
                if matchLimitReached { break }
            }

            try Task.checkCancellation()
            return ArchivedHistorySearchResult(
                query: query,
                matches: matches,
                totalMonthCount: descriptors.count,
                scannedMonthCount: scannedMonths,
                malformedLineCount: malformedLines,
                matchLimitReached: matchLimitReached,
                scanLimitReached: scanLimitReached
            )
        } catch is CancellationError {
            throw ArchivedHistoryReaderError.cancelled
        } catch let error as ArchivedHistoryReaderError {
            throw error
        } catch {
            throw ArchivedHistoryReaderError.invalidArchive
        }
    }

    private func openValidatedArchive(
        from export: UserDataExportArchive,
        expectedUsername: String
    ) throws -> (archive: Archive, entries: [String: Entry], username: String) {
        guard !Task.isCancelled else { throw ArchivedHistoryReaderError.cancelled }
        guard export.fileURL.isFileURL,
              let expected = normalizedUsername(expectedUsername)
        else { throw ArchivedHistoryReaderError.invalidArchive }

        do {
            let values = try export.fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let size = values.fileSize,
                  size >= 0,
                  UInt64(size) <= policy.maximumCompressedBytes
            else { throw ArchivedHistoryReaderError.invalidArchive }

            let archive = try Archive(url: export.fileURL, accessMode: .read)
            let entries = try validatedEntries(in: archive)
            guard let userEntry = entries["user.json"] else {
                throw ArchivedHistoryReaderError.invalidArchive
            }
            let username = try readUsername(from: archive, entry: userEntry)
            guard normalizedUsername(username) == expected else {
                throw ArchivedHistoryReaderError.usernameMismatch
            }
            return (archive, entries, username)
        } catch is CancellationError {
            throw ArchivedHistoryReaderError.cancelled
        } catch let error as ArchivedHistoryReaderError {
            throw error
        } catch {
            throw ArchivedHistoryReaderError.invalidArchive
        }
    }

    private func validatedEntries(in archive: Archive) throws -> [String: Entry] {
        var entries: [String: Entry] = [:]
        var totalUncompressed: UInt64 = 0
        var totalCompressed: UInt64 = 0

        for entry in archive {
            try Task.checkCancellation()
            guard entries.count < policy.maximumEntryCount else {
                throw ArchivedHistoryReaderError.limitExceeded
            }
            guard entry.type == .file,
                  validArchivePath(entry.path),
                  entries[entry.path] == nil
            else { throw ArchivedHistoryReaderError.invalidArchive }
            guard entry.uncompressedSize <= policy.maximumUncompressedBytes,
                  !exceedsCompressionRatio(uncompressed: entry.uncompressedSize, compressed: entry.compressedSize)
            else { throw ArchivedHistoryReaderError.limitExceeded }

            totalUncompressed = try adding(entry.uncompressedSize, to: totalUncompressed)
            totalCompressed = try adding(entry.compressedSize, to: totalCompressed)
            guard totalUncompressed <= policy.maximumUncompressedBytes,
                  totalCompressed <= policy.maximumCompressedBytes
            else { throw ArchivedHistoryReaderError.limitExceeded }
            entries[entry.path] = entry
        }
        guard entries["user.json"] != nil else { throw ArchivedHistoryReaderError.invalidArchive }
        return entries
    }

    private func readUsername(from archive: Archive, entry: Entry) throws -> String {
        guard entry.uncompressedSize <= policy.maximumUserJSONBytes else {
            throw ArchivedHistoryReaderError.limitExceeded
        }
        let data = try readData(from: archive, entry: entry, maximumBytes: policy.maximumUserJSONBytes)
        struct User: Decodable { let username: String }
        let user = try JSONDecoder().decode(User.self, from: data)
        guard normalizedUsername(user.username) != nil else { throw ArchivedHistoryReaderError.invalidArchive }
        return user.username
    }

    private func decodeMonth(
        from archive: Archive,
        entry: Entry,
        username: String,
        year: Int,
        month: Int,
        maximumBytes: UInt64? = nil
    ) throws -> ArchivedListenMonth {
        let byteLimit = min(maximumBytes ?? policy.maximumMonthBytes, policy.maximumMonthBytes)
        guard entry.uncompressedSize <= byteLimit else {
            throw ArchivedHistoryReaderError.limitExceeded
        }

        // A policy ceiling bounds legitimate entries, while the entry's own
        // declared size bounds the extractor itself. A forged central
        // directory must not be allowed to expand to the broader policy cap
        // before the exact-size check below rejects it.
        let state = MonthDecodeState(policy: policy, maximumByteCount: entry.uncompressedSize)

        let checksum = try archive.extract(
            entry,
            bufferSize: policy.extractionBufferSize,
            skipCRC32: false,
            progress: nil
        ) { chunk in
            try state.append(chunk)
        }
        guard checksum == entry.checksum else {
            throw ArchivedHistoryReaderError.invalidArchive
        }
        try state.finish()
        let result = state.result()
        guard result.processedByteCount == entry.uncompressedSize else {
            throw ArchivedHistoryReaderError.invalidArchive
        }

        return ArchivedListenMonth(
            username: username,
            year: year,
            month: month,
            listens: result.listens,
            blankLineCount: result.blankLineCount,
            malformedLineCount: result.malformedLineCount,
            processedLineCount: result.processedLineCount,
            processedByteCount: result.processedByteCount
        )
    }

    private func readData(from archive: Archive, entry: Entry, maximumBytes: UInt64) throws -> Data {
        guard entry.uncompressedSize <= maximumBytes else {
            throw ArchivedHistoryReaderError.limitExceeded
        }
        let output = DataDecodeState()
        let checksum = try archive.extract(entry, bufferSize: policy.extractionBufferSize, skipCRC32: false, progress: nil) { chunk in
            try output.append(chunk, expectedByteCount: entry.uncompressedSize)
        }
        guard checksum == entry.checksum else {
            throw ArchivedHistoryReaderError.invalidArchive
        }
        let value = output.value()
        guard UInt64(value.count) == entry.uncompressedSize else {
            throw ArchivedHistoryReaderError.invalidArchive
        }
        return value
    }

    private func validArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.allSatisfy({ $0 <= 0x7F }) else { return false }
        if path == "user.json" || path == "feedback.jsonl" || path == "pinned_recording.jsonl" { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "listens",
              parts[2].hasSuffix(".jsonl"),
              parts[2].dropLast(".jsonl".count).allSatisfy({ $0.isNumber }),
              parts[1].allSatisfy({ $0.isNumber }),
              let year = Int(parts[1]), validYear(year),
              let month = Int(parts[2].dropLast(".jsonl".count)), (1 ... 12).contains(month),
              parts[2] == "\(month).jsonl"
        else { return false }
        return true
    }

    private func monthDescriptor(path: String, entry: Entry) -> ArchivedHistoryMonthDescriptor? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "listens",
              let year = Int(parts[1]),
              parts[2].hasSuffix(".jsonl"),
              let month = Int(parts[2].dropLast(".jsonl".count))
        else { return nil }
        return ArchivedHistoryMonthDescriptor(
            year: year,
            month: month,
            uncompressedByteCount: entry.uncompressedSize
        )
    }

    private func normalizedUsername(_ username: String) -> String? {
        let normalized = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty, normalized.utf8.count <= 255,
              normalized.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return normalized.lowercased()
    }

    private func validYear(_ year: Int) -> Bool { (1970 ... 9_999).contains(year) }

    private func matchesListen(_ listen: ArchivedListen, query: String) -> Bool {
        listen.title.localizedCaseInsensitiveContains(query)
            || listen.artistName.localizedCaseInsensitiveContains(query)
            || (listen.releaseTitle?.localizedCaseInsensitiveContains(query) == true)
    }

    private func adding(_ value: UInt64, to total: UInt64) throws -> UInt64 {
        let result = total.addingReportingOverflow(value)
        guard !result.overflow else { throw ArchivedHistoryReaderError.limitExceeded }
        return result.partialValue
    }

    private func exceedsCompressionRatio(uncompressed: UInt64, compressed: UInt64) -> Bool {
        guard compressed > 0 else { return uncompressed > 0 }
        let quotient = uncompressed / compressed
        let remainder = uncompressed % compressed
        return quotient > policy.maximumCompressionRatio
            || (quotient == policy.maximumCompressionRatio && remainder > 0)
    }
}

extension ArchivedHistoryReader: ArchivedHistoryReading {}

/// ZIPFoundation's consumer closure is Sendable even though extraction invokes
/// it synchronously. These small locked states keep that boundary explicit and
/// do not allow an archive callback to race with result collection.
private final class MonthDecodeState: @unchecked Sendable {
    private let lock = NSLock()
    private let policy: ArchivedHistoryReaderPolicy
    private let maximumByteCount: UInt64
    private let decoder: JSONDecoder
    private var pending = Data()
    private var listens: [ArchivedListen] = []
    private var blankLineCount = 0
    private var malformedLineCount = 0
    private var previousDate: Date?
    private var sourceLineNumber = 0
    private var totalByteCount: UInt64 = 0
    private var retainedTextByteCount = 0

    init(policy: ArchivedHistoryReaderPolicy, maximumByteCount: UInt64) {
        self.policy = policy
        self.maximumByteCount = maximumByteCount
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    func append(_ chunk: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try Task.checkCancellation()
        let chunkByteCount = UInt64(chunk.count)
        guard chunkByteCount <= maximumByteCount,
              totalByteCount <= maximumByteCount - chunkByteCount
        else { throw ArchivedHistoryReaderError.invalidArchive }
        totalByteCount += chunkByteCount
        pending.append(chunk)

        var lineStart = pending.startIndex
        var cursor = lineStart
        while cursor < pending.endIndex {
            if pending[cursor] == 10 {
                try consume(Data(pending[lineStart ..< cursor]))
                lineStart = pending.index(after: cursor)
            }
            cursor = pending.index(after: cursor)
        }
        if lineStart != pending.startIndex {
            pending.removeSubrange(pending.startIndex ..< lineStart)
        }
        guard pending.count <= policy.maximumLineBytes else {
            throw ArchivedHistoryReaderError.limitExceeded
        }
    }

    func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        try Task.checkCancellation()
        if !pending.isEmpty { try consume(pending) }
        pending.removeAll(keepingCapacity: false)
    }

    func result() -> (
        listens: [ArchivedListen],
        blankLineCount: Int,
        malformedLineCount: Int,
        processedLineCount: Int,
        processedByteCount: UInt64
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (listens, blankLineCount, malformedLineCount, sourceLineNumber, totalByteCount)
    }

    private func consume(_ line: Data) throws {
        try Task.checkCancellation()
        guard sourceLineNumber < policy.maximumProcessedLines else {
            throw ArchivedHistoryReaderError.limitExceeded
        }
        sourceLineNumber += 1
        let trimmed = line.last == 13 ? line.dropLast() : line[...]
        guard !trimmed.isEmpty else {
            blankLineCount += 1
            return
        }
        guard trimmed.count <= policy.maximumLineBytes else {
            throw ArchivedHistoryReaderError.limitExceeded
        }
        do {
            let listen = try decoder.decode(LBListen.self, from: Data(trimmed))
            guard previousDate == nil || previousDate! <= listen.listenedAt else {
                throw ArchivedHistoryReaderError.invalidArchive
            }
            guard listens.count < policy.maximumRecords else {
                throw ArchivedHistoryReaderError.limitExceeded
            }
            let recording = ListenBrainzProvider.map(listen.trackMetadata, msid: listen.recordingMsid)
            let textByteCount = try retainedTextBytes(
                title: recording.title,
                artistName: recording.artistName,
                releaseTitle: recording.releaseTitle
            )
            guard textByteCount <= policy.maximumRetainedTextBytes,
                  retainedTextByteCount <= policy.maximumRetainedTextBytes - textByteCount
            else { throw ArchivedHistoryReaderError.limitExceeded }
            retainedTextByteCount += textByteCount
            previousDate = listen.listenedAt
            listens.append(ArchivedListen(
                title: recording.title,
                artistName: recording.artistName,
                releaseTitle: recording.releaseTitle,
                listenedAt: listen.listenedAt,
                sourceLineNumber: sourceLineNumber
            ))
        } catch let error as ArchivedHistoryReaderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            malformedLineCount += 1
        }
    }

    private func retainedTextBytes(
        title: String,
        artistName: String,
        releaseTitle: String?
    ) throws -> Int {
        var total = 0
        for value in [title, artistName, releaseTitle].compactMap({ $0 }) {
            let result = total.addingReportingOverflow(value.utf8.count)
            guard !result.overflow else { throw ArchivedHistoryReaderError.limitExceeded }
            total = result.partialValue
        }
        return total
    }
}

private final class DataDecodeState: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data, expectedByteCount: UInt64) throws {
        lock.lock()
        defer { lock.unlock() }
        try Task.checkCancellation()
        guard UInt64(chunk.count) <= expectedByteCount,
              UInt64(data.count) <= expectedByteCount - UInt64(chunk.count)
        else { throw ArchivedHistoryReaderError.invalidArchive }
        data.append(chunk)
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
