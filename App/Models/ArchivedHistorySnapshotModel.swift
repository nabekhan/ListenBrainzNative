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

@MainActor
@Observable
final class ArchivedHistorySearchModel {
    private let archive: UserDataExportArchive
    private let expectedUsername: String
    private let reader: any ArchivedHistoryReading
    private var requestID: UUID?
    private var searchTask: Task<Void, Never>?

    var query = ""
    private(set) var result: ArchivedHistorySearchResult?
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    private(set) var validationMessage: String?

    init(
        archive: UserDataExportArchive,
        expectedUsername: String,
        reader: any ArchivedHistoryReading = ArchivedHistoryReader()
    ) {
        self.archive = archive
        self.expectedUsername = expectedUsername
        self.reader = reader
    }

    /// Deliberately starts only from an explicit user action. Archive scans can
    /// be expensive, so typing never schedules work or touches the network.
    func submit() {
        guard !isSearching else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            validationMessage = String(localized: "Enter at least 2 characters to search your archive.")
            return
        }
        guard trimmedQuery.utf8.count <= 256 else {
            validationMessage = String(localized: "Make your search shorter, then try again.")
            return
        }

        cancel()
        let id = UUID()
        requestID = id
        isSearching = true
        result = nil
        errorMessage = nil
        validationMessage = nil
        searchTask = Task { [archive, expectedUsername, reader] in
            do {
                let value = try await reader.search(
                    in: archive,
                    expectedUsername: expectedUsername,
                    query: trimmedQuery
                )
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                self.result = value
                self.isSearching = false
                self.requestID = nil
                self.searchTask = nil
            } catch is CancellationError {
                guard self.requestID == id else { return }
                self.isSearching = false
                self.requestID = nil
                self.searchTask = nil
            } catch let error as ArchivedHistoryReaderError where error == .cancelled {
                guard self.requestID == id else { return }
                self.isSearching = false
                self.requestID = nil
                self.searchTask = nil
            } catch {
                guard self.requestID == id else { return }
                self.isSearching = false
                self.errorMessage = ArchivedHistoryCopy.message(for: error)
                self.requestID = nil
                self.searchTask = nil
            }
        }
    }

    func cancel() {
        requestID = nil
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
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
        case .invalidSearchQuery:
            return String(localized: "Enter at least 2 characters and no more than 256 UTF-8 bytes.")
        }
    }
}
