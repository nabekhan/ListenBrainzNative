import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

@MainActor
final class UserDataExportTests: XCTestCase {
    private let account = Account(username: "fixture-listener", token: "fixture-token")

    func testModelLoadsOnceAndRefreshesOnlyWhenExplicitlyRequested() async {
        let provider = ExportModelProvider(jobs: [job(id: 3, status: .waiting)])
        let model = UserDataExportModel(account: account, provider: provider)

        await model.load()
        await model.load()
        let initialLists = await provider.listCount()
        XCTAssertEqual(initialLists, 1)
        XCTAssertTrue(model.hasLoaded)

        await model.refresh()
        let refreshedLists = await provider.listCount()
        XCTAssertEqual(refreshedLists, 2)
        XCTAssertEqual(model.notice, "Export status refreshed.")
    }

    func testModelBlocksDuplicateCreateWhilePendingAndReconcilesUnknownOutcome() async {
        let pendingProvider = ExportModelProvider(jobs: [job(id: 1, status: .waiting)])
        let pendingModel = UserDataExportModel(account: account, provider: pendingProvider)
        await pendingModel.load()
        await pendingModel.create(range: .all)
        let blockedCreates = await pendingProvider.createCount()
        XCTAssertEqual(blockedCreates, 0)

        let provider = ExportModelProvider(
            jobs: [],
            createResults: [.failure(.outcomeUnknown), .success(job(id: 8, status: .waiting))]
        )
        let model = UserDataExportModel(account: account, provider: provider)
        await model.load()
        await model.create(range: .all)
        XCTAssertTrue(model.requiresReconciliation)
        await model.create(range: .all)
        let createsBeforeReconciliation = await provider.createCount()
        XCTAssertEqual(createsBeforeReconciliation, 1)

        await model.refresh()
        XCTAssertFalse(model.requiresReconciliation)
        await model.create(range: .all)
        let createsAfterReconciliation = await provider.createCount()
        XCTAssertEqual(createsAfterReconciliation, 2)
    }

    func testUnauthenticatedModelNeverCallsProvider() async {
        let provider = ExportModelProvider(jobs: [])
        let model = UserDataExportModel(
            account: Account(username: "public", token: ""),
            provider: provider
        )

        await model.load()
        await model.refresh()
        await model.create(range: .all)

        let callCount = await provider.totalCalls()
        XCTAssertEqual(callCount, 0)
        XCTAssertNotNil(model.loadError)
    }

    func testProviderCoalescesIdenticalListsAndAuditsOneTransport() async throws {
        let fixture = try makeProvider(listDelay: .milliseconds(40))
        defer { fixture.cleanup() }

        async let first = fixture.provider.list()
        async let second = fixture.provider.list()
        let (left, right) = try await (first, second)

        XCTAssertEqual(left, right)
        let listCount = await fixture.transport.listCount()
        XCTAssertEqual(listCount, 1)
        let audit = await fixture.gate.requestAuditSnapshot()
        let entry = audit.reads.first { $0.feature == .userDataExportList }
        XCTAssertEqual(entry?.counts.started, 1)
        XCTAssertEqual(entry?.counts.coalesced, 1)
        XCTAssertEqual(entry?.counts.finished, 1)
    }

    func testProviderCreateRequiresListAndUnknownOutcomeNeedsReconciliation() async throws {
        let fixture = try makeProvider(
            createResults: [
                .failure(.unknownError),
                .success(lbExport(id: 22, status: .waiting)),
            ]
        )
        defer { fixture.cleanup() }

        await assertProviderError(.reconciliationRequired) {
            _ = try await fixture.provider.create(range: .all)
        }
        var createCount = await fixture.transport.createCount()
        XCTAssertEqual(createCount, 0)

        _ = try await fixture.provider.list()
        await assertProviderError(.outcomeUnknown) {
            _ = try await fixture.provider.create(range: .all)
        }
        createCount = await fixture.transport.createCount()
        XCTAssertEqual(createCount, 1)

        await assertProviderError(.reconciliationRequired) {
            _ = try await fixture.provider.create(range: .all)
        }
        createCount = await fixture.transport.createCount()
        XCTAssertEqual(createCount, 1)

        _ = try await fixture.provider.list()
        let created = try await fixture.provider.create(range: .all)
        XCTAssertEqual(created.id, 22)
        createCount = await fixture.transport.createCount()
        XCTAssertEqual(createCount, 2)
    }

