import Foundation
import Observation

struct DoNotRecommendNotice: Identifiable {
    enum Kind: Equatable { case confirmation, error }

    let kind: Kind
    let message: String
    let id = UUID()
}

/// Screen-local optimistic state. No status request is made merely to render a
/// recording: the server offers only a paginated list, not entity lookup.
@MainActor
@Observable
final class DoNotRecommendModel {
    let account: Account
    let recordingMBID: UUID?

    private let provider: any DoNotRecommendProviding
    private let preferenceCache: EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage>
    private let changes: RecommendationPreferenceChanges
    private let changeSourceID = UUID()

    /// `nil` means this screen has not changed the preference in this session.
    private(set) var isExcluded: Bool?
    private(set) var isSubmitting = false
    var notice: DoNotRecommendNotice?

    init(
        account: Account,
        recordingMBID: UUID?,
        provider: (any DoNotRecommendProviding)? = nil,
        preferenceCache: EntityDetailCache<RecommendationPreferencesPageKey, RecommendationPreferencePage> = RecommendationPreferencesCaches.pages,
        changes: RecommendationPreferenceChanges = .shared
    ) {
        self.account = account
        self.recordingMBID = recordingMBID
        self.provider = provider ?? ListenBrainzDoNotRecommendProvider(token: account.token)
        self.preferenceCache = preferenceCache
        self.changes = changes
    }

    var canChangePreference: Bool { account.isAuthenticated && recordingMBID != nil }

    @discardableResult
    func savePreference(duration: RecommendationPreferenceDuration = .permanent, now: Date = .now) async -> Bool {
        await changePreference(excluded: true, until: duration.expiration(from: now))
    }

    @discardableResult
    func removePreference() async -> Bool {
        await changePreference(excluded: false, until: nil)
    }

    func dismissNotice() { notice = nil }

    private func changePreference(excluded: Bool, until: Date?) async -> Bool {
        guard let recordingMBID else {
            notice = .init(kind: .error, message: unavailableReason)
            return false
        }
        guard account.isAuthenticated else {
            notice = .init(kind: .error, message: unavailableReason)
            return false
        }
        guard !isSubmitting else { return false }

        let previous = isExcluded
        isSubmitting = true
        isExcluded = excluded
        notice = nil
        defer { isSubmitting = false }

        // Invalidate and notify before dispatch because a cancelled or failed
        // response cannot prove whether the server applied the mutation.
        // A second invalidation after success protects against reads begun
        // while the mutation was in flight.
        await preferenceCache.removeAll()
        changes.recordChange(for: account.username, sourceID: changeSourceID)
        do {
            if excluded {
                try await provider.add(entity: .recording, entityMBID: recordingMBID, until: until)
                notice = .init(kind: .confirmation, message: String(localized: "Preference saved to ListenBrainz."))
            } else {
                try await provider.removeRecording(recordingMBID: recordingMBID)
                notice = .init(kind: .confirmation, message: String(localized: "Saved preference removed."))
            }
            await preferenceCache.removeAll()
            changes.recordChange(for: account.username, sourceID: changeSourceID)
            return true
        } catch is CancellationError {
            isExcluded = previous
            return false
        } catch let error as DoNotRecommendProviderError {
            isExcluded = previous
            notice = .init(kind: .error, message: error.localizedDescription)
            return false
        } catch let error as ProviderError {
            isExcluded = previous
            notice = .init(kind: .error, message: error.localizedDescription)
            return false
        } catch {
            isExcluded = previous
            notice = .init(
                kind: .error,
                message: DoNotRecommendProviderError.mutationUnavailable.localizedDescription
            )
            return false
        }
    }

    private var unavailableReason: String {
        if !account.isAuthenticated {
            return String(localized: "Sign in with a ListenBrainz token to change saved preferences.")
        }
        return String(localized: "This recording needs a MusicBrainz ID before you can save this preference.")
    }
}
