import CryptoKit
import Darwin
import Foundation
import ListenBrainzKit
import Observation

struct CritiqueBrainzReviewJournalRecord: Codable, Sendable {
    let scopeFingerprint: String
    let payloadFingerprint: String
    let attemptedAt: Date
}

enum CritiqueBrainzReviewReservation: Equatable {
    case reserved
    case inFlight
    case indeterminate
    case unavailable
}

/// A durable, fail-closed barrier for non-idempotent review publishing. The
/// file holds only opaque SHA-256 fingerprints and timestamps.
@MainActor
final class CritiqueBrainzReviewJournal {
    private static let maximumFileBytes = 256 * 1_024
    private static let maximumRecordCount = 512

    static let shared: CritiqueBrainzReviewJournal = {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return .init(storageUnavailable: true)
        }
        return .init(
            fileURL: root
                .appending(path: "Brainz", directoryHint: .isDirectory)
                .appending(path: "critiquebrainz-review-journal-v1.json")
        )
    }()

    private let fileURL: URL?
    private let recordLimit: Int
    private var records: [String: CritiqueBrainzReviewJournalRecord]
    private var claims: Set<String> = []
    private(set) var requiresRecovery: Bool

    /// A nil URL is an in-memory store intended for focused tests. Production
    /// always supplies the Application Support URL above.
    init(fileURL: URL? = nil, recordLimit: Int = 512) {
        self.fileURL = fileURL
        self.recordLimit = max(1, min(recordLimit, Self.maximumRecordCount))
        let loaded = Self.load(fileURL: fileURL, recordLimit: self.recordLimit)
        records = loaded.records
        requiresRecovery = loaded.requiresRecovery
    }

    private init(storageUnavailable: Bool) {
        fileURL = nil
        recordLimit = Self.maximumRecordCount
        records = [:]
        requiresRecovery = storageUnavailable
    }

    static func scopeFingerprint(
        account: Account,
        entity: CritiqueBrainzEntity
    ) -> String {
        digest([
            account.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            entity.kind.rawValue,
            entity.mbid.uuidString.lowercased(),
        ])
    }

    static func payloadFingerprint(_ draft: CritiqueBrainzReviewDraft) -> String {
        let account = draft.account.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return digest([
            account,
            draft.entity.kind.rawValue,
            draft.entity.mbid.uuidString.lowercased(),
            draft.text,
            draft.language,
            draft.rating.map(String.init) ?? "",
        ])
    }

    private static func digest(_ fields: [String]) -> String {
        let material = fields.joined(separator: "\u{1E}")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func reserve(
        scopeFingerprint: String,
        payloadFingerprint: String,
        retryingIndeterminate: Bool
    ) -> CritiqueBrainzReviewReservation {
        guard !requiresRecovery else { return .unavailable }
        guard !claims.contains(scopeFingerprint) else { return .inFlight }
        if let existing = records[scopeFingerprint] {
            guard retryingIndeterminate,
                  existing.payloadFingerprint == payloadFingerprint
            else { return .indeterminate }
            claims.insert(scopeFingerprint)
            return .reserved
        }

        guard records.count < recordLimit else {
            requiresRecovery = true
            return .unavailable
        }
        records[scopeFingerprint] = .init(
            scopeFingerprint: scopeFingerprint,
            payloadFingerprint: payloadFingerprint,
            attemptedAt: .now
        )
        guard persist() else {
            records.removeValue(forKey: scopeFingerprint)
            requiresRecovery = true
            return .unavailable
        }
        claims.insert(scopeFingerprint)
        return .reserved
    }

    func release(scopeFingerprint: String) {
        claims.remove(scopeFingerprint)
    }

    /// Accepted responses and definite failures both clear the replay barrier.
    /// Ambiguous results deliberately leave it on stable storage.
    @discardableResult
    func resolve(scopeFingerprint: String) -> Bool {
        let previous = records.removeValue(forKey: scopeFingerprint)
        guard persist() else {
            if let previous { records[scopeFingerprint] = previous }
            requiresRecovery = true
            return false
        }
        claims.remove(scopeFingerprint)
        return true
    }

    /// Clears only one checked entity. An in-flight claim cannot be cleared by
    /// another composer while its POST outcome is still unresolved.
    func clearAfterReview(scopeFingerprint: String) -> Bool {
        guard !claims.contains(scopeFingerprint) else { return false }
        return resolve(scopeFingerprint: scopeFingerprint)
    }

    func requiresReview(scopeFingerprint: String) -> Bool {
        records[scopeFingerprint] != nil
    }

    /// Recovery is explicit because discarding an unreadable barrier can make
    /// an earlier accepted review replayable.
    func resetRecovery() -> Bool {
        guard requiresRecovery else { return true }
        guard claims.isEmpty else { return false }
        guard let fileURL else { return false }
        do {
            let manager = FileManager.default
            if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
               values.isDirectory == true {
                return false
            }
            if manager.fileExists(atPath: fileURL.path()) {
                try manager.removeItem(at: fileURL)
            }
            let directory = fileURL.deletingLastPathComponent()
            if manager.fileExists(atPath: directory.path()) {
                try Self.syncDirectory(directory)
            }
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
                let values = records.values.sorted {
                    $0.scopeFingerprint < $1.scopeFingerprint
                }
                let data = try JSONEncoder().encode(values)
                guard data.count <= Self.maximumFileBytes else { return false }
                try Self.writeDurably(data, to: fileURL)
            }
            return true
        } catch {
            return false
        }
    }

    private static func load(fileURL: URL?, recordLimit: Int) -> (
        records: [String: CritiqueBrainzReviewJournalRecord],
        requiresRecovery: Bool
    ) {
        guard let fileURL else { return ([:], false) }
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path()) else { return ([:], false) }
        guard
            let attributes = try? manager.attributesOfItem(atPath: fileURL.path()),
            (attributes[.type] as? FileAttributeType) == .typeRegular,
            let fileSize = (attributes[.size] as? NSNumber)?.intValue,
            (1 ... maximumFileBytes).contains(fileSize),
            let data = try? Data(contentsOf: fileURL),
            let values = try? JSONDecoder().decode(
                [CritiqueBrainzReviewJournalRecord].self,
                from: data
            ),
            values.count <= recordLimit
        else { return ([:], true) }

        var loaded: [String: CritiqueBrainzReviewJournalRecord] = [:]
        for value in values {
            guard isValidFingerprint(value.scopeFingerprint),
                  isValidFingerprint(value.payloadFingerprint),
                  value.attemptedAt.timeIntervalSinceReferenceDate.isFinite,
                  loaded[value.scopeFingerprint] == nil
            else { return ([:], true) }
            loaded[value.scopeFingerprint] = value
        }
        return (loaded, false)
    }

    private static func isValidFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
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

        let temporary = directory.appending(
            path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
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
                fileURL.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }
            guard result == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
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
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