    func testProviderDefiniteCreateFailureClearsReservationWithoutRetry() async throws {
        let fixture = try makeProvider(
            createResults: [
                .failure(.badRequest),
                .success(lbExport(id: 23, status: .waiting)),
            ]
        )
        defer { fixture.cleanup() }

        _ = try await fixture.provider.list()
        await assertProviderError(.rejected) {
            _ = try await fixture.provider.create(range: .all)
        }
        let created = try await fixture.provider.create(range: .all)

        XCTAssertEqual(created.id, 23)
        let createCount = await fixture.transport.createCount()
        XCTAssertEqual(createCount, 2)
    }

    func testCompletedDownloadCoalescesAndUsesVerifiedLocalCopy() async throws {
        let fixture = try makeProvider(downloadDelay: .milliseconds(40))
        defer { fixture.cleanup() }
        let completed = job(id: 44, status: .completed)

        async let first = fixture.provider.download(completed)
        async let second = fixture.provider.download(completed)
        let (left, right) = try await (first, second)

        XCTAssertEqual(left.fileURL, right.fileURL)
        var downloadCount = await fixture.transport.downloadCount()
        XCTAssertEqual(downloadCount, 1)
        _ = try await fixture.provider.download(completed)
        downloadCount = await fixture.transport.downloadCount()
        XCTAssertEqual(downloadCount, 1)

        let values = try left.fileURL.resourceValues(forKeys: [
            .isExcludedFromBackupKey,
            .isRegularFileKey,
        ])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        XCTAssertEqual(values.isRegularFile, true)
        let attributes = try FileManager.default.attributesOfItem(atPath: left.fileURL.path())
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptLocalArchiveIsDiscardedAndRedownloadedOnce() async throws {
        let fixture = try makeProvider()
        defer { fixture.cleanup() }
        let completed = job(id: 45, status: .completed)

        let original = try await fixture.provider.download(completed)
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: original.fileURL)
        let replacement = try await fixture.provider.download(completed)

        XCTAssertEqual(replacement.exportID, completed.id)
        let downloadCount = await fixture.transport.downloadCount()
        XCTAssertEqual(downloadCount, 2)
        XCTAssertEqual(try Data(contentsOf: replacement.fileURL).prefix(4), Data([0x50, 0x4B, 0x03, 0x04]))
    }

    func testLifecycleInvalidationRejectsOldProviderBeforeTransport() async throws {
        let fixture = try makeProvider()
        defer { fixture.cleanup() }

        fixture.lifecycle.invalidate()
        await fixture.operations.closeAndDrain()
        try await fixture.storage.purgeAll()
        await fixture.operations.reopen()

        do {
            _ = try await fixture.provider.list()
            XCTFail("Expected the stale provider lease to be cancelled")
        } catch is CancellationError {
            // A provider created before a credential transition cannot return.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await fixture.transport.totalCalls()
        XCTAssertEqual(callCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path()))
    }

    func testLifecycleCloseRejectsAdmissionWhileAnOperationDrains() async throws {
        let fixture = try makeProvider(listDelay: .seconds(30))
        defer { fixture.cleanup() }

        let first = Task { try await fixture.provider.list() }
        while await fixture.transport.listCount() == 0 { await Task.yield() }
        fixture.lifecycle.invalidate()
        let drain = Task { await fixture.operations.closeAndDrain() }

        do {
            _ = try await fixture.provider.status(exportID: 99)
            XCTFail("Expected admission to close during purge")
        } catch is CancellationError {
            // No stale request was admitted.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await drain.value
        _ = try? await first.value
        let statusCount = await fixture.transport.statusCount()
        XCTAssertEqual(statusCount, 0)
    }

    func testLifecycleDrainWaitsForCancellationIgnoringReadFlight() async throws {
        let blocker = CancellationIgnoringDownloadBlocker()
        let fixture = try makeProvider(downloadBlocker: blocker)
        defer { fixture.cleanup() }
        let completed = job(id: 46, status: .completed)

        let download = Task { try await fixture.provider.download(completed) }
        await blocker.waitUntilStarted()
        fixture.lifecycle.invalidate()

        let completion = ExportTransitionCompletion()
        let transition = Task {
            await fixture.operations.closeAndDrain()
            try? await fixture.storage.purgeAll()
            await fixture.operations.reopen()
            await completion.markComplete()
        }

        await blocker.waitUntilCancellationObserved()
        try await Task.sleep(for: .milliseconds(25))
        let completedBeforeFlightExit = await completion.isComplete
        XCTAssertFalse(completedBeforeFlightExit)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root.path()))

        await blocker.release()
        await transition.value
        _ = try? await download.value

