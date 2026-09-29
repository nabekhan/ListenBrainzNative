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

    private func joinedJSONL(_ rows: [Data]) -> Data {
        rows.reduce(into: Data()) { output, row in
            output.append(row)
            output.append(10)
        }
    }

    private func listenJSON(timestamp: Int, msid: UUID, mappingRecording: UUID?) -> Data {
        let mapping = mappingRecording.map { "\"mbid_mapping\":{\"recording_mbid\":\"\($0.uuidString)\"}" } ?? "\"mbid_mapping\":null"
        return Data("""
        {"inserted_at":\(timestamp + 1),"listened_at":\(timestamp),"recording_msid":"\(msid.uuidString)","track_metadata":{"artist_name":"Artist","track_name":"Track","release_name":"Release",\(mapping)}}
        """.utf8)
    }

    private func policy(
        maximumEntryCount: Int = 500,
        maximumLineBytes: Int = 1_024 * 1_024,
        maximumRecords: Int = 50_000,
        maximumRetainedTextBytes: Int = 24 * 1_024 * 1_024,
        maximumProcessedLines: Int = 100_000,
        extractionBufferSize: Int = 64 * 1_024
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
            extractionBufferSize: extractionBufferSize
        )
    }
}
