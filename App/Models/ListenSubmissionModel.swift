import CryptoKit
import Darwin
import Foundation
import Observation

enum ListenSubmissionPhase: Equatable, Sendable {
    case editing
    case submitting
    case sent
    case failed(String)
    case indeterminate
}

@MainActor
@Observable
final class ListenSubmissionModel {
    let account: Account
    var draft: ListenSubmissionDraft
    @ObservationIgnored private let provider: any ListenSubmitting
    @ObservationIgnored private let journal: ListenSubmissionJournal
    @ObservationIgnored private let playingNowClaims: PlayingNowSubmissionClaims
    @ObservationIgnored private let now: () -> Date
    private(set) var phase: ListenSubmissionPhase = .editing
    private(set) var requiresSafetyRecovery: Bool
    private var frozenPayload: ListenSubmissionPayload?

    init(
        account: Account,
        recording: Recording? = nil,
        mode: ListenSubmissionMode = .listen,
        provider: (any ListenSubmitting)? = nil,
        journal: ListenSubmissionJournal = .shared,
        playingNowClaims: PlayingNowSubmissionClaims = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.account = account
        draft = .init(recording: recording, mode: mode)
        self.provider = provider ?? ListenBrainzSubmissionProvider(token: account.token)
        self.journal = journal
        self.playingNowClaims = playingNowClaims
        self.now = now
        requiresSafetyRecovery = journal.requiresRecovery
    }

    var isSubmitting: Bool { phase == .submitting }

    var isFormLocked: Bool {
        switch phase {
        case .submitting, .sent, .indeterminate: true
        case .editing, .failed: requiresSafetyRecovery
        }
    }

    var canSend: Bool {
        guard account.isAuthenticated, !requiresSafetyRecovery else { return false }
        return switch phase {
        case .editing, .failed: true
        case .submitting, .sent, .indeterminate: false
        }
    }

    func textDidChange() {
        draft.clampTextAndInvalidateIdentity()
        resumeEditingAfterDefiniteFailure()
    }

    func modeDidChange() {
        resumeEditingAfterDefiniteFailure()
    }