        let completedAfterFlightExit = await completion.isComplete
        XCTAssertTrue(completedAfterFlightExit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path()))
    }

    func testStorageReservationPersistsAndPurgeInvalidatesPreparedTarget() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let storage = UserDataExportStorage(rootDirectory: root)

        await assertStorageError(.reconciliationRequired) {
            _ = try await storage.beginCreation(account: self.account, range: .all)
        }
        try await storage.reconcileCreation(account: account, jobs: [])
        _ = try await storage.beginCreation(account: account, range: .all)

        let relaunched = UserDataExportStorage(rootDirectory: root)
        await assertStorageError(.reconciliationRequired) {
            _ = try await relaunched.beginCreation(account: self.account, range: .all)
        }
        try await relaunched.reconcileCreation(account: account, jobs: [])

        let target = try await relaunched.prepareDownload(
            account: account,
            exportID: 91,
            range: .all
        )
        try zipBytes.write(to: target.partialURL)
        try await relaunched.purgeAll()
        do {
            _ = try await relaunched.finishDownload(account: account, target: target)
            XCTFail("Expected an invalidated target to be cancelled")
        } catch is CancellationError {
            // Purge invalidates in-flight storage generations.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path()))
    }

    func testCleanupRemovesPartialArchiveEvenWhenManifestIsCorrupt() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let storage = UserDataExportStorage(rootDirectory: root)

        try await storage.reconcileCreation(account: account, jobs: [])
        let target = try await storage.prepareDownload(
            account: account,
            exportID: 92,
            range: .all
        )
        try zipBytes.write(to: target.partialURL)

        let accountDirectories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let accountDirectory = try XCTUnwrap(accountDirectories.first)
        try Data("not-json".utf8).write(
            to: accountDirectory.appending(path: "manifest.json")
        )

        await storage.cleanupExpired()

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.partialURL.path()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountDirectory.path()))
    }

    func testCleanupRemovesArchiveThatWasNeverCommittedToManifest() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let storage = UserDataExportStorage(rootDirectory: root)

        try await storage.reconcileCreation(account: account, jobs: [])
        let target = try await storage.prepareDownload(
            account: account,
            exportID: 93,
            range: .all
        )
        let orphan = target.partialURL.deletingLastPathComponent()
            .appending(path: "export-93.zip")
        try zipBytes.write(to: orphan)

        await storage.cleanupExpired()

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path()))
    }

    // MARK: - Fixtures

    private struct ProviderFixture {
        let provider: ListenBrainzUserDataExportProvider
        let transport: ExportTransportSpy
        let storage: UserDataExportStorage
        let gate: RequestGate
        let operations: UserDataExportOperationRegistry
        let lifecycle: UserDataExportLifecycleClock
        let root: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
    }

    private func makeProvider(
        listDelay: Duration = .zero,
        downloadDelay: Duration = .zero,
        downloadBlocker: CancellationIgnoringDownloadBlocker? = nil,
        createResults: [Result<LBUserDataExport, LBError>] = []
    ) throws -> ProviderFixture {
        let root = temporaryRoot()
        let transport = ExportTransportSpy(
            listResult: [lbExport(id: 1, status: .completed)],
            listDelay: listDelay,
            downloadDelay: downloadDelay,
            downloadBlocker: downloadBlocker,
            createResults: createResults
        )
        let storage = UserDataExportStorage(rootDirectory: root)
        let gate = RequestGate(minimumInterval: .zero)
        let operations = UserDataExportOperationRegistry()
        let lifecycle = UserDataExportLifecycleClock()
        let provider = ListenBrainzUserDataExportProvider(
            account: account,
            transport: transport,
            storage: storage,
            gate: gate,
            operations: operations,
            lifecycle: lifecycle
        )
        return ProviderFixture(
            provider: provider,
            transport: transport,
            storage: storage,
            gate: gate,
            operations: operations,
            lifecycle: lifecycle,
            root: root
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "UserDataExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "exports", directoryHint: .isDirectory)
    }

    private func job(id: Int, status: UserDataExportStatus) -> UserDataExportJob {
        UserDataExportJob(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000 + TimeInterval(id)),
            availableUntil: Date(timeIntervalSince1970: 1_760_000_000),
            range: .all,
            status: status
        )
    }

    private func lbExport(id: Int, status: LBUserDataExportStatus) -> LBUserDataExport {
        LBUserDataExport(
            exportID: id,
            type: "export_all_user_data",
            availableUntil: Date(timeIntervalSince1970: 1_760_000_000),
            created: Date(timeIntervalSince1970: 1_750_000_000 + TimeInterval(id)),
            progress: "fixture",
            status: status,
            filename: nil,
            startTime: nil,
            endTime: nil
        )
    }

    private var zipBytes: Data {
        Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00])
    }

    private func assertProviderError(
        _ expected: UserDataExportProviderError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected provider error \(expected)")
        } catch let error as UserDataExportProviderError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func assertStorageError(
        _ expected: UserDataExportStorageError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected storage error \(expected)")
        } catch let error as UserDataExportStorageError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor ExportTransportSpy: UserDataExportTransport {
    private let listResult: [LBUserDataExport]
    private let listDelay: Duration
    private let downloadDelay: Duration
    private let downloadBlocker: CancellationIgnoringDownloadBlocker?
    private var createResults: [Result<LBUserDataExport, LBError>]
    private var lists = 0
    private var statuses = 0
    private var creates = 0
    private var downloads = 0
    private var deletes = 0

    init(
        listResult: [LBUserDataExport],
        listDelay: Duration,
        downloadDelay: Duration,
        downloadBlocker: CancellationIgnoringDownloadBlocker?,
        createResults: [Result<LBUserDataExport, LBError>]
    ) {
        self.listResult = listResult
        self.listDelay = listDelay
        self.downloadDelay = downloadDelay
        self.downloadBlocker = downloadBlocker
        self.createResults = createResults
    }

    func list() async throws -> [LBUserDataExport] {
        lists += 1
        if listDelay != .zero { try await Task.sleep(for: listDelay) }
        return listResult
    }

    func status(exportID: Int) async throws -> LBUserDataExport {
        statuses += 1
        guard let result = listResult.first(where: { $0.exportID == exportID }) ?? listResult.first else {
            throw LBError.notFound
        }
        return result
    }

    func create(range _: UserDataExportRange) async throws -> LBUserDataExport {
        creates += 1
        guard !createResults.isEmpty else { throw LBError.badRequest }
        return try createResults.removeFirst().get()
    }

    func download(exportID _: Int, to destination: URL) async throws {
        downloads += 1
        if let downloadBlocker { await downloadBlocker.block() }
        if downloadDelay != .zero { try await Task.sleep(for: downloadDelay) }
        try Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00])
            .write(to: destination, options: .withoutOverwriting)
    }

    func delete(exportID _: Int) async throws {
        deletes += 1
    }

    func listCount() -> Int { lists }
    func statusCount() -> Int { statuses }
    func createCount() -> Int { creates }
    func downloadCount() -> Int { downloads }
    func totalCalls() -> Int { lists + statuses + creates + downloads + deletes }
}

