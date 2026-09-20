// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ListenBrainzKit

@Suite struct LBFreshReleasesTests {
    @Test("Fresh Releases tolerates optional fields and unpadded dates")
    func decodeTolerantFreshReleases() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            FreshReleasesResponse.self,
            from: Data("""
            {
              "payload": {
                "user_id": "listener",
                "releases": [{
                  "release_name": "A release",
                  "release_mbid": null,
                  "release_group_mbid": "2f7f57c7-3945-4d8c-85b2-2ce0d9911777",
                  "artist_credit_name": "An artist",
                  "artist_mbids": null,
                  "release_date": "2026-9-7",
                  "release_group_primary_type": "Album",
                  "release_group_secondary_type": "Compilation",
                  "release_tags": ["ambient", "electronic"],
                  "confidence": 3,
                  "caa_id": 29179588350,
                  "caa_release_mbid": "e1de5bb9-81a8-4a3f-949e-a54b8eab4c30"
                }]
              }
            }
            """.utf8)
        )
        let release = try #require(response.payload.releases.first)
        #expect(response.payload.userID == "listener")
        #expect(release.releaseDate == "2026-9-7")
        #expect(release.artistMBIDs.isEmpty)
        #expect(release.primaryType == "Album")
        #expect(release.secondaryType == "Compilation")
        #expect(release.tags == ["ambient", "electronic"])
        #expect(release.confidence == 3)
        #expect(release.caaID == "29179588350")
        #expect(release.releaseGroupMBID == "2f7f57c7-3945-4d8c-85b2-2ce0d9911777")
    }

    @Test("Sitewide envelope exposes total count and tolerates null artwork")
    func decodeSitewideEnvelope() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            FreshReleasesResponse.self,
            from: Data("""
            {
              "payload": {
                "total_count": 42,
                "releases": [{
                  "release_name": "No cover yet",
                  "release_mbid": "fefded45-bd50-4a27-b95d-4ea5b70202a8",
                  "artist_credit_name": "Artist",
                  "artist_mbids": [],
                  "release_date": "2026-10-01",
                  "release_group_secondary_type": null,
                  "release_tags": [],
                  "caa_id": null,
                  "caa_release_mbid": null
                }]
              }
            }
            """.utf8)
        )

        #expect(response.payload.totalCount == 42)
        let release = try #require(response.payload.releases.first)
        #expect(release.secondaryType == nil)
        #expect(release.caaID == nil)
        #expect(release.caaReleaseMBID == nil)
    }

    @Test("Fresh Releases requests use distinct paths and valid query bounds")
    func requestSemantics() throws {
        let personalized = PersonalFreshReleasesRequest(
            user: "test user", days: 0, includePast: false, includeFuture: true, sort: .confidence
        )
        let sitewide = SitewideFreshReleasesRequest(
            days: 100, includePast: true, includeFuture: false, sort: .releaseName
        )

        #expect(personalized.data.path == "/1/user/test user/fresh_releases")
        #expect(personalized.data.preservesTrailingSlash == false)
        #expect(personalized.data.queryItems["days"] == ["1"])
        #expect(personalized.data.queryItems["past"] == ["false"])
        #expect(personalized.data.queryItems["future"] == ["true"])
        #expect(personalized.data.queryItems["sort"] == ["confidence"])
        #expect(sitewide.data.path == "/1/explore/fresh-releases/")
        #expect(sitewide.data.preservesTrailingSlash)
        #expect(sitewide.data.queryItems["days"] == ["90"])
        #expect(sitewide.data.queryItems["past"] == ["true"])
        #expect(sitewide.data.queryItems["future"] == ["false"])
        #expect(sitewide.data.queryItems["sort"] == ["release_name"])
    }

    @Test("Mapped no-content response becomes an empty optional")
    func noContentIsNil() async throws {
        let client = LBFreshReleasesClient(MockAPIClient(result: .failure(.noContent)))

        let releases = try await client.personalized(user: "listener")

        #expect(releases == nil)
    }
}
