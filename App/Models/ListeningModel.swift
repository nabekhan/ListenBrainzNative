import Darwin
import Foundation
import Observation

@MainActor
@Observable
final class ListeningModel {
    private struct ArtistActivityFlight {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct ReleaseGroupRankingFlight {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct ListenDeletionKey: Hashable, Sendable {
        let listenedAt: Int
        let recordingMSID: UUID

        init?(_ listen: Listen) {
            guard let recordingMSID = listen.recording.identity.msid else { return nil }
            self.listenedAt = Int(listen.listenedAt.timeIntervalSince1970)
            self.recordingMSID = recordingMSID
        }
    }

    enum Phase: Equatable {
        case idle
        case loading
        case refreshing
        case ready
        case failed(String)
    }

    let account: Account
    private let provider: any ListeningProvider
    private let cacheScope: RequestGate.ReadScope
    private let cache: SnapshotCache
    private let dailyActivityCache: EntityDetailCache<DailyActivityCacheKey, DailyActivity>
    private let eraActivityCache: EntityDetailCache<EraActivityCacheKey, EraActivity>
    private let artistEvolutionActivityCache: EntityDetailCache<ArtistEvolutionActivityCacheKey, ArtistEvolutionActivity>
    private let genreActivityCache: EntityDetailCache<GenreActivityCacheKey, GenreActivity>
    private let artistOriginsCache: EntityDetailCache<ArtistOriginsCacheKey, ArtistOrigins>
    private let artistActivityCache: EntityDetailCache<ArtistActivityCacheKey, ArtistActivity>
    private let releaseGroupRankingCache: EntityDetailCache<ReleaseGroupRankingCacheKey, [RankedReleaseGroup]>
    private let deletionJournal: ListenDeletionSafetyJournal

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
    private(set) var artistOrigins: [ListeningActivityPeriod: ArtistOriginsLoadState] = [:]
    private(set) var artistOriginsRefreshMessages: [ListeningActivityPeriod: String] = [:]
    private var artistOriginsRequestIDs: [ListeningActivityPeriod: UUID] = [:]
    private(set) var artistActivity: [ListeningActivityPeriod: ArtistActivityLoadState] = [:]
    private(set) var artistActivityRefreshMessages: [ListeningActivityPeriod: String] = [:]
    private var artistActivityFlights: [ListeningActivityPeriod: ArtistActivityFlight] = [:]
    private(set) var releaseGroupRankingState: ReleaseGroupRankingLoadState = .idle
    private(set) var releaseGroupRankingRefreshMessage: String?
    private var releaseGroupRankingFlight: ReleaseGroupRankingFlight?
    var feedback: [String: RecordingFeedback] = [:]
    var actionError: String?
    var deletionNotice: String?
    var deletionSafetyRecoveryNeeded = false
    private var didLoad = false
    private var cacheLease: UUID?
    private var selectedDayRequestID: UUID?
    private var deletionRequestsInFlight: Set<ListenDeletionKey> = []

