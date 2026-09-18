// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import ListenBrainzKit

@Suite
struct LBStatisticsTests {
    @Test("Daily activity decodes weekday hour buckets")
    func deserializeDailyActivity() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            StatsDailyActivityRequest.Result.self,
            from: Data("""
            {
              "payload": {
                "user_id": "listener",
                "daily_activity": {
                  "Monday": [
                    { "hour": 0, "listen_count": 4 },
                    { "hour": 23, "listen_count": 1 }
                  ],
                  "Sunday": [
                    { "hour": 12, "listen_count": 7 }
                  ]
                },
                "range": "this_month",
                "from_ts": 1735689600,
                "to_ts": 1738368000,
                "last_updated": 1738454400
              }
            }
            """.utf8)
        )

        let activity = response.payload
        #expect(activity.userID == "listener")
        #expect(activity.range == "this_month")
        #expect(activity.from == Date(timeIntervalSince1970: 1735689600))
        #expect(activity.to == Date(timeIntervalSince1970: 1738368000))
        #expect(activity.lastUpdated == 1738454400)
        #expect(activity.dailyActivity["Monday"]?.map(\.listenCount) == [4, 1])
        #expect(activity.dailyActivity["Sunday"]?.first?.hour == 12)
    }

    @Test("Daily activity request uses the user endpoint, range query, and escaped URL path")
    func dailyActivityRequestSemantics() throws {
        let request = StatsDailyActivityRequest(user: "test user", range: .halfYearly)
        #expect(request.data.path == "/1/stats/user/test user/daily-activity")
        #expect(request.data.queryItems == ["range": ["half_yearly"]])
        #expect(request.data.statusErrors[204] == .noContent)

        let apiClient = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let urlRequest = try apiClient.makeURLRequest(request)
        #expect(urlRequest.url?.path == "/1/stats/user/test user/daily-activity")
        #expect(urlRequest.url?.absoluteString.contains("test%20user") == true)
        #expect(urlRequest.url?.query == "range=half_yearly")
    }

    @Test("Daily activity maps no-content to nil")
    func dailyActivityNoContentIsNil() async throws {
        let client = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))

        let activity = try await client.dailyActivity(user: "listener", range: .thisWeek)

        #expect(activity == nil)
    }

    @Test("Era activity decodes original release years")
    func deserializeEraActivity() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            StatsEraActivityRequest.Result.self,
            from: Data("""
            {
              "payload": {
                "user_id": "listener",
                "era_activity": [
                  { "year": 1971, "listen_count": 3 },
                  { "year": 1997, "listen_count": 9 },
                  { "year": 2024, "listen_count": 1 }
                ],
                "range": "this_year",
                "from_ts": 1735689600,
                "to_ts": 1767225600,
                "last_updated": 1767312000
              }
            }
            """.utf8)
        )

        let activity = response.payload
        #expect(activity.userID == "listener")
        #expect(activity.range == "this_year")
        #expect(activity.from == Date(timeIntervalSince1970: 1735689600))
        #expect(activity.to == Date(timeIntervalSince1970: 1767225600))
        #expect(activity.lastUpdated == 1767312000)
        #expect(activity.eraActivity.map(\.year) == [1971, 1997, 2024])
        #expect(activity.eraActivity.map(\.listenCount) == [3, 9, 1])
    }

    @Test("Era activity request uses the user endpoint, range query, and escaped URL path")
    func eraActivityRequestSemantics() throws {
        let request = StatsEraActivityRequest(user: "test user", range: .thisYear)
        #expect(request.data.path == "/1/stats/user/test user/era-activity")
        #expect(request.data.queryItems == ["range": ["this_year"]])
        #expect(request.data.statusErrors[204] == .noContent)

        let apiClient = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let urlRequest = try apiClient.makeURLRequest(request)
        #expect(urlRequest.url?.path == "/1/stats/user/test user/era-activity")
        #expect(urlRequest.url?.absoluteString.contains("test%20user") == true)
        #expect(urlRequest.url?.query == "range=this_year")
    }

    @Test("Era activity maps no-content to nil")
    func eraActivityNoContentIsNil() async throws {
        let client = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))

        let activity = try await client.eraActivity(user: "listener", range: .thisYear)

        #expect(activity == nil)
    }

    @Test("Deserialize user artists")
    func deserializeUserArtists() async throws {
        let res = try JSONDecoder
            .ListenBrainz
            .decode(StatsArtistsRequest.Result.self,
                    from: Data("""
                    {
                        "payload":
                        {
                            "artists": [
                                {
                                    "artist_mbid": "ABABABAB-1212-ABAB-1212-ABABABABABAB",
                                    "artist_name": "Artist 1",
                                    "listen_count": 123
                                },
                                {
                                    "artist_mbid": "22222222-1212-ABAB-1212-ABABABABABAB",
                                    "artist_name": "Artist 2",
                                    "listen_count": 100
                                },
                            ],
                            "count": 2,
                            "from_ts": 1009843200,
                            "last_updated": 1737763200,
                            "offset": 0,
                            "range": "all_time",
                            "to_ts": 1737763200,
                            "total_artist_count": 2,
                            "user_id": "username"
                        }
                    }
                    """.utf8))
        #expect(res.payload.artists.count == 2)
    }

    @Test("Deserialize user releases")
    func deserializeUserReleases() async throws {
        let res = try JSONDecoder
            .ListenBrainz
            .decode(StatsReleasesRequest.Result.self,
                    from: Data(
                        """
                        {
                            "payload": {
                                "count": 1,
                                "offset": 0,
                                "range": "all_time",
                                "releases": [
                                    {
                                        "artist_mbids": [
                                            "62162215-b023-4f0e-84bd-1e9412d5b32c",
                                            "faf4cefb-036c-4c88-b93a-5b03dd0a0e6b",
                                            "e07d9474-00ea-4460-ac27-88b46b3d976e"
                                        ],
                                        "artist_name": "All Time Low ft. Demi Lovato & blackbear",
                                        "artists": [
                                            {
                                                "artist_credit_name": "All Time Low",
                                                "artist_mbid": "62162215-b023-4f0e-84bd-1e9412d5b32c",
                                                "join_phrase": " ft. "
                                            },
                                            {
                                                "artist_credit_name": "Demi Lovato",
                                                "artist_mbid": "faf4cefb-036c-4c88-b93a-5b03dd0a0e6b",
                                                "join_phrase": " & "
                                            },
                                            {
                                                "artist_credit_name": "blackbear",
                                                "artist_mbid": "e07d9474-00ea-4460-ac27-88b46b3d976e",
                                                "join_phrase": ""
                                            }
                                        ],
                                        "caa_id": 29179588350,
                                        "caa_release_mbid": "ee65192d-31f3-437a-b170-9158d2172dbc",
                                        "listen_count": 1,
                                        "release_mbid": "ee65192d-31f3-437a-b170-9158d2172dbc",
                                        "release_name": "Monsters"
                                    }
                                ],
                                "from_ts": 1009843200,
                                "to_ts": 1737763200,
                                "last_updated": 1737763200,
                                "total_release_count": 1,
                                "user_id": "username"
                            }
                        }
                        """.utf8))
        let release = try #require(res.payload.releases.first)
        let mbids = try #require(release.artistMbids)
        #expect(mbids.count == 3)
        let artists = try #require(release.artists)
        #expect(artists.count == 3)
    }

    @Test("Deserialize user releases")
    func deserializeUserReleaseGroups() async throws {
        let res = try JSONDecoder
            .ListenBrainz
            .decode(StatsReleaseGroupsRequest.Result.self,
                    from: Data("""
                    {
                    "payload": {
                        "count": 1,
                        "from_ts": 1009843200,
                        "last_updated": 1737763200,
                        "offset": 0,
                        "range": "all_time",
                        "release_groups": [
                            {
                                "artist_mbids": [
                                    "62162215-b023-4f0e-84bd-1e9412d5b32c",
                                    "faf4cefb-036c-4c88-b93a-5b03dd0a0e6b",
                                    "e07d9474-00ea-4460-ac27-88b46b3d976e"
                                ],
                                "artist_name": "All Time Low ft. Demi Lovato & blackbear",
                                "artists": [
                                    {
                                        "artist_credit_name": "All Time Low",
                                        "artist_mbid": "62162215-b023-4f0e-84bd-1e9412d5b32c",
                                        "join_phrase": " ft. "
                                    },
                                    {
                                        "artist_credit_name": "Demi Lovato",
                                        "artist_mbid": "faf4cefb-036c-4c88-b93a-5b03dd0a0e6b",
                                        "join_phrase": " & "
                                    },
                                    {
                                        "artist_credit_name": "blackbear",
                                        "artist_mbid": "e07d9474-00ea-4460-ac27-88b46b3d976e",
                                        "join_phrase": ""
                                    }
                                ],
                                "caa_id": 29179588350,
                                "caa_release_mbid": "ee65192d-31f3-437a-b170-9158d2172dbc",
                                "listen_count": 1,
                                "release_group_mbid": "326b4a29-dff5-4fab-87dc-efc1494001c6",
                                "release_group_name": "Monsters"
                            }
                        ],
                        "to_ts": 1737763200,
                        "total_release_group_count": 1,
                        "user_id": "username"
                    }
                    }
                    """.utf8))
        #expect(res.payload.releaseGroups.count == 1)
        let group = try #require(res.payload.releaseGroups.first)
        let artists = try #require(group.artists)
        #expect(artists.count == 3)
    }

    @Test("Deserialize user recordings")
    func deserializeUserRecordings() async throws {
        let res = try JSONDecoder
            .ListenBrainz
            .decode(StatsRecordingsRequest.Result.self,
                    from: Data("""
                    {
                        "payload": {
                            "count": 1,
                            "from_ts": 1009843200,
                            "last_updated": 1737763200,
                            "offset": 0,
                            "range": "all_time",
                            "recordings": [
                                {
                                    "artist_mbids": [
                                        "62162215-b023-4f0e-84bd-1e9412d5b32c",
                                        "faf4cefb-036c-4c88-b93a-5b03dd0a0e6b",
                                        "e07d9474-00ea-4460-ac27-88b46b3d976e"
                                    ],
                                    "artist_name": "All Time Low ft. Demi Lovato & blackbear",
                                    "artists": [
                                        {
                                            "artist_credit_name": "All Time Low",
                                            "artist_mbid": "62162215-b023-4f0e-84bd-1e9412d5b32c",
                                            "join_phrase": " ft. "
                                        },
                                        {
                                            "artist_credit_name": "Demi Lovato",
                                            "artist_mbid": "faf4cefb-036c-4c88-b93a-5b03dd0a0e6b",
                                            "join_phrase": " & "
                                        },
                                        {
                                            "artist_credit_name": "blackbear",
                                            "artist_mbid": "e07d9474-00ea-4460-ac27-88b46b3d976e",
                                            "join_phrase": ""
                                        }
                                    ],
                                    "caa_id": 29179588350,
                                    "caa_release_mbid": "ee65192d-31f3-437a-b170-9158d2172dbc",
                                    "listen_count": 1,
                                    "recording_mbid": "e8ffcb88-c908-43c1-aa6f-70af63436c53",
                                    "release_mbid": "ee65192d-31f3-437a-b170-9158d2172dbc",
                                    "release_name": "Monsters",
                                    "track_name": "Monsters"
                                }
                            ],
                            "to_ts": 1737763200,
                            "total_recording_count": 4,
                            "user_id": "username"
                        }
                    }
                    """.utf8))
        #expect(res.payload.recordings.count == 1)
        let recording = try #require(res.payload.recordings.first)
        let mbids = try #require(recording.artistMbids)
        #expect(mbids.count == 3)
    }
}
