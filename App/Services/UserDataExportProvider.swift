import Foundation
import ListenBrainzKit

final class UserDataExportLifecycleClock: @unchecked Sendable {
    struct Lease: Sendable, Equatable {
        fileprivate let generation: UInt64
    }

    static let shared = UserDataExportLifecycleClock()

    private let lock = NSLock()
    private var generation: UInt64 = 0

    func issueLease() -> Lease {
        lock.withLock { Lease(generation: generation) }
    }

    func invalidate() {
        lock.withLock { generation &+= 1 }
    }

    func isCurrent(_ lease: Lease) -> Bool {
        lock.withLock { lease.generation == generation }
    }
}

protocol UserDataExportProviding: Sendable {
    func list() async throws -> [UserDataExportJob]
    func status(exportID: Int) async throws -> UserDataExportJob
    func create(range: UserDataExportRange) async throws -> UserDataExportJob
    func download(_ job: UserDataExportJob) async throws -> UserDataExportArchive
    func deleteFromListenBrainz(exportID: Int) async throws
    func removeLocalArchive(exportID: Int) async throws
}

protocol UserDataExportTransport: Sendable {
    func list() async throws -> [LBUserDataExport]
    func status(exportID: Int) async throws -> LBUserDataExport
    func create(range: UserDataExportRange) async throws -> LBUserDataExport
    func download(exportID: Int, to destination: URL) async throws
    func delete(exportID: Int) async throws
}

enum UserDataExportProviderError: Error, Equatable {
    case authentication
    case rateLimited(seconds: Int)
    case rejected
    case unavailable
    case notFound
    case outcomeUnknown
    case reconciliationRequired
    case insufficientSpace
    case invalidArchive
}

private struct LiveUserDataExportTransport: UserDataExportTransport {
    let client: LBUserDataExportClient

    func list() async throws -> [LBUserDataExport] {
        try await client.list()
    }

    func status(exportID: Int) async throws -> LBUserDataExport {
        try await client.status(exportID: exportID)
    }

    func create(range: UserDataExportRange) async throws -> LBUserDataExport {
        if range.isAllTime {
            return try await client.createFull()
        }
        return try await client.create(range: LBUserDataExportRange(
            startTime: range.startTime,
            endTime: range.endTime
        ))
    }

    func download(exportID: Int, to destination: URL) async throws {
        _ = try await client.download(exportID: exportID, to: destination)
    }

    func delete(exportID: Int) async throws {
        try await client.delete(exportID: exportID)
    }
}

/// Tracks export-only operations so disconnecting can cancel and drain every
/// task before protected account files and the credential are removed.
actor UserDataExportOperationRegistry {
    static let shared = UserDataExportOperationRegistry()

    private struct ActiveOperation {
        let cancel: @Sendable () -> Void
        let completion: Task<Void, Never>
    }

    private var active: [UUID: ActiveOperation] = [:]
    private var acceptsOperations = true

    func run<Value: Sendable>(
        lease: UserDataExportLifecycleClock.Lease,
        lifecycle: UserDataExportLifecycleClock,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard acceptsOperations, lifecycle.isCurrent(lease) else {
            throw CancellationError()
        }
        let id = UUID()
        let task = Task { try await operation() }
        let completion = Task<Void, Never> { _ = try? await task.value }
        active[id] = ActiveOperation(
            cancel: { task.cancel() },
            completion: completion
        )

        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            active.removeValue(forKey: id)
            return value
        } catch {
            active.removeValue(forKey: id)
            throw error
        }
    }

    func closeAndDrain() async {
        acceptsOperations = false
        while !active.isEmpty {
            let operationIDs = Array(active.keys)
            let operations = operationIDs.compactMap { active[$0] }
            operations.forEach { $0.cancel() }
            for operation in operations {
                await operation.completion.value
            }
            for id in operationIDs {
                active.removeValue(forKey: id)
            }
        }
    }

    func reopen() {
        acceptsOperations = true
    }
}

enum UserDataExportAccountLifecycle {
    static func purgeAll() async throws {
        let lifecycle = UserDataExportLifecycleClock.shared
        let operations = UserDataExportOperationRegistry.shared
        lifecycle.invalidate()
        await operations.closeAndDrain()
        do {
            try await UserDataExportStorage.shared.purgeAll()
            try UserDataExportShareStaging.purgeAll()
            await operations.reopen()
        } catch {
            await operations.reopen()
            throw error
        }
    }
}

/// A gated, non-retrying boundary around asynchronous account exports.
/// Reads coalesce by account and export ID; create/delete remain serialized.
struct ListenBrainzUserDataExportProvider: UserDataExportProviding {
    private let account: Account
    private let transport: any UserDataExportTransport
    private let storage: any UserDataExportStoring
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope
    private let operations: UserDataExportOperationRegistry
    private let lifecycle: UserDataExportLifecycleClock
    private let lifecycleLease: UserDataExportLifecycleClock.Lease

