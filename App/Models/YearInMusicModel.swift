import Foundation
import Observation

enum YearInMusicLoadState: Equatable {
    case idle
    case loading
    case refreshing
    case ready
    case unavailable
    case failed(String)
}

struct YearInMusicCacheKey: Hashable, Sendable {
    let username: String
    let scope: RequestGate.ReadScope
    let year: Int

    init(username: String, scope: RequestGate.ReadScope, year: Int) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.scope = scope
        self.year = year
    }
}

enum YearInMusicCaches {
    static let reports = EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>(
        timeToLive: 30 * 60,
        maximumEntryCount: 20
    )
    /// Frozen archives do not change, so retain them substantially longer than
    /// the active current-year report.
    static let archives = EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>(
        timeToLive: 24 * 60 * 60,
        maximumEntryCount: 20
    )
}

@MainActor
@Observable
final class YearInMusicModel {
    /// The signed-in (or anonymous) viewer supplies request credentials and
    /// owns any media actions reached from the report.
    let account: Account
    /// The listener whose annual report is being presented. This can differ
    /// from `account.username` when browsing another listener's profile.
    let subjectUsername: String
    let year: Int

    private let provider: any YearInMusicProviding
    private let cache: EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>

    private(set) var report: YearInMusicReport?
    private(set) var state: YearInMusicLoadState = .idle
    private(set) var refreshMessage: String?
    private(set) var lastUpdated: Date?
    private var requestID = UUID()

    init(
        account: Account,
        subjectUsername: String? = nil,
        year: Int,
        provider: (any YearInMusicProviding)? = nil,
        cache: EntityDetailCache<YearInMusicCacheKey, YearInMusicReport> = YearInMusicCaches.reports
    ) {
        self.account = account
        if let requestedSubject = subjectUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedSubject.isEmpty {
            self.subjectUsername = requestedSubject
        } else {
            self.subjectUsername = account.username
        }
        self.year = year
        self.provider = provider ?? ListenBrainzYearInMusicProvider(token: account.token)
        self.cache = cache
    }

    func load() async {
        guard state == .idle else { return }
        let key = cacheKey
        if let cached = await cache.value(for: key) {
            report = cached.value
            lastUpdated = .now
            if cached.isFresh {
                state = .ready
                return
            }
            state = .refreshing
        } else {
            state = .loading
        }
        await fetch()
    }

    func refresh() async {
        requestID = UUID() // makes a returning older request harmless.
        refreshMessage = nil
        state = report == nil ? .loading : .refreshing
        await fetch()
    }

    private func fetch() async {
        let id = UUID()
        requestID = id
        do {
            let result = try await provider.report(username: subjectUsername, year: year)
            try Task.checkCancellation()
            guard requestID == id else { return }
            guard let result else {
                report = nil
                lastUpdated = nil
                state = .unavailable
                refreshMessage = nil
                return
            }
            report = result
            lastUpdated = .now
            state = .ready
            refreshMessage = nil
            await cache.save(result, for: cacheKey)
        } catch is CancellationError {
            guard requestID == id else { return }
            state = report == nil ? .idle : .ready
        } catch {
            guard requestID == id else { return }
            if report == nil {
                state = .failed(error.localizedDescription)
            } else {
                state = .ready
                refreshMessage = error.localizedDescription
            }
        }
    }

    private var cacheKey: YearInMusicCacheKey {
        YearInMusicCacheKey(
            username: subjectUsername,
            scope: (2021 ... 2024).contains(year) ? .anonymous : .authenticated(token: account.token),
            year: year
        )
    }
}
