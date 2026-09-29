import Foundation
import XCTest
import ZIPFoundation
@testable import Brainz

final class ArchivedHistoryReaderTests: XCTestCase {
    func testCatalogValidatesAccountAndReturnsNewestMonthsWithoutReadingRows() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"user_id":1,"username":" nabecite "}"#.utf8)),
            ("listens/2025/12.jsonl", Data("not JSON and deliberately not decoded".utf8)),
            ("listens/2026/1.jsonl", Data()),
            ("listens/2026/9.jsonl", Data()),
            ("feedback.jsonl", Data())
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let catalog = try await ArchivedHistoryReader().catalog(
            from: archive,
            expectedUsername: "NABECITE"
        )

        XCTAssertEqual(catalog.username, " nabecite ")
        XCTAssertEqual(catalog.months.map(\.id), ["2026-9", "2026-1", "2025-12"])
    }

    func testReadsMappedAndUnmappedRowsAcrossSmallChunks() async throws {
        let mappedRecording = UUID()
        let msid = UUID()
        let rows = [
            listenJSON(timestamp: 100, msid: msid, mappingRecording: mappedRecording),
            Data(),
            Data("not JSON".utf8),
            listenJSON(timestamp: 101, msid: UUID(), mappingRecording: nil)
        ]
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"user_id":1,"username":"NabéCite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL(rows))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let reader = ArchivedHistoryReader(policy: policy(extractionBufferSize: 7))
        let month = try await reader.readMonth(
            from: archive,
            expectedUsername: "nabe\u{301}cite",
            year: 2026,
            month: 9
        )

        XCTAssertEqual(month.username, "NabéCite")
        XCTAssertEqual(month.listens.count, 2)
        XCTAssertEqual(month.blankLineCount, 1)
        XCTAssertEqual(month.malformedLineCount, 1)
        XCTAssertEqual(month.listens[0].title, "Track")
        XCTAssertEqual(month.listens[0].artistName, "Artist")
        XCTAssertEqual(month.listens[0].releaseTitle, "Release")
    }

    func testEqualTimestampDuplicateListensKeepDistinctStableIdentities() async throws {
        let msid = UUID()
        let duplicate = listenJSON(timestamp: 100, msid: msid, mappingRecording: nil)
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL([duplicate, duplicate]))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let month = try await ArchivedHistoryReader().readMonth(
            from: archive,
            expectedUsername: "nabecite",
            year: 2026,
            month: 9
        )

        XCTAssertEqual(month.listens.count, 2)
        XCTAssertNotEqual(month.listens[0].id, month.listens[1].id)
        XCTAssertEqual(month.listens.map(\.sourceLineNumber), [1, 2])
    }

    func testReadsCRLFAndFinalLineWithoutNewline() async throws {
        let first = listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil)
        let second = listenJSON(timestamp: 101, msid: UUID(), mappingRecording: nil)
        var payload = first
        payload.append(contentsOf: [13, 10])
        payload.append(second)
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", payload)
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let month = try await ArchivedHistoryReader(policy: policy(extractionBufferSize: 3)).readMonth(
            from: archive,
            expectedUsername: "nabecite",
            year: 2026,
            month: 9
        )
        XCTAssertEqual(month.listens.count, 2)
        XCTAssertEqual(month.malformedLineCount, 0)
    }

    func testMissingMonthIsReportedAfterCatalogValidation() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/8.jsonl", Data())
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        await assertReaderError(.monthUnavailable, reader: ArchivedHistoryReader(), archive: archive)
    }

    func testRejectsDescendingTimestamp() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL([
                listenJSON(timestamp: 101, msid: UUID(), mappingRecording: nil),
                listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil)
            ]))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        await assertReaderError(.invalidArchive, reader: ArchivedHistoryReader(), archive: archive)
    }

    func testRejectsUnexpectedTraversalAndDuplicateEntries() async throws {
        for badPath in ["listens/2026/09.jsonl", "listens/2026/9.jsonl/../../user.json", "other.json"] {
            let archive = try makeArchive(entries: [
                ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
                (badPath, Data())
            ])
            defer { try? FileManager.default.removeItem(at: archive.fileURL) }
            await assertReaderError(.invalidArchive, reader: ArchivedHistoryReader(), archive: archive)
        }

        let duplicate = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", Data()),
            ("listens/2026/9.jsonl", Data())
        ])
        defer { try? FileManager.default.removeItem(at: duplicate.fileURL) }
        await assertReaderError(.invalidArchive, reader: ArchivedHistoryReader(), archive: duplicate)
    }

    func testRejectsWrongUsernameAndPolicyLimits() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"another-user"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL([listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil)]))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        await assertReaderError(.usernameMismatch, reader: ArchivedHistoryReader(), archive: archive)

        let lineLimitArchive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL([listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil)]))
        ])
        defer { try? FileManager.default.removeItem(at: lineLimitArchive.fileURL) }
        await assertReaderError(
            .limitExceeded,
            reader: ArchivedHistoryReader(policy: policy(maximumLineBytes: 8)),
            archive: lineLimitArchive
        )
    }

    func testRejectsCorruptedUserAndMonthEntriesAfterStreaming() async throws {
        let userArchive = try makeArchive(
            entries: [
                ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
                ("listens/2026/9.jsonl", Data())
            ],
            compressionMethod: .none
        )
        defer { try? FileManager.default.removeItem(at: userArchive.fileURL) }
        try replaceBytes(
            Data("nabecite".utf8),
            with: Data("mabecite".utf8),
            in: userArchive.fileURL
        )
        await assertReaderError(.invalidArchive, reader: ArchivedHistoryReader(), archive: userArchive)

        let monthArchive = try makeArchive(
            entries: [
                ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
                ("listens/2026/9.jsonl", joinedJSONL([
                    listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil)
                ]))
            ],
            compressionMethod: .none
        )
        defer { try? FileManager.default.removeItem(at: monthArchive.fileURL) }
        try replaceBytes(Data("Track".utf8), with: Data("Crack".utf8), in: monthArchive.fileURL)
        await assertReaderError(.invalidArchive, reader: ArchivedHistoryReader(), archive: monthArchive)
    }

    func testRejectsEntryWhoseDeclaredSizeDoesNotMatchExtractedBytes() async throws {
        let path = "listens/2026/9.jsonl"
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            (path, joinedJSONL([
                listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil)
            ]))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        try replaceCentralDirectoryUncompressedSize(for: path, with: 1, in: archive.fileURL)
        let patched = try Archive(url: archive.fileURL, accessMode: .read)
        XCTAssertEqual(try XCTUnwrap(patched[path]).uncompressedSize, 1)

        // The deliberately tiny line ceiling would win if extraction were
        // allowed to continue toward the broader policy limit. Declared-size
        // enforcement must reject the second emitted byte first.
        await assertReaderError(
            .invalidArchive,
            reader: ArchivedHistoryReader(policy: policy(maximumLineBytes: 8)),
            archive: archive
        )
    }

    func testCancellationBeforeReadIsReported() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL([listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil)]))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        let reader = ArchivedHistoryReader()
        let task = Task { try await reader.readMonth(from: archive, expectedUsername: "nabecite", year: 2026, month: 9) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as ArchivedHistoryReaderError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testCancellationDuringStreamingIsReported() async throws {
        let archive = try makeArchive(
            entries: [
                ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
                ("listens/2026/9.jsonl", Data(repeating: 10, count: 2_000_000))
            ],
            compressionMethod: .none
        )
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        let reader = ArchivedHistoryReader(
            policy: policy(maximumProcessedLines: 2_000_001, extractionBufferSize: 1)
        )
        let task = Task {
            try await reader.readMonth(
                from: archive,
                expectedUsername: "nabecite",
                year: 2026,
                month: 9
            )
        }
        try await Task.sleep(for: .milliseconds(2))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected in-flight cancellation")
        } catch let error as ArchivedHistoryReaderError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testRecordAndEntryCountLimitsFailClosed() async throws {
        let recordArchive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL([
                listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil),
                listenJSON(timestamp: 101, msid: UUID(), mappingRecording: nil)
            ]))
        ])
        defer { try? FileManager.default.removeItem(at: recordArchive.fileURL) }
        await assertReaderError(
            .limitExceeded,
            reader: ArchivedHistoryReader(policy: policy(maximumRecords: 1)),
            archive: recordArchive
        )

        let entryArchive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", Data())
        ])
        defer { try? FileManager.default.removeItem(at: entryArchive.fileURL) }
        await assertReaderError(
            .limitExceeded,
            reader: ArchivedHistoryReader(policy: policy(maximumEntryCount: 1)),
            archive: entryArchive
        )

        let denseLinesArchive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", Data("\n\n\n".utf8))
        ])
        defer { try? FileManager.default.removeItem(at: denseLinesArchive.fileURL) }
        await assertReaderError(
            .limitExceeded,
            reader: ArchivedHistoryReader(policy: policy(maximumProcessedLines: 2, extractionBufferSize: 1)),
            archive: denseLinesArchive
        )
    }

    func testRetainedTextBudgetFailsClosed() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL([
                listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil)
            ]))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        await assertReaderError(
            .limitExceeded,
            reader: ArchivedHistoryReader(policy: policy(maximumRetainedTextBytes: 10)),
            archive: archive
        )
    }

    func testSearchReturnsNewestFirstAcrossMonthsAndTracksOnlyMalformedRows() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/8.jsonl", joinedJSONL([
                listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil, title: "Older Song"),
                Data(),
                Data("not JSON".utf8)
            ])),
            ("listens/2026/9.jsonl", joinedJSONL([
                listenJSON(timestamp: 200, msid: UUID(), mappingRecording: nil, artist: "Newest Artist"),
                listenJSON(timestamp: 201, msid: UUID(), mappingRecording: nil, release: "Newest Release")
            ]))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let result = try await ArchivedHistoryReader().search(
            in: archive,
            expectedUsername: "nabecite",
            query: "newest"
        )

        XCTAssertEqual(result.matches.map(\.listen.listenedAt), [
            Date(timeIntervalSince1970: 201),
            Date(timeIntervalSince1970: 200)
        ])
        XCTAssertEqual(result.scannedMonthCount, 2)
        XCTAssertEqual(result.totalMonthCount, 2)
        XCTAssertEqual(result.malformedLineCount, 1)
        XCTAssertFalse(result.isPartial)
    }

    func testSearchReportsPartialCoverageAtGlobalMatchAndScanLimits() async throws {
        let rows = (0 ..< 3).map { index in
            listenJSON(timestamp: 100 + index, msid: UUID(), mappingRecording: nil, title: "Find me")
        }
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL(rows)),
            ("listens/2026/8.jsonl", joinedJSONL(rows))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let matchLimited = try await ArchivedHistoryReader(policy: policy(maximumSearchResults: 2)).search(
            in: archive,
            expectedUsername: "nabecite",
            query: "find"
        )
        XCTAssertEqual(matchLimited.matches.count, 2)
        XCTAssertTrue(matchLimited.matchLimitReached)
        XCTAssertEqual(matchLimited.scannedMonthCount, 1)

        let scanLimited = try await ArchivedHistoryReader(policy: policy(
            maximumSearchProcessedLines: 100_000,
            maximumSearchUncompressedBytes: 1_000_000
        )).search(in: archive, expectedUsername: "nabecite", query: "missing")
        XCTAssertTrue(scanLimited.scanLimitReached)
        XCTAssertEqual(scanLimited.scannedMonthCount, 1)
        XCTAssertEqual(scanLimited.totalMonthCount, 2)
    }

    func testSearchDoesNotClaimTruncationAtTheExactMatchLimit() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8)),
            ("listens/2026/9.jsonl", joinedJSONL([
                listenJSON(timestamp: 100, msid: UUID(), mappingRecording: nil, title: "Find me"),
                listenJSON(timestamp: 101, msid: UUID(), mappingRecording: nil, title: "Find me")
            ]))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let result = try await ArchivedHistoryReader(policy: policy(maximumSearchResults: 2)).search(
            in: archive,
            expectedUsername: "nabecite",
            query: "find"
        )

        XCTAssertEqual(result.matches.count, 2)
        XCTAssertFalse(result.matchLimitReached)
        XCTAssertFalse(result.isPartial)
    }

    func testSearchEnforcesCharacterMinimumAndUTF8ByteCeilingIndependently() async throws {
        let archive = try makeArchive(entries: [
            ("user.json", Data(#"{"username":"nabecite"}"#.utf8))
        ])
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        let threeByteReader = ArchivedHistoryReader(policy: policy(maximumSearchQueryBytes: 3))

        for query in [" ", "a", "é", "éé", "four"] {
            do {
                _ = try await threeByteReader.search(
                    in: archive,
                    expectedUsername: "nabecite",
                    query: query
                )
                XCTFail("Expected invalid query for \(query)")
            } catch let error as ArchivedHistoryReaderError {
                XCTAssertEqual(error, .invalidSearchQuery)
            }
        }

        let exactMultibyteBoundary = try await ArchivedHistoryReader(
            policy: policy(maximumSearchQueryBytes: 4)
        ).search(in: archive, expectedUsername: "nabecite", query: "éé")
        XCTAssertTrue(exactMultibyteBoundary.matches.isEmpty)
    }

    private func assertReaderError(
        _ expected: ArchivedHistoryReaderError,
        reader: ArchivedHistoryReader,
        archive: UserDataExportArchive,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await reader.readMonth(from: archive, expectedUsername: "nabecite", year: 2026, month: 9)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ArchivedHistoryReaderError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func makeArchive(
        entries: [(String, Data)],
        compressionMethod: CompressionMethod = .deflate
    ) throws -> UserDataExportArchive {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ArchivedHistoryReaderTests-\(UUID().uuidString).zip", directoryHint: .notDirectory)
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: compressionMethod
            ) { position, size in
                let start = Int(position)
                guard start < data.count else { return Data() }
                return data.subdata(in: start ..< min(start + size, data.count))
            }
        }
        return UserDataExportArchive(
            exportID: 1,
            range: .all,
            downloadedAt: .now,
            byteCount: (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0,
            fileURL: url
        )
    }

    private func replaceBytes(_ original: Data, with replacement: Data, in url: URL) throws {
        XCTAssertEqual(original.count, replacement.count)
        var bytes = try Data(contentsOf: url)
        let range = try XCTUnwrap(bytes.range(of: original))
        bytes.replaceSubrange(range, with: replacement)
        try bytes.write(to: url, options: .atomic)
    }

    private func replaceCentralDirectoryUncompressedSize(
        for path: String,
        with size: UInt32,
        in url: URL
    ) throws {
        var bytes = try Data(contentsOf: url)
        let signature = Data([0x50, 0x4B, 0x01, 0x02])
        var searchStart = bytes.startIndex

        while let range = bytes.range(of: signature, in: searchStart ..< bytes.endIndex) {
            let header = range.lowerBound
            guard header + 46 <= bytes.endIndex else { break }
            let nameLength = Int(bytes.littleEndianUInt16(at: header + 28))
            let extraLength = Int(bytes.littleEndianUInt16(at: header + 30))
            let commentLength = Int(bytes.littleEndianUInt16(at: header + 32))
            let nameStart = header + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= bytes.endIndex else { break }

            if String(data: bytes[nameStart ..< nameEnd], encoding: .utf8) == path {
                var littleEndianSize = size.littleEndian
                withUnsafeBytes(of: &littleEndianSize) { replacement in
                    bytes.replaceSubrange(header + 24 ..< header + 28, with: replacement)
                }
                try bytes.write(to: url, options: .atomic)
                return
            }

            searchStart = nameEnd + extraLength + commentLength
        }

        XCTFail("Central directory entry not found for \(path)")
    }

    private func joinedJSONL(_ rows: [Data]) -> Data {
        rows.reduce(into: Data()) { output, row in
            output.append(row)
            output.append(10)
        }
    }

    private func listenJSON(
        timestamp: Int,
        msid: UUID,
        mappingRecording: UUID?,
        title: String = "Track",
        artist: String = "Artist",
        release: String = "Release"
    ) -> Data {
        let mapping = mappingRecording.map { "\"mbid_mapping\":{\"recording_mbid\":\"\($0.uuidString)\"}" } ?? "\"mbid_mapping\":null"
        return Data("""
        {"inserted_at":\(timestamp + 1),"listened_at":\(timestamp),"recording_msid":"\(msid.uuidString)","track_metadata":{"artist_name":"\(artist)","track_name":"\(title)","release_name":"\(release)",\(mapping)}}
        """.utf8)
    }

    private func policy(
        maximumEntryCount: Int = 500,
        maximumLineBytes: Int = 1_024 * 1_024,
        maximumRecords: Int = 50_000,
        maximumRetainedTextBytes: Int = 24 * 1_024 * 1_024,
        maximumProcessedLines: Int = 100_000,
        extractionBufferSize: Int = 64 * 1_024,
        maximumSearchQueryBytes: Int = 256,
        maximumSearchResults: Int = 500,
        maximumSearchProcessedLines: Int = 5_000_000,
        maximumSearchUncompressedBytes: UInt64 = 2 * 1_024 * 1_024 * 1_024
    ) -> ArchivedHistoryReaderPolicy {
        ArchivedHistoryReaderPolicy(
            maximumEntryCount: maximumEntryCount,
            maximumCompressedBytes: 4 * 1_024 * 1_024 * 1_024,
            maximumUncompressedBytes: 8 * 1_024 * 1_024 * 1_024,
            maximumCompressionRatio: 100,
            maximumUserJSONBytes: 512 * 1_024,
            maximumMonthBytes: 512 * 1_024 * 1_024,
            maximumLineBytes: maximumLineBytes,
            maximumRecords: maximumRecords,
            maximumRetainedTextBytes: maximumRetainedTextBytes,
            maximumProcessedLines: maximumProcessedLines,
            extractionBufferSize: extractionBufferSize,
            maximumSearchQueryBytes: maximumSearchQueryBytes,
            maximumSearchResults: maximumSearchResults,
            maximumSearchProcessedLines: maximumSearchProcessedLines,
            maximumSearchUncompressedBytes: maximumSearchUncompressedBytes
        )
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
}