    init(
        account: Account,
        gate: RequestGate = .shared,
        storage: any UserDataExportStoring = UserDataExportStorage.shared,
        operations: UserDataExportOperationRegistry = .shared
    ) {
        let client = LBClient(
            token: account.token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        self.account = account
        transport = LiveUserDataExportTransport(client: client.userDataExports)
        self.storage = storage
        self.gate = gate
        readScope = .authenticated(token: account.token)
        self.operations = operations
        lifecycle = .shared
        lifecycleLease = lifecycle.issueLease()
    }

    init(
        account: Account,
        transport: some UserDataExportTransport,
        storage: any UserDataExportStoring,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated(),
        operations: UserDataExportOperationRegistry = UserDataExportOperationRegistry(),
        lifecycle: UserDataExportLifecycleClock = UserDataExportLifecycleClock()
    ) {
        self.account = account
        self.transport = transport
        self.storage = storage
        self.gate = gate
        self.readScope = readScope
        self.operations = operations
        self.lifecycle = lifecycle
        lifecycleLease = lifecycle.issueLease()
    }

    func list() async throws -> [UserDataExportJob] {
        try requireAuthenticatedAccount()
        do {
            return try await operations.run(
                lease: lifecycleLease,
                lifecycle: lifecycle
            ) {
                let exports = try await gate.read(
                    for: .userDataExportList(readScope),
                    drainOnFinalCancellation: true
                ) {
                    try await transport.list()
                } deferralForError: { Self.rateLimitDeferral($0) }
                try Task.checkCancellation()
                let jobs = try exports.map(Self.map)
                try await storage.reconcileCreation(account: account, jobs: jobs)
                return jobs.sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            throw Self.mapReadError(error)
        }
    }

    func status(exportID: Int) async throws -> UserDataExportJob {
        try requireAuthenticatedAccount()
        guard exportID > 0 else { throw UserDataExportProviderError.rejected }
        do {
            return try await operations.run(
                lease: lifecycleLease,
                lifecycle: lifecycle
            ) {
                let export = try await gate.read(
                    for: .userDataExportStatus(readScope, exportID: exportID),
                    drainOnFinalCancellation: true
                ) {
                    try await transport.status(exportID: exportID)
                } deferralForError: { Self.rateLimitDeferral($0) }
                try Task.checkCancellation()
                return try Self.map(export)
            }
        } catch {
            throw Self.mapReadError(error)
        }
    }

    func create(range: UserDataExportRange) async throws -> UserDataExportJob {
        try requireAuthenticatedAccount()
        return try await operations.run(
            lease: lifecycleLease,
            lifecycle: lifecycle
        ) {
            try await createRegistered(range: range)
        }
    }

    private func createRegistered(range: UserDataExportRange) async throws -> UserDataExportJob {
        let reservationID: UUID
        do {
            reservationID = try await storage.beginCreation(
                account: account,
                range: range
            )
        } catch {
            throw Self.mapStorageError(error)
        }

        let attempt = ExportMutationAttempt()
        do {
            let export = try await gate.perform({
                await attempt.markTransportStarted()
                return try await transport.create(range: range)
            }) { Self.rateLimitDeferral($0) }
            try Task.checkCancellation()
            let job = try Self.map(export)
            try await storage.finishCreation(
                account: account,
                reservationID: reservationID,
                exportID: job.id
            )
            return job
        } catch is CancellationError {
            if !(await attempt.didStartTransport) {
                try? await storage.cancelCreationBeforeDispatch(
                    account: account,
                    reservationID: reservationID
                )
                throw CancellationError()
            }
            throw UserDataExportProviderError.outcomeUnknown
        } catch let error as LBError {
            if Self.isDefiniteCreateFailure(error) {
                try? await storage.cancelCreationBeforeDispatch(
                    account: account,
                    reservationID: reservationID
                )
                throw Self.mapReadError(error)
            }
            throw UserDataExportProviderError.outcomeUnknown
        } catch let error as UserDataExportStorageError {
            throw Self.mapStorageError(error)
        } catch {
            throw UserDataExportProviderError.outcomeUnknown
        }
    }

    func download(_ job: UserDataExportJob) async throws -> UserDataExportArchive {
        try requireAuthenticatedAccount()
        guard job.id > 0, job.status.canDownload else {
            throw UserDataExportProviderError.rejected
        }
        do {
            return try await operations.run(
                lease: lifecycleLease,
                lifecycle: lifecycle
            ) {
                if let existing = try await storage.existingArchive(
                    account: account,
                    exportID: job.id,
                    range: job.range
                ) {
                    return existing
                }
                return try await gate.read(
                    for: .userDataExportDownload(readScope, exportID: job.id),
                    drainOnFinalCancellation: true
                ) {
                    let target = try await storage.prepareDownload(
                        account: account,
                        exportID: job.id,
                        range: job.range
                    )
                    do {
                        try await transport.download(
                            exportID: job.id,
                            to: target.partialURL
                        )
                        try Task.checkCancellation()
                        return try await storage.finishDownload(
                            account: account,
                            target: target
                        )
                    } catch {
                        await storage.abandonDownload(target)
                        throw error
                    }
                } deferralForError: { Self.rateLimitDeferral($0) }
            }
        } catch let error as UserDataExportStorageError {
            throw Self.mapStorageError(error)
        } catch {
            throw Self.mapReadError(error)
        }
    }

    func deleteFromListenBrainz(exportID: Int) async throws {
        try requireAuthenticatedAccount()
        guard exportID > 0 else { throw UserDataExportProviderError.rejected }
        try await operations.run(
            lease: lifecycleLease,
            lifecycle: lifecycle
        ) {
            try await deleteRegistered(exportID: exportID)
        }
    }

    private func deleteRegistered(exportID: Int) async throws {
        let attempt = ExportMutationAttempt()
        do {
            try await gate.perform({
                await attempt.markTransportStarted()
                try await transport.delete(exportID: exportID)
            }) { Self.rateLimitDeferral($0) }
            try Task.checkCancellation()
        } catch is CancellationError {
            if !(await attempt.didStartTransport) { throw CancellationError() }
            throw UserDataExportProviderError.outcomeUnknown
        } catch let error as LBError {
            switch error {
            case .invalidAuth, .noToken, .forbidden:
                throw UserDataExportProviderError.authentication
            case let .rateLimited(resetIn):
                throw UserDataExportProviderError.rateLimited(seconds: max(resetIn, 1))
            case .notFound:
                throw UserDataExportProviderError.notFound
            case .badRequest, .invalidParam, .invalidJSON:
                throw UserDataExportProviderError.rejected
            case .invalidResponse, .noContent, .unknownError:
                throw UserDataExportProviderError.outcomeUnknown
            }
        } catch {
            throw UserDataExportProviderError.outcomeUnknown
        }
    }

    func removeLocalArchive(exportID: Int) async throws {
        try requireAuthenticatedAccount()
        do {
            try await operations.run(
                lease: lifecycleLease,
                lifecycle: lifecycle
            ) {
                try await storage.removeArchive(account: account, exportID: exportID)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.mapStorageError(error)
        }
    }

    private func requireAuthenticatedAccount() throws {
        guard account.isAuthenticated else {
            throw UserDataExportProviderError.authentication
        }
    }

    private static func map(_ source: LBUserDataExport) throws -> UserDataExportJob {
        guard source.exportID > 0,
              source.created.timeIntervalSinceReferenceDate.isFinite,
              source.availableUntil?.timeIntervalSinceReferenceDate.isFinite != false,
              source.startTime == nil || source.endTime == nil || source.startTime! <= source.endTime!
        else { throw UserDataExportProviderError.unavailable }
        let status: UserDataExportStatus = switch source.status {
        case .waiting: .waiting
        case .inProgress: .inProgress
        case .completed: .completed
        case .failed: .failed
        case .unknown: .unknown
        }
        return UserDataExportJob(
            id: source.exportID,
            createdAt: source.created,
            availableUntil: source.availableUntil,
            range: UserDataExportRange(
                startTime: source.startTime,
                endTime: source.endTime
            ),
            status: status
        )
    }

    private static func rateLimitDeferral(_ error: any Error) -> Duration? {
        guard case let LBError.rateLimited(resetIn) = error else { return nil }
        return .seconds(max(resetIn, 1))
    }

    private static func mapReadError(_ error: any Error) -> any Error {
        if error is CancellationError { return CancellationError() }
        if let providerError = error as? UserDataExportProviderError {
            return providerError
        }
        if let storageError = error as? UserDataExportStorageError {
            return mapStorageError(storageError)
        }
        guard let error = error as? LBError else {
            return UserDataExportProviderError.unavailable
        }
        switch error {
        case .invalidAuth, .noToken, .forbidden:
            return UserDataExportProviderError.authentication
        case let .rateLimited(resetIn):
            return UserDataExportProviderError.rateLimited(seconds: max(resetIn, 1))
        case .notFound:
            return UserDataExportProviderError.notFound
        case .badRequest, .invalidParam, .invalidJSON:
            return UserDataExportProviderError.rejected
        case .invalidResponse, .noContent, .unknownError:
            return UserDataExportProviderError.unavailable
        }
    }

    private static func mapStorageError(_ error: any Error) -> UserDataExportProviderError {
        guard let error = error as? UserDataExportStorageError else {
            return .unavailable
        }
        return switch error {
        case .reconciliationRequired: .reconciliationRequired
        case .insufficientSpace: .insufficientSpace
        case .invalidArchive, .corruptState: .invalidArchive
        case .unavailable: .unavailable
        }
    }

    private static func isDefiniteCreateFailure(_ error: LBError) -> Bool {
        switch error {
        case .invalidAuth, .noToken, .forbidden, .rateLimited,
             .badRequest, .invalidParam, .invalidJSON, .notFound:
            true
        case .invalidResponse, .noContent, .unknownError:
            false
        }
    }

    private actor ExportMutationAttempt {
        private(set) var didStartTransport = false

        func markTransportStarted() {
            didStartTransport = true
        }
    }
}
