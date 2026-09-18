import Foundation

enum FeedMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case activity
    case following
    case similar

    var id: Self { self }

    var title: String {
        switch self {
        case .activity: "My Feed"
        case .following: "Following"
        case .similar: "Similar"
        }
    }
}

enum FeedEventKind: Hashable, Sendable {
    case listen
    case recordingRecommendation
    case recordingPin
    case personalRecordingRecommendation
    case follow
    case notification
    case critiquebrainzReview
    case thanks
    case unknown(String)

    init(eventType: String) {
        switch eventType.lowercased() {
        case "listen": self = .listen
        case "recording_recommendation": self = .recordingRecommendation
        case "recording_pin": self = .recordingPin
        case "personal_recording_recommendation": self = .personalRecordingRecommendation
        case "follow": self = .follow
        case "notification": self = .notification
        case "critiquebrainz_review": self = .critiquebrainzReview
        case "thanks": self = .thanks
        default: self = .unknown(eventType)
        }
    }

    var rawValue: String {
        switch self {
        case .listen: "listen"
        case .recordingRecommendation: "recording_recommendation"
        case .recordingPin: "recording_pin"
        case .personalRecordingRecommendation: "personal_recording_recommendation"
        case .follow: "follow"
        case .notification: "notification"
        case .critiquebrainzReview: "critiquebrainz_review"
        case .thanks: "thanks"
        case let .unknown(value): value
        }
    }
}

/// A read-only ListenBrainz social-feed event. Fields without a matching
/// event type are intentionally optional so new server events remain visible.
struct FeedEvent: Identifiable, Hashable, Sendable {
    let serverID: Int?
    let kind: FeedEventKind
    let userName: String
    let created: Date
    let hidden: Bool
    let similarity: Double?
    let recording: Recording?
    let blurb: String?
    let users: [String]
    let userName0: String?
    let userName1: String?
    let relationshipType: String?
    let message: String?
    let entityName: String?
    let entityID: String?
    let entityType: String?
    let rating: Int?
    let text: String?
    let reviewMBID: String?
    let originalEventID: Int?
    let originalEventType: String?
    let thankerUsername: String?
    let thankeeUsername: String?

    var id: String {
        if let serverID { return "server:\(kind.rawValue):\(serverID)" }
        let identity = recording?.id ?? ""
        let discriminators = [
            kind.rawValue,
            normalized(userName),
            String(Int(created.timeIntervalSince1970)),
            identity,
            normalized(userName0),
            normalized(userName1),
            relationshipType ?? "",
            normalized(users.joined(separator: ",")),
            entityID ?? "",
            reviewMBID ?? "",
            originalEventID.map(String.init) ?? "",
            message ?? "",
            blurb ?? "",
            text ?? "",
            normalized(thankerUsername),
            normalized(thankeeUsername),
        ]
        return "synthetic:\(discriminators.joined(separator: "|"))"
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

extension FeedEvent {
    /// The timeline endpoint returns a stable event row ID separately from the
    /// app's display identity. Never use `id` in a server mutation.
    var supportsThank: Bool {
        guard serverID != nil else { return false }
        return kind == .recordingRecommendation
            || kind == .personalRecordingRecommendation
            || kind == .recordingPin
    }

    var supportsHide: Bool {
        guard serverID != nil else { return false }
        return kind == .recordingRecommendation
            || kind == .personalRecordingRecommendation
            || kind == .recordingPin
            || kind == .thanks
            || kind == .notification
            || kind == .critiquebrainzReview
    }

    var supportsGenericDelete: Bool {
        guard serverID != nil else { return false }
        return kind == .recordingRecommendation
            || kind == .personalRecordingRecommendation
            || kind == .notification
    }

    var supportsPinDelete: Bool { serverID != nil && kind == .recordingPin }
}

struct FeedPage: Hashable, Sendable {
    let username: String
    let serverCount: Int
    let events: [FeedEvent]

    var oldestCreated: Date? { events.map(\.created).min() }
}