@MainActor
@Observable
final class CritiqueBrainzReviewComposerModel {
    struct Failure: Equatable {
        let message: String
        let showsConnectionSettings: Bool
    }

    enum State: Equatable {
        case editing
        case submitting
        case published(UUID)
        case failed(Failure)
        case outcomeUnknown
        case priorAttemptNeedsReview
        case safetyRecovery
    }

    static let supportedLanguageCodes: Set<String> = Set(
        Locale.LanguageCode.isoLanguageCodes
            .map { $0.identifier.lowercased() }
            .filter {
                $0.utf8.count == 2
                    && $0.utf8.allSatisfy { (97 ... 122).contains($0) }
            }
    )

    let account: Account
    let entity: CritiqueBrainzEntity
    let entityName: String
    var text = "" { didSet { resumeEditingAfterDefiniteFailure() } }
    var language: String { didSet { resumeEditingAfterDefiniteFailure() } }
    var rating: Int? { didSet { resumeEditingAfterDefiniteFailure() } }
    var acknowledgedLicense = false { didSet { resumeEditingAfterDefiniteFailure() } }
    private(set) var state: State

    private let provider: any CritiqueBrainzReviewSubmitting
    private let journal: CritiqueBrainzReviewJournal
    private var frozenDraft: CritiqueBrainzReviewDraft?

