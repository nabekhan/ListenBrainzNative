import Foundation
import Observation

@MainActor
@Observable
final class ListeningModel {
    enum Phase: Equatable {
        case idle
        case loading
        case refreshing
        case ready
        case failed(String)
    }

    let account: Account
    private let provider: any ListeningProvider
    private let cache: SnapshotCache
    private let dailyActivityCache: EntityDetailCache<DailyActivityCacheKey, DailyActivity>
    private let eraActivityCache: EntityDetailCache<EraActivityCacheKey, EraActivity>
    private let artistEvolutionActivityCache: EntityDetailCache<ArtistEvolutionActivityCacheKey, ArtistEvolutionActivity>
    private let genreActivityCache: EntityDetailCache<GenreActivityCacheKey, GenreActivity>

    private(set) var snapshot = ListeningSnapshot.empty
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = true
    private(set) var selectedHistoryDay: HistoryDayBounds?
    private(set) var selectedDayListens: [Listen] = []
    private(set) var isLoadingSelectedDay = false
    private(set) var isLoadingMoreSelectedDay = false
    private(set) var canLoadMoreSelectedDay = false
    private(set) var selectedDayError: String?
    private(set) var listeningActivity: [ListeningActivityPeriod: ListeningActivityLoadState] = [:]
    private var listeningActivityRequestIDs: [ListeningActivityPeriod: UUID] = [:]
    private(set) var dailyActivity: [ListeningActivityPeriod: DailyActivityLoadState] = [:]
    private(set) var dailyActivityRefreshMessages: [ListeningActivityPeriod: String] = [:]
    private var dailyActivityRequestIDs: [ListeningActivityPeriod: UUID] = [:]
    private(set) var eraActivity: [ListeningActivityPeriod: EraActivityLoadState] = [:]
    private(set) var eraActivityRefreshMessages: [ListeningActivityPeriod: String] = [:]
    private var eraActivityRequestIDs: [ListeningActivityPeriod: UUID] = [:]
    private(set) var artistEvolutionActivity: [ListeningActivityPeriod: ArtistEvolutionLoadState] = [:]
    private(set) var artistEvolutionRefreshMessages: [ListeningActivityPeriod: String] = [:]
    private var artistEvolutionRequestIDs: [ListeningActivityPeriod: UUID] = [:]
    private(set) var genreActivity: [ListeningActivityPeriod: GenreActivityLoadState] = [:]
    private(set) var genreActivityRefreshMessages: [ListeningActivityPeriod: String] = [:]
    private var genreActivityRequestIDs: [ListeningActivityPeriod: UUID] = [:]
    var feedback: [String: RecordingFeedback] = [:]
    var actionError: String?
    private var didLoad = false
    private var cacheLease: UUID?
    private var selectedDayRequestID: UUID?

    init(
        account: Account,
        provider: (any ListeningProvider)? = nil,
        cache: SnapshotCache = .shared,
        dailyActivityCache: EntityDetailCache<DailyActivityCacheKey, DailyActivity> = EntityDetailCaches.dailyActivity,
        eraActivityCache: EntityDetailCache<EraActivityCacheKey, EraActivity> = EntityDetailCaches.eraActivity,
        artistEvolutionActivityCache: EntityDetailCache<ArtistEvolutionActivityCacheKey, ArtistEvolutionActivity> = EntityDetailCaches.artistEvolutionActivity,
        genreActivityCache: EntityDetailCache<GenreActivityCacheKey, GenreActivity> = EntityDetailCaches.genreActivity
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzProvider(token: account.token)
        self.cache = cache
        self.dailyActivityCache = dailyActivityCache
        self.eraActivityCache = eraActivityCache
        self.artistEvolutionActivityCache = artistEvolutionActivityCache
        self.genreActivityCache = genreActivityCache
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        let lease = await cache.beginSession(username: account.username)
        cacheLease = lease
        if let cached = await cache.load(username: account.username, lease: lease) {
            snapshot = cached
            phase = .refreshing
        } else {
            phase = .loading
        }
        await refresh()
    }

