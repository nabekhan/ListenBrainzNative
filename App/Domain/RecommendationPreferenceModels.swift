import Foundation
import Observation

enum RecommendationPreferenceEntity: String, CaseIterable, Equatable, Sendable {
    case artist
    case release
    case releaseGroup = "release_group"
    case recording

    var pathComponent: String {
        switch self {
        case .artist: "artist"
        case .release: "release"
        case .releaseGroup: "release-group"
        case .recording: "recording"
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .artist: "Artist"
        case .release: "Release"
        case .releaseGroup: "Release group"
        case .recording: "Recording"
        }
    }
}

/// An active, canonical MusicBrainz recommendation preference. The list API
/// intentionally contains no names or artwork, so this stays identity-first
/// and avoids hidden metadata requests while browsing it.
struct RecommendationPreference: Identifiable, Equatable, Sendable {
    let entity: RecommendationPreferenceEntity
    let entityMBID: UUID
    let createdAt: Date
    let expiresAt: Date?

    var id: String { "\(entity.rawValue):\(entityMBID.uuidString.lowercased())" }

    var musicBrainzURL: URL {
        URL(string: "https://musicbrainz.org/\(entity.pathComponent)/\(entityMBID.uuidString)")!
    }
}

struct RecommendationPreferencePage: Equatable, Sendable {
    let username: String
    let items: [RecommendationPreference]
    let serverCount: Int
    let offset: Int
    let totalCount: Int
}

enum RecommendationPreferenceDuration: CaseIterable, Equatable, Sendable {
    case permanent
    case sevenDays
    case thirtyDays

    func expiration(from date: Date) -> Date? {
        switch self {
        case .permanent: nil
        case .sevenDays: date.addingTimeInterval(7 * 24 * 60 * 60)
        case .thirtyDays: date.addingTimeInterval(30 * 24 * 60 * 60)
        }
    }
}

/// Process-local invalidation signal for simultaneously visible preference
/// screens. It contains a normalized public username and opaque source ID only;
/// credentials and music identities never enter the signal.
@MainActor
@Observable
final class RecommendationPreferenceChanges {
    struct Event: Equatable {
        let revision: UInt64
        let sourceID: UUID
    }

    static let shared = RecommendationPreferenceChanges()

    private var events: [String: Event] = [:]

    func event(for username: String) -> Event? {
        events[Self.key(for: username)]
    }

    func recordChange(for username: String, sourceID: UUID) {
        let key = Self.key(for: username)
        guard !key.isEmpty else { return }
        let revision = (events[key]?.revision ?? 0) &+ 1
        events[key] = Event(revision: revision, sourceID: sourceID)
    }

    private static func key(for username: String) -> String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}