    init(
        account: Account,
        entity: CritiqueBrainzEntity,
        entityName: String,
        provider: (any CritiqueBrainzReviewSubmitting)? = nil,
        journal: CritiqueBrainzReviewJournal = .shared
    ) {
        self.account = account
        self.entity = entity
        self.entityName = entityName
        self.provider = provider ?? ListenBrainzCritiqueBrainzReviewSubmissionProvider(
            token: account.token
        )
        self.journal = journal

        let deviceLanguage = Locale.current.language.languageCode?.identifier.lowercased()
        language = deviceLanguage.flatMap {
            Self.supportedLanguageCodes.contains($0) ? $0 : nil
        } ?? "en"
        rating = nil
        let scopeFingerprint = Self.scopeFingerprint(account: account, entity: entity)
        if journal.requiresRecovery {
            state = .safetyRecovery
        } else if journal.requiresReview(scopeFingerprint: scopeFingerprint) {
            state = .priorAttemptNeedsReview
        } else {
            state = .editing
        }
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isLocked: Bool {
        switch state {
        case .submitting, .published, .outcomeUnknown, .priorAttemptNeedsReview,
             .safetyRecovery: true
        case .editing, .failed: false
        }
    }

    var canPublish: Bool {
        guard isValid else { return false }
        return switch state {
        case .editing, .failed: true
        case .submitting, .published, .outcomeUnknown, .priorAttemptNeedsReview,
             .safetyRecovery: false
        }
    }

    var showsPublishAction: Bool {
        switch state {
        case .editing, .failed: true
        case .submitting, .published, .outcomeUnknown, .priorAttemptNeedsReview,
             .safetyRecovery: false
        }
    }

    var isValid: Bool {
        let trimmedName = entityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return account.isAuthenticated
            && LBCritiqueBrainzReviewLimits.acceptsUsername(
                account.username.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            && LBCritiqueBrainzReviewLimits.acceptsEntityName(trimmedName)
            && LBCritiqueBrainzReviewLimits.acceptsText(trimmedText)
            && Self.supportedLanguageCodes.contains(language)
            && (rating == nil || (1 ... 5).contains(rating!))
            && acknowledgedLicense
    }

    func publish(retryingIndeterminate: Bool = false) async {
        let payload: CritiqueBrainzReviewDraft
        if retryingIndeterminate {
            guard state == .outcomeUnknown, let frozenDraft else { return }
            payload = frozenDraft
        } else {
            guard canPublish else { return }
            payload = currentDraft
            frozenDraft = payload
        }

        let scopeFingerprint = Self.scopeFingerprint(
            account: payload.account,
            entity: payload.entity
        )
        let payloadFingerprint = CritiqueBrainzReviewJournal.payloadFingerprint(payload)
        switch journal.reserve(
            scopeFingerprint: scopeFingerprint,
            payloadFingerprint: payloadFingerprint,
            retryingIndeterminate: retryingIndeterminate
        ) {
        case .reserved:
            break
        case .inFlight, .indeterminate:
            frozenDraft = nil
            state = .priorAttemptNeedsReview
            return
        case .unavailable:
            frozenDraft = payload
            state = .safetyRecovery
            return
        }

        state = .submitting
        defer { journal.release(scopeFingerprint: scopeFingerprint) }
        do {
            let reviewID = try await provider.submit(payload)
            _ = journal.resolve(scopeFingerprint: scopeFingerprint)
            state = .published(reviewID)
        } catch is CancellationError {
            let didResolve = journal.resolve(scopeFingerprint: scopeFingerprint)
            frozenDraft = nil
            state = didResolve ? .editing : .safetyRecovery
        } catch CritiqueBrainzReviewSubmissionError.outcomeUnknown {
            state = .outcomeUnknown
        } catch {
            let failure = Failure(
                message: error.localizedDescription,
                showsConnectionSettings: (error as? CritiqueBrainzReviewSubmissionError)
                    == .accountOrServiceUnavailable
            )
            let didResolve = journal.resolve(scopeFingerprint: scopeFingerprint)
            frozenDraft = nil
            state = didResolve ? .failed(failure) : .safetyRecovery
        }
    }

    func clearPriorAttemptAfterChecking() {
        guard state == .priorAttemptNeedsReview else { return }
        let didClear = journal.clearAfterReview(
            scopeFingerprint: Self.scopeFingerprint(account: account, entity: entity)
        )
        frozenDraft = nil
        state = didClear ? .editing : .safetyRecovery
    }

    func resetAllSafetyRecordsAfterChecking() {
        guard state == .safetyRecovery, journal.resetRecovery() else { return }
        frozenDraft = nil
        state = .editing
    }

    private var currentDraft: CritiqueBrainzReviewDraft {
        .init(
            account: account,
            entity: entity,
            entityName: entityName.trimmingCharacters(in: .whitespacesAndNewlines),
            text: trimmedText,
            language: language,
            rating: rating
        )
    }

    private func resumeEditingAfterDefiniteFailure() {
        guard case .failed = state else { return }
        frozenDraft = nil
        state = .editing
    }

    private static func scopeFingerprint(
        account: Account,
        entity: CritiqueBrainzEntity
    ) -> String {
        CritiqueBrainzReviewJournal.scopeFingerprint(account: account, entity: entity)
    }
}
