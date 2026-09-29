import Foundation

struct ConnectedService: Identifiable, Hashable, Sendable {
    let identifier: String

    var id: String { identifier.lowercased() }

    var label: String? {
        Self.knownLabels[identifier.lowercased()]
    }

    static let knownLabels: [String: String] = [
        "spotify": String(localized: "Spotify"),
        "critiquebrainz": String(localized: "CritiqueBrainz"),
        "lastfm": String(localized: "Last.fm"),
        "librefm": String(localized: "Libre.fm"),
        "soundcloud": String(localized: "SoundCloud"),
        "apple": String(localized: "Apple Music"),
        "funkwhale": String(localized: "Funkwhale"),
        "navidrome": String(localized: "Navidrome"),
        "musicbrainz": String(localized: "MusicBrainz"),
        "musicbrainz-prod": String(localized: "MusicBrainz"),
        "musicbrainz-beta": String(localized: "MusicBrainz"),
        "musicbrainz-test": String(localized: "MusicBrainz")
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

    var playlistExportDestinations: [PlaylistExternalService] {
        let connected = Set(services.map { $0.identifier.lowercased() })
        return PlaylistExternalService.allCases.filter { service in
            !service.connectionIdentifiers.isDisjoint(with: connected)
        }
    }
}

enum PlaylistExternalService: String, CaseIterable, Codable, Identifiable, Sendable {
    case spotify
    case appleMusic = "apple_music"
    case soundCloud = "soundcloud"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spotify:
            String(localized: "Spotify")
        case .appleMusic:
            String(localized: "Apple Music")
        case .soundCloud:
            String(localized: "SoundCloud")
        }
    }

    var connectionIdentifiers: Set<String> {
        switch self {
        case .spotify:
            ["spotify"]
        case .appleMusic:
            // The account-services endpoint uses `apple`; playlist routes use
            // `apple_music`. Accept both without exposing either wire name.
            ["apple", "apple_music"]
        case .soundCloud:
            ["soundcloud"]
        }
    }

    var serviceHomeURL: URL {
        switch self {
        case .spotify:
            URL(string: "https://open.spotify.com/collection/playlists")!
        case .appleMusic:
            URL(string: "https://music.apple.com/")!
        case .soundCloud:
            URL(string: "https://soundcloud.com/you/sets")!
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
