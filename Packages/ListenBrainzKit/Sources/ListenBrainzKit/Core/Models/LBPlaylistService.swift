// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A music service supported by ListenBrainz's server-side playlist
/// transfer endpoints.
public enum LBPlaylistService: String, CaseIterable, Codable, Sendable {
    case spotify
    case appleMusic = "apple_music"
    case soundCloud = "soundcloud"

    func validatedExternalPlaylistURL(_ rawValue: String) -> URL? {
        guard let components = URLComponents(string: rawValue),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              allowedHosts.contains(host),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              hasValidPlaylistPath(components.percentEncodedPath),
              let url = components.url
        else { return nil }

        return url
    }

    private var allowedHosts: Set<String> {
        switch self {
        case .spotify:
            ["open.spotify.com"]
        case .appleMusic:
            ["music.apple.com"]
        case .soundCloud:
            ["soundcloud.com", "www.soundcloud.com"]
        }
    }

    private func hasValidPlaylistPath(_ path: String) -> Bool {
        let lowercasePath = path.lowercased()
        guard !lowercasePath.contains("%2f"),
              !lowercasePath.contains("%5c")
        else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else { return false }

        switch self {
        case .spotify:
            return components.count == 2 && components[0].lowercased() == "playlist"
        case .appleMusic:
            if components.count >= 2, components[0].lowercased() == "playlist" {
                return true
            }
            return components.count >= 3 && components[1].lowercased() == "playlist"
        case .soundCloud:
            return components.count >= 3 && components[1].lowercased() == "sets"
        }
    }
}