    func send(retryIndeterminate: Bool = false) async {
        guard account.isAuthenticated else { return }
        if retryIndeterminate {
            guard phase == .indeterminate else { return }
        } else {
            guard canSend else { return }
        }

        let payload: ListenSubmissionPayload
        do {
            payload = retryIndeterminate
                ? try replayPayload()
                : try draft.payload(appVersion: ListenBrainzSubmissionProvider.appVersion, now: now())
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        if !retryIndeterminate { frozenPayload = payload }
        phase = .submitting

        if payload.mode == .listen {
            await sendListen(payload, retryIndeterminate: retryIndeterminate)
        } else {
            await sendPlayingNow(payload)
        }
    }

    func resetSafetyRecord() {
        guard requiresSafetyRecovery else { return }
        if journal.resetRecovery() {
            requiresSafetyRecovery = false
            frozenPayload = nil
            phase = .editing
        } else {
            phase = .failed(String(localized: "Brainz couldn’t reset its safety record. Manual listens remain paused."))
        }
    }

    private func sendListen(_ payload: ListenSubmissionPayload, retryIndeterminate: Bool) async {
        let fingerprint = ListenSubmissionJournal.fingerprint(account: account.username, payload: payload)
        switch journal.reserve(fingerprint: fingerprint, retryingIndeterminate: retryIndeterminate) {
        case .reserved:
            break
        case .inFlight:
            // Another scene may receive a confirmed response after this one
            // stops waiting. Treat the outcome as ambiguous so a second tap
            // always carries the same explicit duplicate warning as a lost
            // response.
            phase = .indeterminate
            return
        case .indeterminate:
            phase = .indeterminate
            return
        case .unavailable:
            requiresSafetyRecovery = true
            phase = .failed(Self.safetyUnavailableMessage)
            return
        }

        do {
            try await provider.submit(payload)
            _ = journal.resolve(fingerprint: fingerprint)
            journal.release(fingerprint: fingerprint)
            requiresSafetyRecovery = journal.requiresRecovery
            phase = .sent
        } catch is CancellationError {
            resolveDefiniteOutcome(fingerprint: fingerprint, fallbackPhase: .editing)
        } catch let error as ListenSubmissionError {
            if error == .indeterminate {
                journal.release(fingerprint: fingerprint)
                phase = .indeterminate
            } else {
                resolveDefiniteOutcome(fingerprint: fingerprint, fallbackPhase: .failed(error.localizedDescription))
            }
        } catch {
            journal.release(fingerprint: fingerprint)
            phase = .indeterminate
        }
    }

    private func sendPlayingNow(_ payload: ListenSubmissionPayload) async {
        let fingerprint = ListenSubmissionJournal.fingerprint(account: account.username, payload: payload)
        guard await playingNowClaims.claim(fingerprint: fingerprint) else {
            phase = .failed(String(localized: "This Playing Now update was just sent."))
            return
        }
        do {
            try await provider.submit(payload)
            await playingNowClaims.finish(fingerprint: fingerprint, markRecent: true)
            phase = .sent
        } catch is CancellationError {
            await playingNowClaims.finish(fingerprint: fingerprint, markRecent: false)
            phase = .editing
        } catch let error as ListenSubmissionError {
            let isIndeterminate = error == .indeterminate
            await playingNowClaims.finish(fingerprint: fingerprint, markRecent: isIndeterminate)
            phase = isIndeterminate ? .indeterminate : .failed(error.localizedDescription)
        } catch {
            await playingNowClaims.finish(fingerprint: fingerprint, markRecent: true)
            phase = .indeterminate
        }
    }

    private func resolveDefiniteOutcome(fingerprint: String, fallbackPhase: ListenSubmissionPhase) {
        let didResolve = journal.resolve(fingerprint: fingerprint)
        journal.release(fingerprint: fingerprint)
        requiresSafetyRecovery = journal.requiresRecovery
        phase = didResolve ? fallbackPhase : .failed(Self.safetyUnavailableMessage)
    }

    private func replayPayload() throws -> ListenSubmissionPayload {
        guard let frozenPayload, frozenPayload.mode == .listen else {
            throw ListenSubmissionValidationError.replayUnavailable
        }
        return frozenPayload
    }

    private func resumeEditingAfterDefiniteFailure() {
        guard case .failed = phase, !requiresSafetyRecovery else { return }
        frozenPayload = nil
        phase = .editing
    }

    private static let safetyUnavailableMessage = String(
        localized: "Brainz couldn’t safely check for a duplicate. Manual listens are paused."
    )

    #if DEBUG
        func installFixturePhase(_ value: ListenSubmissionPhase) { phase = value }
        func installFixtureSafetyRecovery() { requiresSafetyRecovery = true }
    #endif
}

enum ListenSubmissionReservation: Equatable {
    case reserved
    case inFlight
    case indeterminate
    case unavailable
}

struct ListenSubmissionJournalRecord: Codable, Sendable {
    let fingerprint: String
    let attemptedAt: Date
}

/// Token-free replay barrier. It intentionally persists only an opaque digest
/// and attempt time—never a credential or submitted music metadata.
@MainActor
final class ListenSubmissionJournal {
    static let shared: ListenSubmissionJournal = {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return .init(storageUnavailable: true)
        }
        return .init(
            fileURL: root
                .appending(path: "Brainz", directoryHint: .isDirectory)
                .appending(path: "listen-submission-journal-v1.json")
        )
    }()

    private let fileURL: URL?
    private var records: [String: ListenSubmissionJournalRecord]
    private var claims: Set<String> = []
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

