import Foundation
import XCTest
@testable import Brainz

@MainActor
final class ArchivedHistorySnapshotModelTests: XCTestCase {
    func testCatalogLoadsOnceAndRetryRecoversFromReadableFailure() async throws {
        let reader = ArchivedHistoryModelReader(
            catalogOutcomes: [
                .failure(.invalidArchive),
                .success(.init(
                    username: "nabecite",
                    months: [.init(year: 2026, month: 9, uncompressedByteCount: 42)]
                )),
            ]
        )
        let model = ArchivedHistorySnapshotModel(
            archive: archive(),
            expectedUsername: "nabecite",
            reader: reader
        )

        await model.load()
        XCTAssertNil(model.catalog)
        XCTAssertEqual(
            model.errorMessage,
            "This history snapshot is damaged or has an unsupported format. Try downloading it again."
        )

        await model.load(retrying: true)
        XCTAssertEqual(model.catalog?.months.map(\.id), ["2026-9"])
        XCTAssertNil(model.errorMessage)
        await model.load()
        let catalogCallCount = await reader.catalogCallCount()
        XCTAssertEqual(catalogCallCount, 2)
    }

    func testMonthPublishesSnapshotAndMapsAccountMismatchCopy() async throws {
        let descriptor = ArchivedHistoryMonthDescriptor(year: 2026, month: 9, uncompressedByteCount: 42)
        let reader = ArchivedHistoryModelReader(
            catalogOutcomes: [],
            monthOutcomes: [.failure(.usernameMismatch)]
        )
        let model = ArchivedHistoryMonthModel(
            archive: archive(),
            expectedUsername: "nabecite",
            descriptor: descriptor,
            reader: reader
        )

        await model.load()
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(
            model.errorMessage,
            "This history snapshot belongs to a different ListenBrainz account."
        )
    }

    func testCancelSuppressesLateCatalogPublication() async throws {
        let reader = ArchivedHistoryModelReader(
            catalogOutcomes: [.success(.init(username: "nabecite", months: []))],
            delay: .milliseconds(30)
        )
        let model = ArchivedHistorySnapshotModel(
            archive: archive(),
            expectedUsername: "nabecite",
            reader: reader
        )

        let load = Task { await model.load() }
        await Task.yield()
        model.cancel()
        await load.value

        XCTAssertNil(model.catalog)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    private func archive() -> UserDataExportArchive {
        UserDataExportArchive(
            exportID: 1,
            range: .all,
            downloadedAt: .now,
            byteCount: 1,
            fileURL: URL(fileURLWithPath: "/tmp/model-fixture.zip")
        )
    }
}

private actor ArchivedHistoryModelReader: ArchivedHistoryReading {
    enum Outcome<Value: Sendable>: Sendable {
        case success(Value)
        case failure(ArchivedHistoryReaderError)
    }

    private var catalogOutcomes: [Outcome<ArchivedHistoryCatalog>]
    private var monthOutcomes: [Outcome<ArchivedListenMonth>]
    private let delay: Duration?
    private var catalogCalls = 0

    init(
        catalogOutcomes: [Outcome<ArchivedHistoryCatalog>],
        monthOutcomes: [Outcome<ArchivedListenMonth>] = [],
        delay: Duration? = nil
    ) {
        self.catalogOutcomes = catalogOutcomes
        self.monthOutcomes = monthOutcomes
        self.delay = delay
    }

    func catalog(
        from _: UserDataExportArchive,
        expectedUsername _: String
    ) async throws -> ArchivedHistoryCatalog {
        catalogCalls += 1
        if let delay { try? await Task.sleep(for: delay) }
        guard !catalogOutcomes.isEmpty else { throw ArchivedHistoryReaderError.invalidArchive }
        return try resolve(catalogOutcomes.removeFirst())
    }

    func readMonth(
        from _: UserDataExportArchive,
        expectedUsername _: String,
        year _: Int,
        month _: Int
    ) async throws -> ArchivedListenMonth {
        if let delay { try? await Task.sleep(for: delay) }
        guard !monthOutcomes.isEmpty else { throw ArchivedHistoryReaderError.monthUnavailable }
        return try resolve(monthOutcomes.removeFirst())
    }

    func catalogCallCount() -> Int { catalogCalls }

    private func resolve<Value>(_ outcome: Outcome<Value>) throws -> Value {
        switch outcome {
        case let .success(value): value
        case let .failure(error): throw error
        }
    }
}
