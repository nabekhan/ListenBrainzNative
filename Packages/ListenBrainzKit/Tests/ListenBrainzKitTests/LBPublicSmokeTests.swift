// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import ListenBrainzKit

@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["LISTENBRAINZ_PUBLIC_SMOKE"] == "1")
)
struct LBPublicSmokeTests {
    private let username = ProcessInfo.processInfo.environment["LISTENBRAINZ_PUBLIC_USER"] ?? "rob"
    private let client = LBClient(
        token: "",
        userAgent: "ListenBrainzKit-PublicSmoke/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
    )

    @Test("Current public ListenBrainz endpoints decode")
    func publicReadSurface() async throws {
        let listens = try await client.core.userListens(username: username, count: 2)
        let count = try await client.core.userListensCount(username: username)
        _ = try await client.core.userPlayingNow(username: username)
        let artists = try await client.stats.topArtists(user: username, count: 2, range: .allTime)

        #expect(!listens.listens.isEmpty)
        #expect(count > 0)
        #expect(artists?.artists.isEmpty == false)
    }
}
