import Foundation
import Observation

enum RecordingShareFollowersPhase: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct RecordingShareNotice: Identifiable {
    enum Kind: Equatable { case confirmation, error }

    let kind: Kind
    let message: String
    let id = UUID()
}

@MainActor
@Observable
final class RecordingShareModel {
    let account: Account
    let recording: Recording

    private let provider: any RecordingShareProviding
    private let socialCache: UserSocialCache
    private let feedCache: EntityDetailCache<FeedPageKey, FeedPage>

    private(set) var followers: [SearchUser] = []
    private(set) var followersPhase: RecordingShareFollowersPhase = .idle
    private(set) var selectedFollowerIDs: Set<String> = []
    private(set) var isSubmitting = false
    var blurb = ""
    var notice: RecordingShareNotice?

    private var restoredFollowersCache = false
    private var followersAreFresh = false
    private var followersRequestInFlight = false

    init(
        account: Account,
        recording: Recording,
        provider: (any RecordingShareProviding)? = nil,
        socialCache: UserSocialCache = .shared,
        feedCache: EntityDetailCache<FeedPageKey, FeedPage> = FeedCaches.pages
    ) {
        self.account = account
        self.recording = recording
        self.provider = provider ?? ListenBrainzRecordingShareProvider(token: account.token)
        self.socialCache = socialCache
        self.feedCache = feedCache
    }

    var canRecommend: Bool {
        account.isAuthenticated && (recording.identity.mbid != nil || recording.identity.msid != nil)
    }

    var selectedFollowers: [SearchUser] {
        followers.filter { selectedFollowerIDs.contains(Self.normalized($0.username)) }
    }

    var selectedCount: Int { selectedFollowerIDs.count }
    var canSendPersonally: Bool { canRecommend && selectedCount > 0 && blurb.count <= 280 && !isSubmitting }

    func isSelected(_ user: SearchUser) -> Bool {
        selectedFollowerIDs.contains(Self.normalized(user.username))
    }

    func preparePersonalRecommendation() {
        selectedFollowerIDs.removeAll()
        blurb = ""
        notice = nil
    }

    func toggle(_ user: SearchUser) {
        guard !isSubmitting,
              followers.contains(where: { Self.normalized($0.username) == Self.normalized(user.username) })
        else { return }
        let key = Self.normalized(user.username)
        if !selectedFollowerIDs.insert(key).inserted {
            selectedFollowerIDs.remove(key)
        }
        if notice?.kind == .error { notice = nil }
    }

    func loadFollowers() async {
        guard canRecommend else {
            followersPhase = .failed(unavailableReason)
            return
        }
        guard !followersRequestInFlight else { return }

        if !restoredFollowersCache {
            restoredFollowersCache = true
            if let cached = await socialCache.publicValue(for: account.username)?.followers {
                followers = Self.orderedUnique(cached.value)
                followersPhase = .ready
                followersAreFresh = cached.isFresh
            }
        }
        guard !followersAreFresh else { return }
        await fetchFollowers()
    }

    func refreshFollowers() async {
        guard canRecommend, !isSubmitting else { return }
        followersAreFresh = false
        await fetchFollowers()
    }

    @discardableResult
    func recommendToFollowers() async -> Bool {
        guard beginSubmission() else { return false }
        defer { isSubmitting = false }
        do {
            try await provider.recommendToFollowers(username: account.username, recording: recording)
            await feedCache.removeAll()
            notice = RecordingShareNotice(
                kind: .confirmation,
                message: "Recommended to your followers."
            )
            return true
        } catch {
            notice = RecordingShareNotice(kind: .error, message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func recommendPersonally() async -> Bool {
        guard canRecommend else {
            notice = RecordingShareNotice(kind: .error, message: unavailableReason)
            return false
        }
        guard !selectedFollowerIDs.isEmpty else {
            notice = RecordingShareNotice(kind: .error, message: String(localized: "Choose at least one follower."))
            return false
        }
        guard blurb.count <= 280 else {
            notice = RecordingShareNotice(
                kind: .error,
                message: String(localized: "A personal recommendation note can be up to 280 characters.")
            )
            return false
        }
        guard !isSubmitting, beginSubmission() else {
            return false
        }
        defer { isSubmitting = false }
        let recipients = selectedFollowers.map(\.username)
        let note = blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await provider.recommendPersonally(
                username: account.username,
                recording: recording,
                recipients: recipients,
                blurb: note.isEmpty ? nil : note
            )
            await feedCache.removeAll()
            notice = RecordingShareNotice(
                kind: .confirmation,
                message: recipients.count == 1
                    ? "Personal recommendation sent."
                    : "Sent to \(recipients.count) followers."
            )
            return true
        } catch {
            notice = RecordingShareNotice(kind: .error, message: error.localizedDescription)
            return false
        }
    }

    func dismissNotice() { notice = nil }

    private func fetchFollowers() async {
        guard !followersRequestInFlight else { return }
        followersRequestInFlight = true
        let hadFollowers = followersPhase == .ready
        if !hadFollowers { followersPhase = .loading }
        defer { followersRequestInFlight = false }

        do {
            let users = Self.orderedUnique(try await provider.followers(of: account.username))
            followers = users
            selectedFollowerIDs.formIntersection(users.map { Self.normalized($0.username) })
            followersAreFresh = true
            followersPhase = .ready
            await socialCache.saveFollowers(users, for: account.username)
        } catch is CancellationError {
            followersPhase = hadFollowers ? .ready : .idle
        } catch {
            if hadFollowers {
                followersPhase = .ready
                notice = RecordingShareNotice(kind: .error, message: error.localizedDescription)
            } else {
                followersPhase = .failed(error.localizedDescription)
            }
        }
    }

    private func beginSubmission() -> Bool {
        guard canRecommend, !isSubmitting else {
            if !canRecommend {
                notice = RecordingShareNotice(kind: .error, message: unavailableReason)
            }
            return false
        }
        notice = nil
        isSubmitting = true
        return true
    }

    private var unavailableReason: String {
        if !account.isAuthenticated {
            return String(localized: "Sign in with a ListenBrainz token to recommend recordings.")
        }
        return String(localized: "This recording needs a MusicBrainz or MessyBrainz ID before it can be recommended.")
    }

    private static func orderedUnique(_ users: [SearchUser]) -> [SearchUser] {
        var seen: Set<String> = []
        return users
            .filter { seen.insert(normalized($0.username)).inserted }
            .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
