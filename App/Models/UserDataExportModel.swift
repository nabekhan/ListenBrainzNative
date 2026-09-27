import Foundation
import Observation

@MainActor
@Observable
final class UserDataExportModel {
    enum Operation: Equatable {
        case refreshing
        case creating
        case downloading(Int)
        case removingLocal(Int)
    }

    let account: Account

    private let provider: any UserDataExportProviding
    private var didRequestInitialLoad = false
    private var requestID: UUID?

    private(set) var jobs: [UserDataExportJob] = []
    private(set) var archives: [Int: UserDataExportArchive] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var operation: Operation?
    private(set) var loadError: String?
    private(set) var notice: String?
    private(set) var requiresReconciliation = false

    init(
        account: Account,
        provider: (any UserDataExportProviding)? = nil
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzUserDataExportProvider(account: account)
    }

    func load() async {
        guard account.isAuthenticated else {
            loadError = String(localized: "Sign in to create and download your ListenBrainz data archive.")
            return
        }
        guard !didRequestInitialLoad else { return }
        didRequestInitialLoad = true
        await fetchList(isInitial: true)
    }

    func refresh() async {
        guard account.isAuthenticated, operation == nil else { return }
        await fetchList(isInitial: jobs.isEmpty)
    }

    func create(range: UserDataExportRange) async {
        guard account.isAuthenticated,
              operation == nil,
              !requiresReconciliation,
              !jobs.contains(where: { $0.status.isPending })
        else { return }
        operation = .creating
        notice = nil
        let id = UUID()
        requestID = id
        defer {
            if requestID == id {
                requestID = nil
                operation = nil
            }
        }
        do {
            let job = try await provider.create(range: range)
            try Task.checkCancellation()
            guard requestID == id else { return }
            upsert(job)
            notice = String(localized: "Archive requested. Refresh later to check its status.")
        } catch is CancellationError {
            return
        } catch let error as UserDataExportProviderError {
            guard requestID == id else { return }
            if error == .outcomeUnknown || error == .reconciliationRequired {
                requiresReconciliation = true
            }
            notice = Self.message(for: error, action: .create)
        } catch {
            guard requestID == id else { return }
            requiresReconciliation = true
            notice = Self.message(for: .outcomeUnknown, action: .create)
        }
    }

    func download(_ job: UserDataExportJob) async {
        guard account.isAuthenticated,
              operation == nil,
              job.status.canDownload
        else { return }
        operation = .downloading(job.id)
        notice = nil
        let id = UUID()
        requestID = id
        defer {
            if requestID == id {
                requestID = nil
                operation = nil
            }
        }
        do {
            let archive = try await provider.download(job)
            try Task.checkCancellation()
            guard requestID == id else { return }
            archives[job.id] = archive
            notice = String(localized: "Archive downloaded. Choose where to save or share it.")
        } catch is CancellationError {
            return
        } catch let error as UserDataExportProviderError {
            guard requestID == id else { return }
            notice = Self.message(for: error, action: .download)
        } catch {
            guard requestID == id else { return }
            notice = Self.message(for: .unavailable, action: .download)
        }
    }

    func removeLocalArchive(exportID: Int) async {
        guard operation == nil, archives[exportID] != nil else { return }
        operation = .removingLocal(exportID)
        notice = nil
        let id = UUID()
        requestID = id
        defer {
            if requestID == id {
                requestID = nil
                operation = nil
            }
        }
        do {
            try await provider.removeLocalArchive(exportID: exportID)
            guard requestID == id else { return }
            archives.removeValue(forKey: exportID)
            notice = String(localized: "Downloaded copy removed from this device.")
        } catch is CancellationError {
            return
        } catch {
            guard requestID == id else { return }
            notice = String(localized: "Couldn’t remove the downloaded copy. Try again.")
        }
    }

    func cancel() {
        requestID = nil
        isLoading = false
        operation = nil
    }

    var hasPendingExport: Bool {
        jobs.contains { $0.status.isPending }
    }

    private func fetchList(isInitial: Bool) async {
        let id = UUID()
        requestID = id
        if isInitial { isLoading = true } else { operation = .refreshing }
        if isInitial { loadError = nil }
        notice = nil
        defer {
            if requestID == id {
                requestID = nil
                isLoading = false
                operation = nil
            }
        }
        do {
            let result = try await provider.list()
            try Task.checkCancellation()
            guard requestID == id else { return }
            jobs = result
            hasLoaded = true
            requiresReconciliation = false
            loadError = nil
            if !isInitial {
                notice = String(localized: "Export status refreshed.")
            }
        } catch is CancellationError {
            return
        } catch let error as UserDataExportProviderError {
            guard requestID == id else { return }
            let message = Self.message(for: error, action: .list)
            if jobs.isEmpty { loadError = message } else { notice = message }
        } catch {
            guard requestID == id else { return }
            let message = Self.message(for: .unavailable, action: .list)
            if jobs.isEmpty { loadError = message } else { notice = message }
        }
    }

    private func upsert(_ job: UserDataExportJob) {
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
        jobs.sort { $0.createdAt > $1.createdAt }
    }

    private enum Action {
        case list
        case create
        case download
    }

    private static func message(
        for error: UserDataExportProviderError,
        action: Action
    ) -> String {
        switch error {
        case .authentication:
            String(localized: "Your ListenBrainz sign-in needs attention. Sign in again to manage data exports.")
        case let .rateLimited(seconds):
            String(localized: "ListenBrainz is busy. Try again in about \(seconds) seconds.")
        case .rejected:
            switch action {
            case .create:
                String(localized: "ListenBrainz couldn’t start this archive. Refresh and check the date range.")
            case .download:
                String(localized: "This archive isn’t ready to download. Refresh its status and try again.")
            case .list:
                String(localized: "ListenBrainz couldn’t load your data exports. Try again.")
            }
        case .notFound:
            String(localized: "This archive is no longer available. Refresh the list.")
        case .outcomeUnknown:
            String(localized: "Brainz couldn’t confirm whether ListenBrainz started the archive. Refresh before trying again.")
        case .reconciliationRequired:
            String(localized: "Refresh your exports before creating another archive.")
        case .insufficientSpace:
            String(localized: "Free some storage on this device, then download the archive again.")
        case .invalidArchive:
            String(localized: "The downloaded archive couldn’t be verified. Try downloading it again.")
        case .unavailable:
            switch action {
            case .download:
                String(localized: "Couldn’t download the archive. Check your connection and try again.")
            case .create:
                String(localized: "Couldn’t request the archive. Check your connection and try again.")
            case .list:
                String(localized: "Couldn’t load your data exports. Check your connection and try again.")
            }
        }
    }
}
