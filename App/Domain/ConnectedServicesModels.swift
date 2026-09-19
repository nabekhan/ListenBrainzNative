import Foundation

struct ConnectedService: Identifiable, Hashable, Sendable {
    let identifier: String

    var id: String { identifier.lowercased() }

    var label: String? {
        Self.knownLabels[identifier.lowercased()]
    }

    static let knownLabels: [String: String] = [
        "spotify": "Spotify",
        "critiquebrainz": "CritiqueBrainz",
        "lastfm": "Last.fm",
        "librefm": "Libre.fm",
        "soundcloud": "SoundCloud",
        "apple": "Apple Music",
        "funkwhale": "Funkwhale",
        "navidrome": "Navidrome",
        "musicbrainz": "MusicBrainz",
        "musicbrainz-prod": "MusicBrainz",
        "musicbrainz-beta": "MusicBrainz",
        "musicbrainz-test": "MusicBrainz"
    ]
}

struct ConnectedServices: Hashable, Sendable {
    let services: [ConnectedService]

    init(identifiers: [String]) {
        var seen: Set<String> = []
        services = identifiers.compactMap { raw in
            let identifier = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, seen.insert(identifier.lowercased()).inserted else { return nil }
            return ConnectedService(identifier: identifier)
        }
        .sorted { lhs, rhs in
            let lhsName = lhs.label ?? lhs.identifier
            let rhsName = rhs.label ?? rhs.identifier
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }
}

struct ConnectedServicesCacheKey: Hashable, Sendable {
    let username: String
    let scope: RequestGate.ReadScope

    init(username: String, scope: RequestGate.ReadScope) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.scope = scope
    }
}

enum ConnectedServicesPhase: Equatable {
    case idle
    case loading
    case loaded(ConnectedServices)
    case failed(String)
}
