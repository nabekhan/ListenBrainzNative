import Foundation
import ListenBrainzKit

protocol CritiqueBrainzReviewSubmitting: Sendable {
    func submit(_ payload: CritiqueBrainzReviewDraft) async throws -> UUID
}

struct CritiqueBrainzReviewDraft: Hashable, Sendable {
    let account: Account
    let entity: CritiqueBrainzEntity
    let entityName: String
    let text: String
    let language: String
    let rating: Int?
}

enum CritiqueBrainzReviewSubmissionError: LocalizedError, Sendable, Equatable {
    case accountOrServiceUnavailable
    case duplicateOrRejected
    case rateLimited(Int)
    case outcomeUnknown

    var errorDescription: String? {
        switch self {
        case .accountOrServiceUnavailable:
            String(localized: "Sign in again or connect CritiqueBrainz in ListenBrainz settings before publishing a review.")
        case .duplicateOrRejected:
            String(localized: "CritiqueBrainz couldn’t publish this review. You may already have a review for this item.")
        case let .rateLimited(seconds):
            String(localized: "ListenBrainz is busy. Try again in about \(seconds) seconds.")
        case .outcomeUnknown:
            String(localized: "We couldn’t confirm whether your review was published. Check CritiqueBrainz before sending the same review again.")
        }
    }
}

private struct LiveCritiqueBrainzReviewSubmissionTransport: Sendable {
    let client: LBClient
    func submit(_ draft: CritiqueBrainzReviewDraft) async throws -> UUID {
        let event = try await client.feed.createCritiqueBrainzReview(
            username: draft.account.username,
            entityName: draft.entityName,
            entityID: draft.entity.mbid,
            entityType: draft.entity.kind.rawValue,
            text: draft.text,
            language: draft.language,
            rating: draft.rating
        )
        guard event.eventType == "critiquebrainz_review",
              let rawID = event.metadata.reviewID ?? event.metadata.reviewMBID,
              let reviewID = UUID(uuidString: rawID)
        else { throw LBError.invalidResponse }
        return reviewID
    }
}

/// A single POST boundary. Known HTTP rejections are definite, while transport
/// loss, malformed success, and cancellation after dispatch are indeterminate:
/// the upstream review can exist even if its LB timeline write or response fails.
struct ListenBrainzCritiqueBrainzReviewSubmissionProvider: CritiqueBrainzReviewSubmitting {
    private let transport: @Sendable (CritiqueBrainzReviewDraft) async throws -> UUID
    private let gate: RequestGate

    init(token: String, gate: RequestGate = .shared) {
        let live = LiveCritiqueBrainzReviewSubmissionTransport(client: LBClient(token: token, userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"))
        transport = live.submit
        self.gate = gate
    }

    init(gate: RequestGate, transport: @escaping @Sendable (CritiqueBrainzReviewDraft) async throws -> UUID) {
        self.gate = gate; self.transport = transport
    }

    func submit(_ payload: CritiqueBrainzReviewDraft) async throws -> UUID {
        let attempt = SubmissionAttempt()
        do {
            return try await gate.perform {
                await attempt.started()
                return try await transport(payload)
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(1, resetIn))
            }
        } catch let LBError.rateLimited(seconds) {
            throw CritiqueBrainzReviewSubmissionError.rateLimited(max(1, seconds))
        } catch LBError.invalidAuth, LBError.noToken, LBError.forbidden {
            throw CritiqueBrainzReviewSubmissionError.accountOrServiceUnavailable
        } catch LBError.invalidJSON, LBError.badRequest, LBError.invalidParam, LBError.notFound {
            throw CritiqueBrainzReviewSubmissionError.duplicateOrRejected
        } catch is CancellationError {
            if await attempt.didStart { throw CritiqueBrainzReviewSubmissionError.outcomeUnknown }
            throw CancellationError()
        } catch {
            throw CritiqueBrainzReviewSubmissionError.outcomeUnknown
        }
    }

    private actor SubmissionAttempt {
        private(set) var didStart = false
        func started() { didStart = true }
    }
}
