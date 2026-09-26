import Foundation
import Observation

@MainActor
@Observable
final class ManualMappingModel {
    enum Availability: Equatable {
        case available(msid: UUID, currentMBID: UUID?)
        case unavailable(String)
    }

    enum State: Equatable {
        case idle
        case saving
        case saved(UUID)
        case failed(String)
        case outcomeUnknown
    }

    private let availability: Availability
    private let provider: any ManualMappingProviding
    private var inFlightMBID: UUID?
    private(set) var state: State = .idle

    init(account: Account, listen: Listen, provider: (any ManualMappingProviding)? = nil) {
        availability = Self.availability(account: account, listen: listen)
        self.provider = provider ?? ManualMappingProvider(token: account.token)
    }

    static func availability(account: Account, listen: Listen) -> Availability {
        guard account.isAuthenticated else { return .unavailable(String(localized: "Sign in to save a MusicBrainz match.")) }
        guard !listen.isPlayingNow else { return .unavailable(String(localized: "Wait until this track appears in your history before matching it.")) }
        guard let details = listen.inspection, let msid = details.recordingMSID else {
            return .unavailable(String(localized: "ListenBrainz hasn’t assigned this listen a recording MSID yet."))
        }
        guard details.submittedRecordingMBID == nil else {
            return .unavailable(String(localized: "This listen already includes a submitted recording MBID, so its submitted match takes precedence."))
        }
        return .available(msid: msid, currentMBID: details.resolvedRecordingMBID)
    }

    var isEligible: Bool { if case .available = availability { true } else { false } }
    var unavailableReason: String? { if case let .unavailable(reason) = availability { reason } else { nil } }
    var savedMBID: UUID? { if case let .saved(mbid) = state { mbid } else { nil } }
    var currentMBID: UUID? { if case let .available(_, mbid) = availability { mbid } else { nil } }
    var isSaving: Bool { state == .saving }

    func resetForNewSelection() {
        guard !isSaving, savedMBID == nil else { return }
        // Preserve an indeterminate write across navigation and candidate
        // changes. Any later POST for this MSID must remain an explicitly
        // confirmed resend because the first upsert may have committed.
        if case .failed = state {
            state = .idle
        }
    }

    func save(mbid: UUID, sendAgainAfterUnknown: Bool = false) async {
        guard case let .available(msid, currentMBID) = availability else { return }
        guard currentMBID != mbid else {
            state = .failed(String(localized: "This is already the current MusicBrainz match, so nothing was sent."))
            return
        }
        guard inFlightMBID == nil else { return }
        guard state != .outcomeUnknown || sendAgainAfterUnknown else { return }
        inFlightMBID = mbid
        state = .saving
        defer { inFlightMBID = nil }
        do {
            try await provider.submit(msid: msid, mbid: mbid)
            state = .saved(mbid)
        } catch is CancellationError {
            state = .idle
        } catch ProviderError.manualMappingOutcomeUnknown {
            state = .outcomeUnknown
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
@Observable
final class ManualMappingStatusModel {
    enum Availability: Equatable {
        case available(msid: UUID)
        case unavailable
    }

    enum State: Equatable {
        case idle
        case checking
        case found(UUID)
        case notFound
        case failed(String)
    }

    private let availability: Availability
    private let provider: (any ManualMappingStatusProviding)?
    private var checkRevision = 0
    private(set) var state: State = .idle

    init(
        account: Account?,
        listen: Listen,
        provider: (any ManualMappingStatusProviding)? = nil
    ) {
        availability = Self.availability(account: account, listen: listen)
        if let provider {
            self.provider = provider
        } else if let account, account.isAuthenticated {
            self.provider = ManualMappingStatusProvider(token: account.token)
        } else {
            self.provider = nil
        }
    }

    static func availability(account: Account?, listen: Listen) -> Availability {
        guard let account, account.isAuthenticated else { return .unavailable }
        guard !listen.isPlayingNow else { return .unavailable }
        guard let details = listen.inspection,
              let msid = details.recordingMSID
        else { return .unavailable }
        return .available(msid: msid)
    }

    var isEligible: Bool {
        if case .available = availability { true } else { false }
    }

    var isChecking: Bool { state == .checking }

    static func shouldSuggestHistoryRefresh(
        details: ListenInspection,
        savedMBID: UUID
    ) -> Bool {
        details.submittedRecordingMBID == nil
            && details.resolvedRecordingMBID != savedMBID
    }

    func check() async {
        guard case let .available(msid) = availability,
              let provider,
              canStartCheck
        else { return }

        checkRevision &+= 1
        let revision = checkRevision
        state = .checking
        do {
            if let mapping = try await provider.savedMapping(msid: msid) {
                guard revision == checkRevision else { return }
                guard mapping.msid == msid else {
                    state = .failed(ProviderError.manualMappingCheckUnavailable.localizedDescription)
                    return
                }
                state = .found(mapping.mbid)
            } else {
                guard revision == checkRevision else { return }
                state = .notFound
            }
        } catch is CancellationError {
            guard revision == checkRevision else { return }
            state = .idle
        } catch {
            guard revision == checkRevision else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func confirmSaved(mbid: UUID) {
        guard isEligible else { return }
        checkRevision &+= 1
        state = .found(mbid)
    }

    private var canStartCheck: Bool {
        switch state {
        case .idle, .failed: true
        case .checking, .found, .notFound: false
        }
    }
}
