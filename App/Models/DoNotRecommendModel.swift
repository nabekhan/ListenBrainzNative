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

    /// `nil` means this screen has not changed the preference in this session.
    private(set) var isExcluded: Bool?
    private(set) var isSubmitting = false
    var notice: DoNotRecommendNotice?

    init(
        account: Account,
        recordingMBID: UUID?,
        provider: (any DoNotRecommendProviding)? = nil
    ) {
        self.account = account
        self.recordingMBID = recordingMBID
        self.provider = provider ?? ListenBrainzDoNotRecommendProvider(token: account.token)
    }

    var canChangePreference: Bool { account.isAuthenticated && recordingMBID != nil }

    @discardableResult
    func savePreference() async -> Bool {
        await changePreference(excluded: true)
    }

    @discardableResult
    func removePreference() async -> Bool {
        await changePreference(excluded: false)
    }

    func dismissNotice() { notice = nil }

    private func changePreference(excluded: Bool) async -> Bool {
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

        do {
            if excluded {
                try await provider.addRecording(recordingMBID: recordingMBID)
                notice = .init(kind: .confirmation, message: String(localized: "Preference saved to ListenBrainz."))
            } else {
                try await provider.removeRecording(recordingMBID: recordingMBID)
                notice = .init(kind: .confirmation, message: String(localized: "Saved preference removed."))
            }
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
                message: DoNotRecommendProviderError.unavailable.localizedDescription
            )
            return false
        }
    }

    private var unavailableReason: String {
        if !account.isAuthenticated {
            return String(localized: "Sign in with a ListenBrainz token to change saved preferences.")
        }
        return String(localized: "This track needs a MusicBrainz ID before you can save this preference.")
    }
}