private actor CancellationIgnoringDownloadBlocker {
    private var didStart = false
    private var didObserveCancellation = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func block() async {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        do {
            try await Task.sleep(for: .seconds(30))
        } catch is CancellationError {
            didObserveCancellation = true
            cancellationWaiters.forEach { $0.resume() }
            cancellationWaiters.removeAll()
        } catch {
            return
        }

        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            if isReleased {
                continuation.resume()
            } else {
                releaseWaiters.append(continuation)
            }
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitUntilCancellationObserved() async {
        guard !didObserveCancellation else { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor ExportTransitionCompletion {
    private(set) var isComplete = false

    func markComplete() {
        isComplete = true
    }
}

private actor ExportModelProvider: UserDataExportProviding {
    private var jobs: [UserDataExportJob]
    private var createResults: [Result<UserDataExportJob, UserDataExportProviderError>]
    private var lists = 0
    private var creates = 0
    private var downloads = 0
    private var deletions = 0
    private var removals = 0

    init(
        jobs: [UserDataExportJob],
        createResults: [Result<UserDataExportJob, UserDataExportProviderError>] = []
    ) {
        self.jobs = jobs
        self.createResults = createResults
    }

    func list() async throws -> [UserDataExportJob] {
        lists += 1
        return jobs
    }

    func status(exportID: Int) async throws -> UserDataExportJob {
        guard let job = jobs.first(where: { $0.id == exportID }) else {
            throw UserDataExportProviderError.notFound
        }
        return job
    }

    func create(range _: UserDataExportRange) async throws -> UserDataExportJob {
        creates += 1
        guard !createResults.isEmpty else { throw UserDataExportProviderError.rejected }
        let job = try createResults.removeFirst().get()
        jobs.append(job)
        return job
    }

    func download(_ job: UserDataExportJob) async throws -> UserDataExportArchive {
        downloads += 1
        return UserDataExportArchive(
            exportID: job.id,
            range: job.range,
            downloadedAt: .now,
            byteCount: 8,
            fileURL: FileManager.default.temporaryDirectory.appending(path: "fixture-\(job.id).zip")
        )
    }

    func deleteFromListenBrainz(exportID _: Int) async throws { deletions += 1 }
    func removeLocalArchive(exportID _: Int) async throws { removals += 1 }

    func listCount() -> Int { lists }
    func createCount() -> Int { creates }
    func totalCalls() -> Int { lists + creates + downloads + deletions + removals }
}