    func refresh() async {
        if phase == .ready { phase = .refreshing }
        do {
            let newListens = try await provider.recentListens(
                username: account.username,
                before: nil,
                count: 40
            )
            snapshot.recentListens = newListens
            snapshot.savedAt = .now
            canLoadMore = newListens.count == 40
            phase = .ready
            await saveSnapshot()

            snapshot.playingNow = try? await provider.playingNow(username: account.username)
            snapshot.savedAt = .now
            await saveSnapshot()
            await loadSupplementalData()
        } catch {
            phase = snapshot.recentListens.isEmpty ? .failed(error.localizedDescription) : .ready
            actionError = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoadingMore, canLoadMore, let oldest = snapshot.recentListens.last?.listenedAt else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            // max_ts is exclusive and second-granular. Overlap one second and
            // de-duplicate so ordinary page boundaries cannot drop siblings
            // that share the oldest visible timestamp.
            let values = try await provider.recentListens(
                username: account.username,
                before: oldest.addingTimeInterval(1),
                count: 100
            )
            let existing = Set(snapshot.recentListens.map(\.id))
            let additions = values.filter { !existing.contains($0.id) }
            snapshot.recentListens.append(contentsOf: additions)
            // A repeated full boundary page cannot advance this timestamp
            // cursor. Stop instead of issuing the same request indefinitely.
            canLoadMore = values.count == 100 && !additions.isEmpty
            snapshot.savedAt = .now
            await saveSnapshot()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func selectHistoryDay(_ day: Date, calendar: Calendar = .autoupdatingCurrent) async {
        await loadSelectedHistoryDay(HistoryDayBounds(day: day, calendar: calendar))
    }

    func refreshSelectedHistoryDay() async {
        guard let selectedHistoryDay else { return }
        await loadSelectedHistoryDay(selectedHistoryDay)
    }

    private func loadSelectedHistoryDay(_ bounds: HistoryDayBounds) async {
        let requestID = UUID()
        selectedDayRequestID = requestID
        selectedHistoryDay = bounds
        selectedDayListens = []
        selectedDayError = nil
        canLoadMoreSelectedDay = false
        // A new day or a refresh supersedes any pagination task. Its stale
        // defer must not leave the replacement day permanently "loading more."
        isLoadingMoreSelectedDay = false
        isLoadingSelectedDay = true

        do {
            let values = try await provider.recentListens(
                username: account.username,
                before: bounds.latest,
                after: bounds.earliest,
                count: 100
            )
            guard selectedDayRequestID == requestID else { return }
            guard !Task.isCancelled else {
                isLoadingSelectedDay = false
                return
            }
            selectedDayListens = values
            canLoadMoreSelectedDay = values.count == 100
            isLoadingSelectedDay = false
        } catch {
            guard selectedDayRequestID == requestID else { return }
            isLoadingSelectedDay = false
            if Task.isCancelled
                || error is CancellationError
                || (error as? URLError)?.code == .cancelled {
                return
            }
            selectedDayError = error.localizedDescription
        }
    }

    func loadMoreSelectedHistoryDay() async {
        guard !isLoadingSelectedDay,
              !isLoadingMoreSelectedDay,
              canLoadMoreSelectedDay,
              let bounds = selectedHistoryDay,
              let oldest = selectedDayListens.last?.listenedAt
        else { return }

        let requestID = UUID()
        selectedDayRequestID = requestID
        selectedDayError = nil
        isLoadingMoreSelectedDay = true
        defer {
            if selectedDayRequestID == requestID {
                isLoadingMoreSelectedDay = false
            }
        }

        do {
            // Keep the same inclusive day lower bound while overlapping the
            // second at the older cursor, then reject duplicates locally.
            let values = try await provider.recentListens(
                username: account.username,
                before: oldest.addingTimeInterval(1),
                after: bounds.earliest,
                count: 100
            )
            guard selectedDayRequestID == requestID, !Task.isCancelled else { return }
            let existing = Set(selectedDayListens.map(\.id))
            let additions = values.filter { !existing.contains($0.id) }
            selectedDayListens.append(contentsOf: additions)
            // A full response with no new identities means this cursor cannot
            // make progress (for example, a server-side repeated boundary).
            canLoadMoreSelectedDay = values.count == 100 && !additions.isEmpty
        } catch {
            guard selectedDayRequestID == requestID, !Task.isCancelled else { return }
            selectedDayError = error.localizedDescription
        }
    }

    func showLatestHistory() {
        selectedDayRequestID = UUID()
        selectedHistoryDay = nil
        selectedDayListens = []
        selectedDayError = nil
        isLoadingSelectedDay = false
        isLoadingMoreSelectedDay = false
        canLoadMoreSelectedDay = false
    }

    func setFeedback(_ value: RecordingFeedback, for recording: Recording) async {
        guard account.isAuthenticated else {
            actionError = "Sign in with a token to love or hate recordings."
            return
        }
        let previous = feedback[recording.id] ?? .none
        feedback[recording.id] = value
        do {
            try await provider.submitFeedback(value, for: recording)
        } catch {
            feedback[recording.id] = previous
            actionError = error.localizedDescription
        }
    }

    func activityState(for period: ListeningActivityPeriod) -> ListeningActivityLoadState {
        listeningActivity[period] ?? .idle
    }

    func loadListeningActivity(for period: ListeningActivityPeriod, retrying: Bool = false) async {
        switch activityState(for: period) {
        case .loaded where !retrying:
            return
        case .failed where !retrying:
            return
        case .idle, .loading, .loaded, .failed:
            listeningActivity[period] = .loading
        }

        // SwiftUI cancels the previous `.task(id:)` before starting its
        // replacement, but cancellation can take a moment to reach the
        // provider. Let the replacement supersede that request and prevent
        // the older task from resetting the newer state when it unwinds.
        let requestID = UUID()
        listeningActivityRequestIDs[period] = requestID

        do {
            let activity = try await provider.listenActivity(username: account.username, period: period)
            guard listeningActivityRequestIDs[period] == requestID else { return }
            listeningActivity[period] = .loaded(activity)
            listeningActivityRequestIDs[period] = nil
        } catch {
            guard listeningActivityRequestIDs[period] == requestID else { return }
            listeningActivity[period] = Task.isCancelled
                ? .idle
                : .failed(error.localizedDescription)
            listeningActivityRequestIDs[period] = nil
        }
    }

    func dailyActivityState(for period: ListeningActivityPeriod) -> DailyActivityLoadState {
        dailyActivity[period] ?? .idle
    }

    func dailyActivityRefreshMessage(for period: ListeningActivityPeriod) -> String? {
        dailyActivityRefreshMessages[period]
    }

    /// Loads only the selected server range. A stale cached matrix remains
    /// visible during revalidation, and any refresh failure leaves it usable.
    func loadDailyActivity(for period: ListeningActivityPeriod, retrying: Bool = false) async {
        let key = DailyActivityCacheKey(username: account.username, period: period)
        if !retrying, dailyActivityRequestIDs[period] != nil {
            return
        }

        if let cached = await dailyActivityCache.value(for: key) {
            dailyActivity[period] = .loaded(cached.value)
            if cached.isFresh, !retrying {
                return
            }
        } else {
            if !retrying {
                switch dailyActivityState(for: period) {
                case .loaded, .unavailable, .loading:
                    return
                case .idle, .failed:
                    break
                }
            }
            dailyActivity[period] = .loading
        }

        dailyActivityRefreshMessages[period] = nil
        let requestID = UUID()
        dailyActivityRequestIDs[period] = requestID

        do {
            let result = try await provider.dailyActivity(username: account.username, period: period)
            try Task.checkCancellation()
            guard dailyActivityRequestIDs[period] == requestID else { return }
            guard let result else {
                dailyActivity[period] = .unavailable
                dailyActivityRequestIDs[period] = nil
                return
            }
            dailyActivity[period] = .loaded(result)
            dailyActivityRequestIDs[period] = nil
            await dailyActivityCache.save(result, for: key)
        } catch is CancellationError {
            guard dailyActivityRequestIDs[period] == requestID else { return }
            dailyActivityRequestIDs[period] = nil
            if case .loading = dailyActivityState(for: period) {
                dailyActivity[period] = .idle
            }
        } catch {
            guard dailyActivityRequestIDs[period] == requestID else { return }
            dailyActivityRequestIDs[period] = nil
            if case .loaded = dailyActivityState(for: period) {
                dailyActivityRefreshMessages[period] = error.localizedDescription
            } else {
                dailyActivity[period] = .failed(error.localizedDescription)
            }
        }
    }

    func eraActivityState(for period: ListeningActivityPeriod) -> EraActivityLoadState {
        eraActivity[period] ?? .idle
    }

    func eraActivityRefreshMessage(for period: ListeningActivityPeriod) -> String? {
        eraActivityRefreshMessages[period]
    }

    /// Loads one server-calculated release-year distribution for the selected
    /// range. Stale data remains usable while ListenBrainz is revalidating it.
    func loadEraActivity(for period: ListeningActivityPeriod, retrying: Bool = false) async {
        let key = EraActivityCacheKey(username: account.username, period: period)
        if !retrying, eraActivityRequestIDs[period] != nil {
            return
        }

        if let cached = await eraActivityCache.value(for: key) {
            eraActivity[period] = .loaded(cached.value)
            if cached.isFresh, !retrying {
                return
            }
        } else {
            if !retrying {
                switch eraActivityState(for: period) {
                case .loaded, .unavailable, .loading:
                    return
                case .idle, .failed:
                    break
                }
            }
            eraActivity[period] = .loading
        }

        eraActivityRefreshMessages[period] = nil
        let requestID = UUID()
        eraActivityRequestIDs[period] = requestID

        do {
            let result = try await provider.eraActivity(username: account.username, period: period)
            try Task.checkCancellation()
            guard eraActivityRequestIDs[period] == requestID else { return }
            guard let result else {
                eraActivity[period] = .unavailable
                eraActivityRequestIDs[period] = nil
                return
            }
            eraActivity[period] = .loaded(result)
            eraActivityRequestIDs[period] = nil
            await eraActivityCache.save(result, for: key)
        } catch is CancellationError {
            guard eraActivityRequestIDs[period] == requestID else { return }
            eraActivityRequestIDs[period] = nil
            if case .loading = eraActivityState(for: period) {
                eraActivity[period] = .idle
            }
        } catch {
            guard eraActivityRequestIDs[period] == requestID else { return }
            eraActivityRequestIDs[period] = nil
            if case .loaded = eraActivityState(for: period) {
                eraActivityRefreshMessages[period] = error.localizedDescription
            } else {
                eraActivity[period] = .failed(error.localizedDescription)
            }
        }
    }

    func artistEvolutionState(for period: ListeningActivityPeriod) -> ArtistEvolutionLoadState {
        artistEvolutionActivity[period] ?? .idle
    }

    func artistEvolutionRefreshMessage(for period: ListeningActivityPeriod) -> String? {
        artistEvolutionRefreshMessages[period]
    }

    /// Loads a single server-calculated range only after the dedicated detail
    /// screen is opened. Stale chart data remains visible during revalidation.
    func loadArtistEvolution(for period: ListeningActivityPeriod, retrying: Bool = false) async {
        let key = ArtistEvolutionActivityCacheKey(username: account.username, period: period)
        if !retrying, artistEvolutionRequestIDs[period] != nil {
            return
        }

        if let cached = await artistEvolutionActivityCache.value(for: key) {
            artistEvolutionActivity[period] = .loaded(cached.value)
            if cached.isFresh, !retrying {
                return
            }
        } else {
            if !retrying {
                switch artistEvolutionState(for: period) {
                case .loaded, .unavailable, .loading:
                    return
                case .idle, .failed:
                    break
                }
            }
            artistEvolutionActivity[period] = .loading
        }

        artistEvolutionRefreshMessages[period] = nil
        let requestID = UUID()
        artistEvolutionRequestIDs[period] = requestID

        do {
            let result = try await provider.artistEvolutionActivity(
                username: account.username,
                period: period
            )
            try Task.checkCancellation()
            guard artistEvolutionRequestIDs[period] == requestID else { return }
            guard let result else {
                artistEvolutionActivity[period] = .unavailable
                artistEvolutionRequestIDs[period] = nil
                return
            }
            artistEvolutionActivity[period] = .loaded(result)
            artistEvolutionRequestIDs[period] = nil
            await artistEvolutionActivityCache.save(result, for: key)
        } catch is CancellationError {
            guard artistEvolutionRequestIDs[period] == requestID else { return }
            artistEvolutionRequestIDs[period] = nil
            if case .loading = artistEvolutionState(for: period) {
                artistEvolutionActivity[period] = .idle
            }
        } catch {
            guard artistEvolutionRequestIDs[period] == requestID else { return }
            artistEvolutionRequestIDs[period] = nil
            if case .loaded = artistEvolutionState(for: period) {
                artistEvolutionRefreshMessages[period] = error.localizedDescription
            } else {
                artistEvolutionActivity[period] = .failed(error.localizedDescription)
            }
        }
    }

    func genreActivityState(for period: ListeningActivityPeriod) -> GenreActivityLoadState {
        genreActivity[period] ?? .idle
    }

    func genreActivityRefreshMessage(for period: ListeningActivityPeriod) -> String? {
        genreActivityRefreshMessages[period]
    }

    /// Loads one server-calculated UTC-hour genre aggregate. A stale response
    /// stays visible while it is revalidated, including if that refresh fails.
    func loadGenreActivity(for period: ListeningActivityPeriod, retrying: Bool = false) async {
        let key = GenreActivityCacheKey(username: account.username, period: period)
        if !retrying, genreActivityRequestIDs[period] != nil {
            return
        }

        if let cached = await genreActivityCache.value(for: key) {
            genreActivity[period] = .loaded(cached.value)
            if cached.isFresh, !retrying {
                return
            }
        } else {
            if !retrying {
                switch genreActivityState(for: period) {
                case .loaded, .unavailable, .loading:
                    return
                case .idle, .failed:
                    break
                }
            }
            genreActivity[period] = .loading
        }

        genreActivityRefreshMessages[period] = nil
        let requestID = UUID()
        genreActivityRequestIDs[period] = requestID

        do {
            let result = try await provider.genreActivity(username: account.username, period: period)
            try Task.checkCancellation()
            guard genreActivityRequestIDs[period] == requestID else { return }
            guard let result else {
                genreActivity[period] = .unavailable
                genreActivityRequestIDs[period] = nil
                return
            }
            genreActivity[period] = .loaded(result)
            genreActivityRequestIDs[period] = nil
            await genreActivityCache.save(result, for: key)
        } catch is CancellationError {
            guard genreActivityRequestIDs[period] == requestID else { return }
            genreActivityRequestIDs[period] = nil
            if case .loading = genreActivityState(for: period) {
                genreActivity[period] = .idle
            }
        } catch {
            guard genreActivityRequestIDs[period] == requestID else { return }
            genreActivityRequestIDs[period] = nil
            if case .loaded = genreActivityState(for: period) {
                genreActivityRefreshMessages[period] = error.localizedDescription
            } else {
                genreActivity[period] = .failed(error.localizedDescription)
            }
        }
    }

    func listens(for artist: RankedArtist) -> [Listen] {
        snapshot.recentListens.filter { listen in
            if let mbid = artist.mbid, listen.recording.artistMBIDs.contains(mbid) { return true }
            return listen.recording.artistName.localizedCaseInsensitiveCompare(artist.name) == .orderedSame
        }
    }

    func recordings(for artist: RankedArtist) -> [RankedRecording] {
        snapshot.topRecordings.filter { recording in
            if let mbid = artist.mbid, recording.artistMBIDs.contains(mbid) { return true }
            return recording.artistName.localizedCaseInsensitiveCompare(artist.name) == .orderedSame
        }
    }

    private func loadSupplementalData() async {
        if let count = try? await provider.listenCount(username: account.username) {
            snapshot.listenCount = count
        }
        if let artists = try? await provider.topArtists(username: account.username, count: 20) {
            snapshot.topArtists = artists
        }
        if let releases = try? await provider.topReleases(username: account.username, count: 20) {
            snapshot.topReleases = releases
        }
        if let recordings = try? await provider.topRecordings(username: account.username, count: 50) {
            snapshot.topRecordings = recordings
        }
        snapshot.savedAt = .now
        await saveSnapshot()
    }

    private func saveSnapshot() async {
        guard let cacheLease else { return }
        await cache.save(snapshot, username: account.username, lease: cacheLease)
    }
}