    init(
        account: Account,
        provider: (any ListeningProvider)? = nil,
        cache: SnapshotCache = .shared,
        dailyActivityCache: EntityDetailCache<DailyActivityCacheKey, DailyActivity> = EntityDetailCaches.dailyActivity,
        eraActivityCache: EntityDetailCache<EraActivityCacheKey, EraActivity> = EntityDetailCaches.eraActivity,
        artistEvolutionActivityCache: EntityDetailCache<ArtistEvolutionActivityCacheKey, ArtistEvolutionActivity> = EntityDetailCaches.artistEvolutionActivity,
        genreActivityCache: EntityDetailCache<GenreActivityCacheKey, GenreActivity> = EntityDetailCaches.genreActivity,
        artistOriginsCache: EntityDetailCache<ArtistOriginsCacheKey, ArtistOrigins> = EntityDetailCaches.artistOrigins,
        artistActivityCache: EntityDetailCache<ArtistActivityCacheKey, ArtistActivity> = EntityDetailCaches.artistActivity,
        releaseGroupRankingCache: EntityDetailCache<ReleaseGroupRankingCacheKey, [RankedReleaseGroup]> = EntityDetailCaches.releaseGroupRankings,
        deletionJournal: ListenDeletionSafetyJournal = .shared
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzProvider(token: account.token)
        self.cacheScope = .authenticated(token: account.token)
        self.cache = cache
        self.dailyActivityCache = dailyActivityCache
        self.eraActivityCache = eraActivityCache
        self.artistEvolutionActivityCache = artistEvolutionActivityCache
        self.genreActivityCache = genreActivityCache
        self.artistOriginsCache = artistOriginsCache
        self.artistActivityCache = artistActivityCache
        self.releaseGroupRankingCache = releaseGroupRankingCache
        self.deletionJournal = deletionJournal
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        let lease = await cache.beginSession(username: account.username)
        cacheLease = lease
        if let cached = await cache.load(username: account.username, lease: lease) {
            var restored = cached
            let visibleListens = removingDeletedListens(from: restored.recentListens)
            var removedConfirmedDeletion = visibleListens.count != restored.recentListens.count
            restored.recentListens = visibleListens
            if let playingNow = restored.playingNow,
               let key = ListenDeletionKey(playingNow),
               deletionJournal.state(
                   username: account.username,
                   listenedAt: key.listenedAt,
                   recordingMSID: key.recordingMSID
               ) == .confirmed {
                restored.playingNow = nil
                removedConfirmedDeletion = true
            }
            snapshot = restored
            phase = .refreshing
            if removedConfirmedDeletion {
                await saveSnapshot()
            }
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
            snapshot.recentListens = removingDeletedListens(from: newListens)
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
            let additions = removingDeletedListens(from: values).filter { !existing.contains($0.id) }
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
            selectedDayListens = removingDeletedListens(from: values)
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
            let additions = removingDeletedListens(from: values).filter { !existing.contains($0.id) }
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
            actionError = String(localized: "Sign in with a token to love or hate recordings.")
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

    func isDeletionIndeterminate(_ listen: Listen) -> Bool {
        guard let key = ListenDeletionKey(listen) else { return false }
        return deletionJournal.state(
            username: account.username,
            listenedAt: key.listenedAt,
            recordingMSID: key.recordingMSID
        ) == .indeterminate
    }

    func deleteListen(_ listen: Listen) async {
        await performListenDeletion(listen, retryingIndeterminateAttempt: false)
    }

    func retryListenDeletionAnyway(_ listen: Listen) async {
        await performListenDeletion(listen, retryingIndeterminateAttempt: true)
    }

    func dismissDeletionSafetyRecovery() {
        deletionSafetyRecoveryNeeded = false
    }

    func resetDeletionSafetyData() {
        guard deletionJournal.resetUnreadableStorage() else {
            actionError = String(localized: "Brainz couldn’t reset its deletion record. Restart the app and try again.")
            return
        }
        deletionSafetyRecoveryNeeded = false
    }

    private func performListenDeletion(_ listen: Listen, retryingIndeterminateAttempt: Bool) async {
        guard account.isAuthenticated else {
            actionError = String(localized: "Sign in to delete this listen.")
            return
        }
        guard !listen.isPlayingNow else {
            actionError = String(localized: "Wait until this track appears in your history, then delete it.")
            return
        }
        guard let key = ListenDeletionKey(listen) else {
            actionError = String(localized: "ListenBrainz hasn’t assigned this listen an ID, so it can’t be deleted yet.")
            return
        }
        guard !deletionRequestsInFlight.contains(key) else { return }
        guard !deletionJournal.requiresRecovery else {
            deletionSafetyRecoveryNeeded = true
            return
        }
        let priorState = deletionJournal.state(
            username: account.username,
            listenedAt: key.listenedAt,
            recordingMSID: key.recordingMSID
        )
        guard priorState != .confirmed else {
            actionError = String(localized: "Deletion is already scheduled. This listen wasn’t sent again.")
            return
        }

        guard priorState != .indeterminate || retryingIndeterminateAttempt else {
            actionError = String(localized: "The first request couldn’t be confirmed, so Brainz didn’t send it again. Wait until after the next hour, then refresh.")
            return
        }

        deletionRequestsInFlight.insert(key)
        defer { deletionRequestsInFlight.remove(key) }
        var reservedExistingIndeterminateAttempt: Bool?
        do {
            let canonicalUsername = try await provider.validateToken()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard canonicalUsername == account.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                actionError = String(localized: "No deletion was sent. This token belongs to another account. Sign in again.")
                return
            }

            let reservation = deletionJournal.reserveAttempt(
                username: account.username,
                listenedAt: key.listenedAt,
                recordingMSID: key.recordingMSID,
                retryingIndeterminateAttempt: retryingIndeterminateAttempt
            )
            switch reservation {
            case let .reserved(previouslyIndeterminate):
                reservedExistingIndeterminateAttempt = previouslyIndeterminate
            case .inFlight:
                actionError = String(localized: "This deletion is already in progress.")
                return
            case .confirmed:
                actionError = String(localized: "Deletion is already scheduled. This listen wasn’t sent again.")
                return
            case .indeterminate:
                actionError = String(localized: "The first request couldn’t be confirmed, so Brainz didn’t send it again. Wait until after the next hour, then refresh.")
                return
            case .unavailable:
                deletionSafetyRecoveryNeeded = true
                return
            }
            defer {
                deletionJournal.releaseReservation(
                    username: account.username,
                    listenedAt: key.listenedAt,
                    recordingMSID: key.recordingMSID
                )
            }

            try await provider.deleteListen(listenedAt: listen.listenedAt, recordingMSID: key.recordingMSID)
            deletionJournal.markConfirmed(
                username: account.username,
                listenedAt: key.listenedAt,
                recordingMSID: key.recordingMSID
            )
            removeDeletedListen(key)
            deletionNotice = String(localized: "ListenBrainz usually removes it shortly after the next hour. Statistics may update later.")
            await saveSnapshot()
        } catch is CancellationError {
            // The delete transport never started. Clear only a new provisional
            // marker; an older indeterminate attempt remains unresolved.
            if reservedExistingIndeterminateAttempt == false {
                deletionJournal.resolve(username: account.username, listenedAt: key.listenedAt, recordingMSID: key.recordingMSID)
            }
        } catch ProviderError.deleteListenOutcomeUnknown {
            actionError = ProviderError.deleteListenOutcomeUnknown.localizedDescription
        } catch {
            // A response-backed failure means the server did not accept this
            // deletion. Keep the visible listen and allow a later retry.
            if reservedExistingIndeterminateAttempt == false {
                deletionJournal.resolve(username: account.username, listenedAt: key.listenedAt, recordingMSID: key.recordingMSID)
            }
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
        let key = DailyActivityCacheKey(username: account.username, scope: cacheScope, period: period)
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
        let key = EraActivityCacheKey(username: account.username, scope: cacheScope, period: period)
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
        let key = ArtistEvolutionActivityCacheKey(username: account.username, scope: cacheScope, period: period)
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

    func artistOriginsState(for period: ListeningActivityPeriod) -> ArtistOriginsLoadState {
        artistOrigins[period] ?? .idle
    }

    func artistOriginsRefreshMessage(for period: ListeningActivityPeriod) -> String? {
        artistOriginsRefreshMessages[period]
    }

    func artistActivityState(for period: ListeningActivityPeriod) -> ArtistActivityLoadState {
        artistActivity[period] ?? .idle
    }

    func artistActivityRefreshMessage(for period: ListeningActivityPeriod) -> String? {
        artistActivityRefreshMessages[period]
    }

    /// Fetches one bounded aggregate only after the Artist Activity destination opens.
    /// The unstructured flight outlives a cancelled view task so a quick
    /// dismiss-and-reopen can join the same intentional request instead of
    /// leaving the replacement screen idle or starting an overlapping read.
    func loadArtistActivity(for period: ListeningActivityPeriod, retrying: Bool = false) async {
        let key = ArtistActivityCacheKey(username: account.username, scope: cacheScope, period: period)
        var hasVisibleValue = false

        if let cached = await artistActivityCache.value(for: key) {
            artistActivity[period] = .loaded(cached.value)
            hasVisibleValue = true
            if cached.isFresh, !retrying { return }
        } else if case .loaded = artistActivityState(for: period) {
            hasVisibleValue = true
        }

        if let flight = artistActivityFlights[period] {
            await flight.task.value
            return
        }

        if !retrying, case .unavailable = artistActivityState(for: period) {
            return
        }
        if !hasVisibleValue {
            artistActivity[period] = .loading
        }

        artistActivityRefreshMessages[period] = nil
        let flightID = UUID()
        let provider = self.provider
        let username = account.username
        let cache = artistActivityCache
        let task = Task { @MainActor [weak self] in
            let outcome: Result<ArtistActivity?, Error>
            do {
                outcome = .success(try await provider.artistActivity(username: username, period: period))
            } catch {
                outcome = .failure(error)
            }

            guard let self else { return }
            defer {
                if self.artistActivityFlights[period]?.id == flightID {
                    self.artistActivityFlights.removeValue(forKey: period)
                }
            }
            guard self.artistActivityFlights[period]?.id == flightID else { return }

            switch outcome {
            case let .success(result):
                guard let result else {
                    self.artistActivity[period] = .unavailable
                    return
                }
                self.artistActivity[period] = .loaded(result)
                await cache.save(result, for: key)
            case let .failure(error) where error is CancellationError:
                if case .loading = self.artistActivityState(for: period) {
                    self.artistActivity[period] = .idle
                }
            case let .failure(error):
                if case .loaded = self.artistActivityState(for: period) {
                    self.artistActivityRefreshMessages[period] = error.localizedDescription
                } else {
                    self.artistActivity[period] = .failed(error.localizedDescription)
                }
            }
        }
        artistActivityFlights[period] = ArtistActivityFlight(id: flightID, task: task)
        await task.value
    }

    /// Ends report reads when the authenticated app surface is torn down.
    /// A destination-level cancellation does not call this so a quick reopen
    /// can still join its single bounded request.
    func cancelArtistActivityLoads() {
        let flights = Array(artistActivityFlights.values)
        artistActivityFlights.removeAll()
        for flight in flights {
            flight.task.cancel()
        }
        for period in ListeningActivityPeriod.allCases
        where artistActivityState(for: period) == .loading {
            artistActivity[period] = .idle
        }
    }

    /// Loads the full precomputed Artist Origins response only when its future
    /// detail screen asks for it. Stale data remains useful while the one
    /// exact user-and-range request is revalidated.
    func loadArtistOrigins(for period: ListeningActivityPeriod, retrying: Bool = false) async {
        let key = ArtistOriginsCacheKey(username: account.username, scope: cacheScope, period: period)
        if !retrying, artistOriginsRequestIDs[period] != nil {
            return
        }

        if let cached = await artistOriginsCache.value(for: key) {
            artistOrigins[period] = .loaded(cached.value)
            if cached.isFresh, !retrying {
                return
            }
        } else {
            if !retrying {
                switch artistOriginsState(for: period) {
                case .loaded, .unavailable, .loading:
                    return
                case .idle, .failed:
                    break
                }
            }
            artistOrigins[period] = .loading
        }

        artistOriginsRefreshMessages[period] = nil
        let requestID = UUID()
        artistOriginsRequestIDs[period] = requestID

        do {
            let result = try await provider.artistOrigins(username: account.username, period: period)
            try Task.checkCancellation()
            guard artistOriginsRequestIDs[period] == requestID else { return }
            guard let result else {
                artistOrigins[period] = .unavailable
                artistOriginsRequestIDs[period] = nil
                return
            }
            artistOrigins[period] = .loaded(result)
            artistOriginsRequestIDs[period] = nil
            await artistOriginsCache.save(result, for: key)
        } catch is CancellationError {
            guard artistOriginsRequestIDs[period] == requestID else { return }
            artistOriginsRequestIDs[period] = nil
            if case .loading = artistOriginsState(for: period) {
                artistOrigins[period] = .idle
            }
        } catch {
            guard artistOriginsRequestIDs[period] == requestID else { return }
            artistOriginsRequestIDs[period] = nil
            if case .loaded = artistOriginsState(for: period) {
                artistOriginsRefreshMessages[period] = error.localizedDescription
            } else {
                artistOrigins[period] = .failed(error.localizedDescription)
            }
        }
    }

    /// Loads one server-calculated UTC-hour genre aggregate. A stale response
    /// stays visible while it is revalidated, including if that refresh fails.
    func loadGenreActivity(for period: ListeningActivityPeriod, retrying: Bool = false) async {
        let key = GenreActivityCacheKey(username: account.username, scope: cacheScope, period: period)
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

    /// Loads the all-time release-group ranking only after it is requested by
    /// Taste. Cached values stay visible while an explicit refresh validates
    /// them, and repeated selection joins one model-owned provider read.
    func loadReleaseGroupRanking(retrying: Bool = false) async {
        let key = ReleaseGroupRankingCacheKey(username: account.username, scope: cacheScope)
        var hasVisibleValue = false
        var shouldRevalidateCachedValue = false

        if let cached = await releaseGroupRankingCache.value(for: key) {
            releaseGroupRankingState = .loaded(cached.value)
            hasVisibleValue = true
            if cached.isFresh, !retrying { return }
            shouldRevalidateCachedValue = true
        } else if case .loaded = releaseGroupRankingState {
            hasVisibleValue = true
        }

        if let flight = releaseGroupRankingFlight {
            await flight.task.value
            return
        }

        if !retrying, !shouldRevalidateCachedValue {
            switch releaseGroupRankingState {
            case .loaded, .failed:
                return
            case .idle, .loading:
                break
            }
        }
        if !hasVisibleValue {
            releaseGroupRankingState = .loading
        }

        releaseGroupRankingRefreshMessage = nil
        let flightID = UUID()
        let provider = self.provider
        let username = account.username
        let cache = releaseGroupRankingCache
        let task = Task { @MainActor [weak self] in
            let outcome: Result<[RankedReleaseGroup], Error>
            do {
                outcome = .success(try await provider.topReleaseGroups(username: username, count: 20))
            } catch {
                outcome = .failure(error)
            }

            guard let self else { return }
            defer {
                if self.releaseGroupRankingFlight?.id == flightID {
                    self.releaseGroupRankingFlight = nil
                }
            }
            guard self.releaseGroupRankingFlight?.id == flightID else { return }

            switch outcome {
            case let .success(groups):
                self.releaseGroupRankingState = .loaded(groups)
                await cache.save(groups, for: key)
            case let .failure(error) where error is CancellationError:
                if case .loading = self.releaseGroupRankingState {
                    self.releaseGroupRankingState = .idle
                }
            case let .failure(error):
                if case .loaded = self.releaseGroupRankingState {
                    self.releaseGroupRankingRefreshMessage = error.localizedDescription
                } else {
                    self.releaseGroupRankingState = .failed(error.localizedDescription)
                }
            }
        }
        releaseGroupRankingFlight = ReleaseGroupRankingFlight(id: flightID, task: task)
        await task.value
    }

    /// Taste refreshes this optional ranking only after the user has opened it.
    func refreshReleaseGroupRankingIfLoaded() async {
        guard case .loaded = releaseGroupRankingState else { return }
        await loadReleaseGroupRanking(retrying: true)
    }

    /// Cancels the model-owned read when the authenticated app surface ends.
    /// Switching ranking choices does not call this, allowing a quick return
    /// to join the same intentional request.
    func cancelReleaseGroupRankingLoad() {
        let flight = releaseGroupRankingFlight
        releaseGroupRankingFlight = nil
        flight?.task.cancel()
        if case .loading = releaseGroupRankingState {
            releaseGroupRankingState = .idle
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

    private func removingDeletedListens(from listens: [Listen]) -> [Listen] {
        listens.filter { listen in
            guard let key = ListenDeletionKey(listen) else { return true }
            return deletionJournal.state(
                username: account.username,
                listenedAt: key.listenedAt,
                recordingMSID: key.recordingMSID
            ) != .confirmed
        }
    }

    private func removeDeletedListen(_ key: ListenDeletionKey) {
        snapshot.recentListens = snapshot.recentListens.filter { ListenDeletionKey($0) != key }
        selectedDayListens = selectedDayListens.filter { ListenDeletionKey($0) != key }
        if let playingNow = snapshot.playingNow, ListenDeletionKey(playingNow) == key {
            snapshot.playingNow = nil
        }
    }
}

enum ListenDeletionSafetyState: String, Codable, Equatable, Sendable {
    case indeterminate
    case confirmed
}

enum ListenDeletionReservation: Equatable, Sendable {
    case reserved(previouslyIndeterminate: Bool)
    case inFlight
    case confirmed
    case indeterminate
    case unavailable
}

struct ListenDeletionSafetyRecord: Codable, Equatable, Sendable {
    let username: String
    let listenedAt: Int
    let recordingMSID: UUID
    let attemptedAt: Date
    var state: ListenDeletionSafetyState
}

/// Durable, token-free state for accepted or unresolved delete POSTs. The
/// server queues accepted work, so a refresh is not proof that replay is safe.
@MainActor
final class ListenDeletionSafetyJournal {
    static let shared: ListenDeletionSafetyJournal = {
        let fileManager = FileManager.default
        guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return ListenDeletionSafetyJournal(storageUnavailable: true)
        }
        return ListenDeletionSafetyJournal(
            fileURL: root
                .appending(path: "Brainz", directoryHint: .isDirectory)
                .appending(path: "listen-deletion-journal-v1.json")
        )
    }()

    private let fileURL: URL?
    private var records: [String: ListenDeletionSafetyRecord]
    private var activeReservations: Set<String> = []
    private(set) var requiresRecovery: Bool

    /// A nil URL is an in-memory store intended for focused tests. Production
    /// always supplies the Application Support URL above.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        let loaded = Self.load(fileURL: fileURL)
        records = loaded.records
        requiresRecovery = loaded.requiresRecovery
    }

    private init(storageUnavailable: Bool) {
        fileURL = nil
        records = [:]
        requiresRecovery = storageUnavailable
    }

    func state(username: String, listenedAt: Int, recordingMSID: UUID) -> ListenDeletionSafetyState? {
        records[key(username: username, listenedAt: listenedAt, recordingMSID: recordingMSID)]?.state
    }

    /// Atomically establishes the persisted replay barrier and the transient
    /// cross-scene claim. Call only after the token owner has been verified.
    func reserveAttempt(
        username: String,
        listenedAt: Int,
        recordingMSID: UUID,
        retryingIndeterminateAttempt: Bool,
        at date: Date = .now
    ) -> ListenDeletionReservation {
        guard !requiresRecovery else { return .unavailable }
        let recordKey = key(username: username, listenedAt: listenedAt, recordingMSID: recordingMSID)
        guard !activeReservations.contains(recordKey) else { return .inFlight }

        let previousState = records[recordKey]?.state
        switch previousState {
        case .confirmed:
            return .confirmed
        case .indeterminate where !retryingIndeterminateAttempt:
            return .indeterminate
        case .indeterminate:
            activeReservations.insert(recordKey)
            return .reserved(previouslyIndeterminate: true)
        case nil:
            let normalizedUsername = Self.normalized(username)
            records[recordKey] = .init(
                username: normalizedUsername,
                listenedAt: listenedAt,
                recordingMSID: recordingMSID,
                attemptedAt: date,
                state: .indeterminate
            )
            guard persist() else {
                records.removeValue(forKey: recordKey)
                requiresRecovery = true
                return .unavailable
            }
            activeReservations.insert(recordKey)
            return .reserved(previouslyIndeterminate: false)
        }
    }

    func releaseReservation(username: String, listenedAt: Int, recordingMSID: UUID) {
        activeReservations.remove(key(username: username, listenedAt: listenedAt, recordingMSID: recordingMSID))
    }

    /// Must run before the provider is asked to acquire RequestGate, so a
    /// process crash after dispatch is always fail-closed on relaunch.
    func beginAttempt(username: String, listenedAt: Int, recordingMSID: UUID, at date: Date = .now) {
        guard !requiresRecovery else { return }
        let normalizedUsername = Self.normalized(username)
        records[key(username: normalizedUsername, listenedAt: listenedAt, recordingMSID: recordingMSID)] = .init(
            username: normalizedUsername,
            listenedAt: listenedAt,
            recordingMSID: recordingMSID,
            attemptedAt: date,
            state: .indeterminate
        )
        if !persist() {
            requiresRecovery = true
        }
    }

    func markConfirmed(username: String, listenedAt: Int, recordingMSID: UUID) {
        let recordKey = key(username: username, listenedAt: listenedAt, recordingMSID: recordingMSID)
        guard var record = records[recordKey] else { return }
        record.state = .confirmed
        records[recordKey] = record
        if !persist() {
            requiresRecovery = true
        }
    }

    /// Only a definite pre-acceptance failure or an accepted response may
    /// clear the barrier. Ambiguous outcomes deliberately remain recorded.
    func resolve(username: String, listenedAt: Int, recordingMSID: UUID) {
        records.removeValue(forKey: key(username: username, listenedAt: listenedAt, recordingMSID: recordingMSID))
        if !persist() {
            requiresRecovery = true
        }
    }

    /// Recovery is deliberately explicit because discarding an unreadable
    /// barrier can make an earlier accepted request replayable.
    func resetUnreadableStorage() -> Bool {
        guard requiresRecovery else { return true }
        // A production instance created without an Application Support URL
        // cannot be made crash-safe by resetting it into an in-memory store.
        guard let fileURL else { return false }
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: fileURL.path()) {
                try fileManager.removeItem(at: fileURL)
                try Self.syncDirectory(fileURL.deletingLastPathComponent())
            }
            guard !fileManager.fileExists(atPath: fileURL.path()) else { return false }
        } catch {
            return false
        }
        records.removeAll()
        activeReservations.removeAll()
        requiresRecovery = false
        return true
    }

    private func key(username: String, listenedAt: Int, recordingMSID: UUID) -> String {
        "\(Self.normalized(username)):\(listenedAt):\(recordingMSID.uuidString.lowercased())"
    }

    private func persist() -> Bool {
        guard let data = try? JSONEncoder().encode(records.values.sorted {
            ($0.username, $0.listenedAt, $0.recordingMSID.uuidString) < ($1.username, $1.listenedAt, $1.recordingMSID.uuidString)
        }) else { return false }
        guard let fileURL else { return true }
        do {
            try Self.writeDurably(data, to: fileURL)
            return true
        } catch {
            return false
        }
    }

    private static func load(fileURL: URL?) -> (
        records: [String: ListenDeletionSafetyRecord],
        requiresRecovery: Bool
    ) {
        guard let fileURL else { return ([:], false) }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path()) else { return ([:], false) }
        guard let data = try? Data(contentsOf: fileURL) else { return ([:], true) }
        guard let values = try? JSONDecoder().decode([ListenDeletionSafetyRecord].self, from: data) else {
            return ([:], true)
        }
        let records = values.reduce(into: [:]) { result, value in
            result["\(normalized(value.username)):\(value.listenedAt):\(value.recordingMSID.uuidString.lowercased())"] = value
        }
        return (records, false)
    }

    /// The barrier is synced before its atomic rename becomes visible. The
    /// parent directory is synced as well so ordinary app termination cannot
    /// lose the rename after a delete POST has started.
    private static func writeDurably(_ data: Data, to fileURL: URL) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        let directoryAlreadyExisted = fileManager.fileExists(atPath: directoryURL.path())
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !directoryAlreadyExisted {
            try syncDirectory(directoryURL.deletingLastPathComponent())
        }

        let temporaryURL = directoryURL.appending(
            path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporaryURL)
            #if os(iOS)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: temporaryURL.path()
            )
            #endif
            let handle = try FileHandle(forWritingTo: temporaryURL)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            let renameResult = temporaryURL.path.withCString { source in
                fileURL.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }
            guard renameResult == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            try syncDirectory(directoryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func syncDirectory(_ directoryURL: URL) throws {
        let descriptor = directoryURL.path.withCString { path in
            Darwin.open(path, O_RDONLY)
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
