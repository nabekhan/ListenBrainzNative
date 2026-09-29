import Foundation
import Observation

@MainActor
@Observable
final class ArchivedHistorySnapshotModel {
    let archive: UserDataExportArchive

    private let expectedUsername: String
    private let reader: any ArchivedHistoryReading
    private var requestID: UUID?

    private(set) var catalog: ArchivedHistoryCatalog?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(
        archive: UserDataExportArchive,
        expectedUsername: String,
        reader: any ArchivedHistoryReading = ArchivedHistoryReader()
    ) {
        self.archive = archive
        self.expectedUsername = expectedUsername
        self.reader = reader
    }

    func load(retrying: Bool = false) async {
        guard !isLoading else { return }
        guard catalog == nil || retrying else { return }

        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        do {
            let value = try await reader.catalog(
                from: archive,
                expectedUsername: expectedUsername
            )
            try Task.checkCancellation()
            guard requestID == id else { return }
            catalog = value
            isLoading = false
            requestID = nil
        } catch is CancellationError {
            guard requestID == id else { return }
            isLoading = false
            requestID = nil
        } catch let error as ArchivedHistoryReaderError where error == .cancelled {
            guard requestID == id else { return }
            isLoading = false
            requestID = nil
        } catch {
            guard requestID == id else { return }
            isLoading = false
            errorMessage = ArchivedHistoryCopy.message(for: error)
            requestID = nil
        }
    }

    func cancel() {
        requestID = nil
        isLoading = false
    }
}

@MainActor
@Observable
final class ArchivedHistoryMonthModel {
    let descriptor: ArchivedHistoryMonthDescriptor

    private let archive: UserDataExportArchive
    private let expectedUsername: String
    private let reader: any ArchivedHistoryReading
    private var requestID: UUID?

    private(set) var snapshot: ArchivedListenMonth?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(
        archive: UserDataExportArchive,
        expectedUsername: String,
        descriptor: ArchivedHistoryMonthDescriptor,
        reader: any ArchivedHistoryReading = ArchivedHistoryReader()
    ) {
        self.archive = archive
        self.expectedUsername = expectedUsername
        self.descriptor = descriptor
        self.reader = reader
    }

    func load(retrying: Bool = false) async {
        guard !isLoading else { return }
        guard snapshot == nil || retrying else { return }

        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        do {
            let value = try await reader.readMonth(
                from: archive,
                expectedUsername: expectedUsername,
                year: descriptor.year,
                month: descriptor.month
            )
            try Task.checkCancellation()
            guard requestID == id else { return }
            snapshot = value
            isLoading = false
            requestID = nil
        } catch is CancellationError {
            guard requestID == id else { return }
            isLoading = false
            requestID = nil
        } catch let error as ArchivedHistoryReaderError where error == .cancelled {
            guard requestID == id else { return }
            isLoading = false
            requestID = nil
        } catch {
            guard requestID == id else { return }
            isLoading = false
            errorMessage = ArchivedHistoryCopy.message(for: error)
            requestID = nil
        }
    }

    func cancel() {
        requestID = nil
        isLoading = false
    }
}

enum ArchivedHistoryCopy {
    static func message(for error: Error) -> String {
        guard let error = error as? ArchivedHistoryReaderError else {
            return String(localized: "This history snapshot couldn’t open. Try downloading it again.")
        }
        switch error {
        case .usernameMismatch:
            return String(localized: "This history snapshot belongs to a different ListenBrainz account.")
        case .monthUnavailable:
            return String(localized: "This month is no longer available in the downloaded snapshot.")
        case .limitExceeded:
            return String(localized: "This history snapshot is too large to open safely.")
        case .invalidArchive:
            return String(localized: "This history snapshot is damaged or has an unsupported format. Try downloading it again.")
        case .cancelled:
            return String(localized: "Opening this history snapshot was cancelled.")
        }
    }
}
