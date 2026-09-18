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
    var feedback: [String: RecordingFeedback] = [:]
    var actionError: String?
    private var didLoad = false
    private var cacheLease: UUID?
    private var selectedDayRequestID: UUID?

    init(
        account: Account,
        provider: (any ListeningProvider)? = nil,
        cache: SnapshotCache = .shared
    ) {
        self.account = account
        self.provider = provider ?? ListenBrainzProvider(token: account.token)
        self.cache = cache
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
        case .loaded:
            return
        case .failed where !retrying:
            return
        case .idle, .loading, .failed:
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