    static func fingerprint(account: String, payload: ListenSubmissionPayload) -> String {
        let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let input = "\(normalizedAccount)\u{1E}\(payload.fingerprint)"
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func reserve(fingerprint: String, retryingIndeterminate: Bool) -> ListenSubmissionReservation {
        guard !requiresRecovery else { return .unavailable }
        guard !claims.contains(fingerprint) else { return .inFlight }
        if records[fingerprint] != nil {
            guard retryingIndeterminate else { return .indeterminate }
            claims.insert(fingerprint)
            return .reserved
        }

        records[fingerprint] = .init(fingerprint: fingerprint, attemptedAt: .now)
        guard persist() else {
            records.removeValue(forKey: fingerprint)
            requiresRecovery = true
            return .unavailable
        }
        claims.insert(fingerprint)
        return .reserved
    }

    func release(fingerprint: String) {
        claims.remove(fingerprint)
    }

    /// Accepted responses and definite failures both clear the replay barrier.
    /// Ambiguous results deliberately leave it on stable storage.
    @discardableResult
    func resolve(fingerprint: String) -> Bool {
        let previous = records.removeValue(forKey: fingerprint)
        guard persist() else {
            if let previous { records[fingerprint] = previous }
            requiresRecovery = true
            return false
        }
        return true
    }

    /// Recovery is explicit because discarding an unreadable barrier can make
    /// an earlier accepted request replayable.
    func resetRecovery() -> Bool {
        guard requiresRecovery else { return true }
        guard let fileURL else { return false }
        do {
            let manager = FileManager.default
            if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
                return false
            }
            if manager.fileExists(atPath: fileURL.path()) {
                try manager.removeItem(at: fileURL)
            }
            let directory = fileURL.deletingLastPathComponent()
            if manager.fileExists(atPath: directory.path()) { try Self.syncDirectory(directory) }
            guard !manager.fileExists(atPath: fileURL.path()) else { return false }
            records.removeAll()
            claims.removeAll()
            requiresRecovery = false
            return true
        } catch {
            return false
        }
    }

    private func persist() -> Bool {
        guard let fileURL else { return true }
        do {
            if records.isEmpty {
                let manager = FileManager.default
                if manager.fileExists(atPath: fileURL.path()) {
                    try manager.removeItem(at: fileURL)
                    try Self.syncDirectory(fileURL.deletingLastPathComponent())
                }
            } else {
                let values = records.values.sorted { $0.fingerprint < $1.fingerprint }
                try Self.writeDurably(JSONEncoder().encode(values), to: fileURL)
            }
            return true
        } catch {
            return false
        }
    }

    private static func load(fileURL: URL?) -> (
        records: [String: ListenSubmissionJournalRecord],
        requiresRecovery: Bool
    ) {
        guard let fileURL else { return ([:], false) }
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path()) else { return ([:], false) }
        guard
            let data = try? Data(contentsOf: fileURL),
            let values = try? JSONDecoder().decode([ListenSubmissionJournalRecord].self, from: data)
        else { return ([:], true) }

        var loaded: [String: ListenSubmissionJournalRecord] = [:]
        for value in values {
            guard isValidFingerprint(value.fingerprint), loaded[value.fingerprint] == nil else {
                return ([:], true)
            }
            loaded[value.fingerprint] = value
        }
        return (loaded, false)
    }

    private static func isValidFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    /// The barrier is synced before its atomic rename becomes visible. The
    /// directory is synced as well so ordinary app termination cannot lose
    /// the rename after a POST has started.
    private static func writeDurably(_ data: Data, to fileURL: URL) throws {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let directoryAlreadyExisted = manager.fileExists(atPath: directory.path())
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !directoryAlreadyExisted {
            try syncDirectory(directory.deletingLastPathComponent())
        }

        let temporary = directory.appending(path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            #if os(iOS)
                try manager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: temporary.path()
                )
            #endif
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            let result = temporary.path.withCString { source in
                fileURL.path.withCString { destination in Darwin.rename(source, destination) }
            }
            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            #if os(iOS)
                try manager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: fileURL.path()
                )
            #endif
            try syncDirectory(directory)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    private static func syncDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString { Darwin.open($0, O_RDONLY) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

actor PlayingNowSubmissionClaims {
    static let shared = PlayingNowSubmissionClaims()
    private var active: Set<String> = []
    private var recent: [String: Date] = [:]

    func claim(fingerprint: String, now: Date = .now) -> Bool {
        recent = recent.filter { now.timeIntervalSince($0.value) < 15 }
        guard !active.contains(fingerprint), recent[fingerprint] == nil else { return false }
        active.insert(fingerprint)
        return true
    }

    func finish(fingerprint: String, markRecent: Bool, now: Date = .now) {
        active.remove(fingerprint)
        if markRecent { recent[fingerprint] = now }
    }
}
