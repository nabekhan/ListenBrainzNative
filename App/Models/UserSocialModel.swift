import Foundation
import Observation

@MainActor
@Observable
final class UserSocialModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let target: SearchUser
    let viewer: Account
    private let provider: any SocialProviding
    private let cache: UserSocialCache
    private let viewerScope: RequestGate.ReadScope

    private(set) var followers: [SearchUser] = []
    private(set) var following: [SearchUser] = []
    private(set) var similarUsers: [SimilarListener] = []
    private(set) var compatibility: Double?
    private(set) var isFollowing: Bool?
    private(set) var followersPhase: Phase = .idle
    private(set) var followingPhase: Phase = .idle
    private(set) var similarUsersPhase: Phase = .idle
    private(set) var compatibilityPhase: Phase = .idle
    private(set) var isMutating = false
    private(set) var actionError: String?

    private var didLoad = false
    private var followersAreFresh = false
    private var followingAreFresh = false
    private var similarUsersAreFresh = false
    private var compatibilityIsFresh = false
    private var relationshipIsFresh = false
    private var followersRequestInFlight = false
    private var followingRequestInFlight = false
    private var similarUsersRequestInFlight = false
    private var compatibilityRequestInFlight = false
    private var followersRequestID = UUID()

    init(
        target: SearchUser,
        viewer: Account,
        provider: (any SocialProviding)? = nil,
        cache: UserSocialCache = .shared
    ) {
        self.target = target
        self.viewer = viewer
        self.provider = provider ?? ListenBrainzSocialProvider(token: viewer.token)
        self.cache = cache
        self.viewerScope = .authenticated(token: viewer.token)
    }

    var isSelf: Bool {
        Self.normalized(viewer.username) == Self.normalized(target.username)
    }

    var canFollow: Bool { viewer.isAuthenticated && !isSelf }

    var normalizedCompatibility: Double? {
        compatibility.map { min(max($0, 0), 1) }
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        await restoreCache()

        if !followersAreFresh { await loadFollowers() }
        if !followingAreFresh { await loadFollowing() }
        if !similarUsersAreFresh { await loadSimilarUsers() }
        if canFollow, !compatibilityIsFresh { await loadCompatibility() }
    }

    func refresh() async {
        guard !isMutating else { return }
        await loadFollowers(force: true)
        await loadFollowing(force: true)
        await loadSimilarUsers(force: true)
        if canFollow { await loadCompatibility(force: true) }
    }

    func retryFollowers() async { await loadFollowers(force: true) }
    func retryFollowing() async { await loadFollowing(force: true) }
    func retrySimilarUsers() async { await loadSimilarUsers(force: true) }
    func retryCompatibility() async { await loadCompatibility(force: true) }

    func toggleFollow() async {
        guard canFollow,
              !isMutating,
              !followersRequestInFlight,
              let previousState = isFollowing
        else { return }

        isMutating = true
        followersRequestID = UUID()
        let previousFollowers = followers
        let newState = !previousState
        isFollowing = newState
        if followersPhase == .ready {
            if newState {
                if !followers.contains(where: { Self.normalized($0.username) == Self.normalized(viewer.username) }) {
                    followers.append(SearchUser(username: viewer.username))
                    followers.sort { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
                }
            } else {
                followers.removeAll { Self.normalized($0.username) == Self.normalized(viewer.username) }
            }
        }

        do {
            if newState {
                try await provider.follow(username: target.username)
            } else {
                try await provider.unfollow(username: target.username)
            }
            relationshipIsFresh = true
            await cache.saveIsFollowing(
                newState,
                viewer: viewer.username,
                scope: viewerScope,
                target: target.username
            )
            if followersPhase == .ready {
                await cache.saveFollowers(followers, for: target.username)
            }
        } catch is CancellationError {
            isFollowing = previousState
            followers = previousFollowers
        } catch {
            isFollowing = previousState
            followers = previousFollowers
            actionError = error.localizedDescription
        }
        isMutating = false
    }

    func dismissActionError() { actionError = nil }

    private func restoreCache() async {
        if let value = await cache.publicValue(for: target.username) {
            if let cached = value.followers {
                followers = cached.value
                followersPhase = .ready
                followersAreFresh = cached.isFresh
            }
            if let cached = value.following {
                following = cached.value
                followingPhase = .ready
                followingAreFresh = cached.isFresh
            }
            if let cached = value.similarUsers {
                similarUsers = cached.value
                similarUsersPhase = .ready
                similarUsersAreFresh = cached.isFresh
            }
        }

        if canFollow,
           let value = await cache.viewerValue(
               viewer: viewer.username,
               scope: viewerScope,
               target: target.username
           ) {
            if let cached = value.isFollowing {
                isFollowing = cached.value
                relationshipIsFresh = cached.isFresh
            }
            if let cached = value.compatibility {
                compatibility = cached.value
                compatibilityPhase = .ready
                compatibilityIsFresh = cached.isFresh
            }
        }

        if canFollow, !relationshipIsFresh, followersPhase == .ready {
            updateRelationship(from: followers)
            relationshipIsFresh = followersAreFresh
            if followersAreFresh {
                await cache.saveIsFollowing(
                    isFollowing ?? false,
                    viewer: viewer.username,
                    scope: viewerScope,
                    target: target.username
                )
            }
        }
    }

    private func loadFollowers(force: Bool = false) async {
        guard !followersRequestInFlight, force || !followersAreFresh else { return }
        followersRequestInFlight = true
        let hadValue = followersPhase == .ready
        if !hadValue { followersPhase = .loading }
        let requestID = UUID()
        followersRequestID = requestID
        defer { followersRequestInFlight = false }

        do {
            let users = try await provider.followers(of: target.username)
            guard followersRequestID == requestID else { return }
            followers = users
            followersAreFresh = true
            followersPhase = .ready
            await cache.saveFollowers(users, for: target.username)
            if canFollow {
                updateRelationship(from: users)
                relationshipIsFresh = true
                await cache.saveIsFollowing(
                    isFollowing ?? false,
                    viewer: viewer.username,
                    scope: viewerScope,
                    target: target.username
                )
            }
        } catch is CancellationError {
            guard followersRequestID == requestID else { return }
            followersPhase = hadValue ? .ready : .idle
        } catch {
            guard followersRequestID == requestID else { return }
            followersPhase = hadValue ? .ready : .failed(error.localizedDescription)
        }
    }

    private func loadFollowing(force: Bool = false) async {
        guard !followingRequestInFlight, force || !followingAreFresh else { return }
        followingRequestInFlight = true
        let hadValue = followingPhase == .ready
        if !hadValue { followingPhase = .loading }
        defer { followingRequestInFlight = false }

        do {
            let users = try await provider.following(of: target.username)
            following = users
            followingAreFresh = true
            followingPhase = .ready
            await cache.saveFollowing(users, for: target.username)
        } catch is CancellationError {
            followingPhase = hadValue ? .ready : .idle
        } catch {
            followingPhase = hadValue ? .ready : .failed(error.localizedDescription)
        }
    }

    private func loadSimilarUsers(force: Bool = false) async {
        guard !similarUsersRequestInFlight, force || !similarUsersAreFresh else { return }
        similarUsersRequestInFlight = true
        let hadValue = similarUsersPhase == .ready
        if !hadValue { similarUsersPhase = .loading }
        defer { similarUsersRequestInFlight = false }

        do {
            let users = try await provider.similarUsers(to: target.username)
            similarUsers = users
            similarUsersAreFresh = true
            similarUsersPhase = .ready
            await cache.saveSimilarUsers(users, for: target.username)
        } catch is CancellationError {
            similarUsersPhase = hadValue ? .ready : .idle
        } catch {
            similarUsersPhase = hadValue ? .ready : .failed(error.localizedDescription)
        }
    }

    private func loadCompatibility(force: Bool = false) async {
        guard canFollow,
              !compatibilityRequestInFlight,
              force || !compatibilityIsFresh
        else { return }
        compatibilityRequestInFlight = true
        let hadValue = compatibilityPhase == .ready
        if !hadValue { compatibilityPhase = .loading }
        defer { compatibilityRequestInFlight = false }

        do {
            let value = try await provider.compatibility(
                between: viewer.username,
                and: target.username
            )
            compatibility = value
            compatibilityIsFresh = true
            compatibilityPhase = .ready
            await cache.saveCompatibility(
                value,
                viewer: viewer.username,
                scope: viewerScope,
                target: target.username
            )
        } catch is CancellationError {
            compatibilityPhase = hadValue ? .ready : .idle
        } catch {
            compatibilityPhase = hadValue ? .ready : .failed(error.localizedDescription)
        }
    }

    private func updateRelationship(from followers: [SearchUser]) {
        let viewerName = Self.normalized(viewer.username)
        isFollowing = followers.contains { Self.normalized($0.username) == viewerName }
    }

    private static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
