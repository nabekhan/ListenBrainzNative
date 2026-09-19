// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import ListenBrainzKit

@Suite
struct LBStatisticsTests {
    @Test("Top listeners decode tolerantly and preserve useful rows")
    func deserializeTopListeners() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            StatsTopListenersRequest.Result.self,
            from: Data("""
            { "payload": {
              "artist_mbid": "11111111-1111-1111-1111-111111111111",
              "artist_name": "Example Artist",
              "listeners": [
                { "user_name": "listener", "listen_count": "12" },
                { "user_name": null, "listen_count": null }
              ],
              "total_listen_count": "48", "total_user_count": "9", "range": "all_time",
              "from_ts": 1, "to_ts": 2, "last_updated": "3"
            } }
            """.utf8)
        )
        #expect(response.payload.listeners.map(\.userName) == ["listener", ""])
        #expect(response.payload.listeners.map(\.listenCount) == [12, 0])
        #expect(response.payload.artistMBID == "11111111-1111-1111-1111-111111111111")
        #expect(response.payload.artistName == "Example Artist")
        #expect(response.payload.totalListenCount == 48)
        #expect(response.payload.totalUserCount == 9)
        #expect(response.payload.range == "all_time")
        #expect(response.payload.lastUpdated == 3)

        let releaseGroup = try JSONDecoder.ListenBrainz.decode(
            StatsTopListenersRequest.Result.self,
            from: Data("""
            { "payload": {
              "release_group_mbid": "22222222-2222-2222-2222-222222222222",
              "release_group_name": "Example Album", "artist_name": "Example Artist",
              "artist_mbids": ["11111111-1111-1111-1111-111111111111"],
              "caa_id": "42", "caa_release_mbid": "33333333-3333-3333-3333-333333333333",
              "listeners": [], "total_listen_count": 0
            } }
            """.utf8)
        )
        #expect(releaseGroup.payload.releaseGroupMBID == "22222222-2222-2222-2222-222222222222")
        #expect(releaseGroup.payload.releaseGroupName == "Example Album")
        #expect(releaseGroup.payload.artistName == "Example Artist")
        #expect(releaseGroup.payload.artistMBIDs == ["11111111-1111-1111-1111-111111111111"])
        #expect(releaseGroup.payload.coverArtArchiveID == 42)
        #expect(releaseGroup.payload.coverArtArchiveReleaseMBID == "33333333-3333-3333-3333-333333333333")
    }

    @Test("Top listener routes keep artist and release group identities distinct")
    func topListenerRequestSemantics() async throws {
        let artistID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let groupID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let artist = StatsTopListenersRequest(entity: .artist, mbid: artistID, range: .thisMonth)
        let group = StatsTopListenersRequest(entity: .releaseGroup, mbid: groupID, range: nil)
        #expect(artist.data.path == "/1/stats/artist/11111111-1111-1111-1111-111111111111/listeners")
        #expect(group.data.path == "/1/stats/release-group/22222222-2222-2222-2222-222222222222/listeners")
        #expect(artist.data.queryItems == ["range": ["this_month"]])
        #expect(group.data.queryItems.isEmpty)
        #expect(artist.data.statusErrors == [400: .badRequest, 404: .notFound, 204: .noContent])

        let apiClient = ListenBrainzAPIClient(
            token: "", root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let urlRequest = try apiClient.makeURLRequest(artist)
        #expect(urlRequest.url?.path == artist.data.path)
        #expect(urlRequest.url?.query == "range=this_month")

        let client = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))
        #expect(try await client.artistListeners(mbid: artistID, range: .allTime) == nil)
        #expect(try await client.releaseGroupListeners(mbid: groupID) == nil)
    }

    @Test("Artist activity decodes user and sitewide payloads tolerantly")
    func deserializeArtistActivity() throws {
        let response = try JSONDecoder.ListenBrainz.decode(StatsArtistActivityRequest.Result.self, from: Data("""
        { "payload": { "user_id": "listener", "artist_activity": [
          { "name": "  Artist  ", "artist_name": "Artist", "artist_mbid": "11111111-1111-1111-1111-111111111111", "listen_count": "12", "albums": [
            { "name": "Album", "listen_count": 7, "release_group_mbid": "22222222-2222-2222-2222-222222222222" }, { "name": null, "listen_count": null }
          ] }
        ], "range": "this_year", "from_ts": 1, "to_ts": 2, "last_updated": 3 } }
        """.utf8))
        #expect(response.payload.userID == "listener")
        #expect(response.payload.artistActivity.first?.listenCount == 12)
        #expect(response.payload.artistActivity.first?.artistMBID == "11111111-1111-1111-1111-111111111111")
        #expect(response.payload.artistActivity.first?.albums.map(\.listenCount) == [7, 0])
        #expect(response.payload.artistActivity.first?.albums.first?.releaseGroupMBID == "22222222-2222-2222-2222-222222222222")
        #expect(response.payload.artistActivity.first?.albums.last?.name == "")

        let sitewide = try JSONDecoder.ListenBrainz.decode(
            StatsArtistActivityRequest.Result.self,
            from: Data("""
            { "payload": { "artist_activity": [], "range": "all_time", "from_ts": 1, "to_ts": 2, "last_updated": 3 } }
            """.utf8)
        )
        #expect(sitewide.payload.userID == nil)
    }

    @Test("Artist activity request selects user or sitewide endpoint and maps no-content to nil")
    func artistActivityRequestSemantics() async throws {
        let user = StatsArtistActivityRequest(user: "test user", range: .thisMonth)
        let sitewide = StatsArtistActivityRequest(user: nil, range: .allTime)
        #expect(user.data.path == "/1/stats/user/test user/artist-activity")
        #expect(sitewide.data.path == "/1/stats/sitewide/artist-activity")
        #expect(user.data.queryItems == ["range": ["this_month"]])
        #expect(user.data.statusErrors[204] == .noContent)
        let apiClient = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let urlRequest = try apiClient.makeURLRequest(user)
        #expect(urlRequest.url?.path == "/1/stats/user/test user/artist-activity")
        #expect(urlRequest.url?.absoluteString.contains("test%20user") == true)
        #expect(urlRequest.url?.query == "range=this_month")

        let client = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))
        #expect(try await client.artistActivity(user: "listener", range: .thisMonth) == nil)
        #expect(try await client.artistActivitySitewide(range: .allTime) == nil)
    }
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

    @Test("Genre activity tolerates numeric strings and malformed row values")
    func deserializeGenreActivity() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            StatsGenreActivityRequest.Result.self,
            from: Data("""
            {
              "payload": {
                "user_id": "listener",
                "genre_activity": [
                  { "genre": "Electronic", "hour": 0, "listen_count": 4 },
                  { "genre": "Ambient", "hour": "23", "listen_count": "1" },
                  { "genre": null, "hour": "not-an-hour", "listen_count": null }
                ],
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
        #expect(activity.genreActivity.map(\.genre) == ["Electronic", "Ambient", ""])
        #expect(activity.genreActivity.map(\.hour) == [0, 23, -1])
        #expect(activity.genreActivity.map(\.listenCount) == [4, 1, 0])
    }

    @Test("Genre activity request uses the user endpoint, range query, and escaped URL path")
    func genreActivityRequestSemantics() throws {
        let request = StatsGenreActivityRequest(user: "test user", range: .thisMonth)
        #expect(request.data.path == "/1/stats/user/test user/genre-activity")
        #expect(request.data.queryItems == ["range": ["this_month"]])
        #expect(request.data.statusErrors[204] == .noContent)

        let apiClient = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let urlRequest = try apiClient.makeURLRequest(request)
        #expect(urlRequest.url?.path == "/1/stats/user/test user/genre-activity")
        #expect(urlRequest.url?.absoluteString.contains("test%20user") == true)
        #expect(urlRequest.url?.query == "range=this_month")
    }

    @Test("Genre activity maps no-content to nil")
    func genreActivityNoContentIsNil() async throws {
        let client = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))

        let activity = try await client.genreActivity(user: "listener", range: .thisWeek)

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

    @Test("Artist map decodes user and sitewide shapes tolerantly")
    func deserializeArtistMap() throws {
        let userResponse = try JSONDecoder.ListenBrainz.decode(
            StatsArtistMapRequest.Result.self,
            from: Data("""
            { "payload": {
              "user_id": "listener", "artist_map": [{
                "country": "usa", "artist_count": "2", "listen_count": 9,
                "artists": [
                  { "artist_name": "Mapped Artist", "artist_mbid": "11111111-1111-1111-1111-111111111111", "listen_count": "7" },
                  { "artist_name": null, "artist_mbid": "invalid", "listen_count": null }
                ]
              }], "range": "all_time", "from_ts": 1735689600, "to_ts": 1738368000, "last_updated": 1738454400
            }}
            """.utf8)
        )
        let map = userResponse.payload
        #expect(map.userID == "listener")
        #expect(map.artistMap.first?.country == "usa")
        #expect(map.artistMap.first?.artistCount == 2)
        #expect(map.artistMap.first?.artists.map(\.listenCount) == [7, 0])
        #expect(map.artistMap.first?.artists.first?.artistMBID == "11111111-1111-1111-1111-111111111111")
        #expect(map.artistMap.first?.artists.last?.artistName == "")

        let sitewideResponse = try JSONDecoder.ListenBrainz.decode(
            StatsArtistMapRequest.Result.self,
            from: Data("""
            { "payload": { "artist_map": [], "range": "this_year", "from_ts": 1735689600, "to_ts": 1738368000, "last_updated": 1738454400 } }
            """.utf8)
        )
        #expect(sitewideResponse.payload.userID == nil)
    }

    @Test("Artist map requests use exact user and sitewide routes")
    func artistMapRequestSemantics() throws {
        let userRequest = StatsArtistMapRequest(user: "test user", range: .halfYearly)
        #expect(userRequest.data.path == "/1/stats/user/test user/artist-map")
        #expect(userRequest.data.queryItems == ["range": ["half_yearly"]])
        #expect(userRequest.data.statusErrors[204] == .noContent)

        let sitewideRequest = StatsArtistMapRequest(user: nil, range: .allTime)
        #expect(sitewideRequest.data.path == "/1/stats/sitewide/artist-map")
        #expect(sitewideRequest.data.queryItems == ["range": ["all_time"]])

        let apiClient = ListenBrainzAPIClient(token: "", root: URL(string: "https://api.listenbrainz.org")!, userAgent: "TestClient/1.0 (+https://example.com)")
        let urlRequest = try apiClient.makeURLRequest(userRequest)
        #expect(urlRequest.url?.path == "/1/stats/user/test user/artist-map")
        #expect(urlRequest.url?.absoluteString.contains("test%20user") == true)
        #expect(urlRequest.url?.query == "range=half_yearly")
    }

    @Test("Artist map maps no-content to nil")
    func artistMapNoContentIsNil() async throws {
        let client = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))
        #expect(try await client.artistMap(user: "listener", range: .thisWeek) == nil)
        #expect(try await client.artistMapSitewide(range: .thisWeek) == nil)
    }

    @Test("Artist evolution decodes string and numeric buckets with missing artist identifiers")
    func deserializeArtistEvolutionActivity() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            StatsArtistEvolutionActivityRequest.Result.self,
            from: Data("""
            {
              "payload": {
                "user_id": "listener",
                "artist_evolution_activity": [
                  {
                    "time_unit": "January",
                    "artist_mbid": "11111111-1111-1111-1111-111111111111",
                    "artist_name": "First Artist",
                    "listen_count": 12
                  },
                  {
                    "time_unit": 2,
                    "artist_mbid": null,
                    "artist_name": "Second Artist",
                    "listen_count": 8
                  },
                  {
                    "time_unit": 2024,
                    "artist_name": "Unmapped Artist",
                    "listen_count": 3
                  }
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
        #expect(activity.artistEvolutionActivity.map(\.timeUnit) == ["January", "2", "2024"])
        #expect(activity.artistEvolutionActivity.map(\.artistName) == ["First Artist", "Second Artist", "Unmapped Artist"])
        #expect(activity.artistEvolutionActivity.map(\.artistMBID) == [
            "11111111-1111-1111-1111-111111111111",
            nil,
            nil,
        ])
        #expect(activity.artistEvolutionActivity.map(\.listenCount) == [12, 8, 3])
    }

    @Test("Artist evolution request uses the user endpoint, range query, and escaped URL path")
    func artistEvolutionActivityRequestSemantics() throws {
        let request = StatsArtistEvolutionActivityRequest(user: "test user", range: .quarter)
        #expect(request.data.path == "/1/stats/user/test user/artist-evolution-activity")
        #expect(request.data.queryItems == ["range": ["quarter"]])
        #expect(request.data.statusErrors[204] == .noContent)

        let defaultRange = StatsArtistEvolutionActivityRequest(user: "listener", range: nil)
        #expect(defaultRange.data.queryItems.isEmpty)

        let apiClient = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let urlRequest = try apiClient.makeURLRequest(request)
        #expect(urlRequest.url?.path == "/1/stats/user/test user/artist-evolution-activity")
        #expect(urlRequest.url?.absoluteString.contains("test%20user") == true)
        #expect(urlRequest.url?.query == "range=quarter")
    }

    @Test("Artist evolution maps no-content to nil")
    func artistEvolutionActivityNoContentIsNil() async throws {
        let client = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))

        let activity = try await client.artistEvolutionActivity(user: "listener", range: .thisYear)

        #expect(activity == nil)
    }

    @Test("Year in Music decodes the current report with incomplete identifiers")
    func deserializeYearInMusic() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            StatsYearInMusicRequest.Result.self,
            from: Data("""
            {
              "payload": {
                "user_name": "listener",
                "year": 2025,
                "data": {
                  "day_of_week": "Monday",
                  "total_listen_count": 20989,
                  "total_listening_time": 4154743.722,
                  "total_artists_count": 2059,
                  "total_new_artists_discovered": 1227,
                  "total_recordings_count": 12716,
                  "total_release_groups_count": 1861,
                  "listens_per_day": [
                    { "from_ts": 1735689600, "to_ts": 1735775999, "time_range": "01 January 2025", "listen_count": 0 }
                  ],
                  "top_artists": [
                    { "artist_mbid": null, "artist_name": "Unmapped Artist", "listen_count": 507 }
                  ],
                  "top_release_groups": [
                    { "release_group_name": "A Release", "release_group_mbid": null, "artist_name": "Artist", "artist_mbids": [], "listen_count": 210, "caa_id": null }
                  ],
                  "top_recordings": [
                    { "track_name": "A Track", "artist_name": "Artist", "listen_count": 55, "recording_mbid": null, "release_name": "A Release", "release_mbid": null, "caa_id": null, "artists": [] }
                  ],
                  "artist_evolution_activity": [
                    { "artist_name": "Artist", "time_unit": 9, "listen_count": 7 }
                  ],
                  "genre_activity": [
                    { "genre": "alternative pop", "hour": 21, "listen_count": 13 }
                  ],
                  "top_genres": [
                    { "genre": "rock", "genre_count": 13483, "genre_count_percent": 6.02 }
                  ],
                  "similar_users": { "friend": 0.05 },
                  "most_listened_year": { "1957": 2 },
                  "artist_map": [
                    { "country": "USA", "artist_count": 3, "listen_count": 920, "artists": [] }
                  ],
                  "new_releases_of_top_artists": [
                    { "title": "New Release", "release_group_mbid": "not-a-uuid", "caa_id": 42, "artist_credit_mbids": ["also-not-a-uuid"] }
                  ],
                  "playlist-top-discoveries-for-year": {
                    "title": "Top Discoveries", "creator": "listenbrainz", "date": "2025-01-01T00:00:00+00:00", "track": [
                      { "title": "Discovery", "creator": "Artist", "duration": 180000, "identifier": ["https://musicbrainz.org/recording/example"] }
                    ]
                  }
                }
              }
            }
            """.utf8)
        )

        let report = response.payload
        #expect(report.userName == "listener")
        #expect(report.year == 2025)
        #expect(report.isAvailable)
        #expect(report.data.totalListenCount == 20989)
        #expect(report.data.totalListeningTime == 4154743.722)
        #expect(report.data.listensPerDay.first?.from == Date(timeIntervalSince1970: 1735689600))
        #expect(report.data.topArtists.first?.mbid == nil)
        #expect(report.data.topArtists.first?.name == "Unmapped Artist")
        #expect(report.data.topReleaseGroups.first?.mbid == nil)
        #expect(report.data.topRecordings.first?.recordingMBID == nil)
        #expect(report.data.artistEvolutionActivity.first?.timeUnit == "9")
        #expect(report.data.topGenres.first?.countPercent == 6.02)
        #expect(report.data.similarUsers["friend"] == 0.05)
        #expect(report.data.topDiscoveriesPlaylist?.date == "2025-01-01T00:00:00+00:00")
        #expect(report.data.topDiscoveriesPlaylist?.tracks.first?.identifiers?.count == 1)
    }

    @Test("Year in Music accepts a partial or empty data object")
    func deserializePartialAndEmptyYearInMusic() throws {
        let partial = try JSONDecoder.ListenBrainz.decode(
            StatsYearInMusicRequest.Result.self,
            from: Data("""
            { "payload": { "user_name": "listener", "year": 2025, "data": { "total_listen_count": 1 } } }
            """.utf8)
        ).payload
        #expect(partial.isAvailable)
        #expect(partial.data.totalListenCount == 1)
        #expect(partial.data.topArtists.isEmpty)
        #expect(partial.data.topRecordings.isEmpty)

        let empty = try JSONDecoder.ListenBrainz.decode(
            StatsYearInMusicRequest.Result.self,
            from: Data("""
            { "payload": { "user_name": "listener", "year": 2025, "data": {} } }
            """.utf8)
        ).payload
        #expect(!empty.isAvailable)
        #expect(empty.data.listensPerDay.isEmpty)
        #expect(empty.data.topReleaseGroups.isEmpty)
    }

    @Test("Year in Music request uses optional year path and escaped user path")
    func yearInMusicRequestSemantics() throws {
        let current = StatsYearInMusicRequest(user: "test user", year: nil)
        #expect(current.data.path == "/1/stats/user/test%20user/year-in-music")
        #expect(current.data.queryItems.isEmpty)
        #expect(current.data.statusErrors[204] == .noContent)
        #expect(current.data.statusErrors[404] == .notFound)

        let historical = StatsYearInMusicRequest(user: "listener", year: 2025)
        #expect(historical.data.path == "/1/stats/user/listener/year-in-music/2025")

        let apiClient = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let urlRequest = try apiClient.makeURLRequest(current)
        #expect(urlRequest.url?.path == "/1/stats/user/test user/year-in-music")
        #expect(urlRequest.url?.absoluteString.contains("test%20user") == true)

        for (username, encoded) in [
            ("a/b", "a%2Fb"),
            ("..", "%2E%2E"),
            ("50%?", "50%25%3F"),
            ("Björk", "Bj%C3%B6rk"),
        ] {
            let hostile = StatsYearInMusicRequest(user: username, year: 2025)
            let hostileURL = try #require(try apiClient.makeURLRequest(hostile).url)
            #expect(hostileURL.absoluteString.contains("/user/\(encoded)/year-in-music/2025"))
        }
    }

    @Test("Year in Music maps no content to nil and preserves not found")
    func yearInMusicErrors() async throws {
        let noContentClient = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))
        let report = try await noContentClient.yearInMusic(user: "listener", year: 2025)
        #expect(report == nil)

        let missingClient = LBStatisticsClient(MockAPIClient(result: .failure(.notFound)))
        await #expect(throws: LBError.notFound) {
            _ = try await missingClient.yearInMusic(user: "listener", year: 2025)
        }
    }

    @Test("Legacy Year in Music uses the archival route, bounds payloads, and preserves availability")
    func legacyYearInMusic() async throws {
        let request = try StatsLegacyYearInMusicRequest(user: "test user", year: 2021)
        #expect(request.data.path == "/1/stats/user/test%20user/year-in-music/legacy/2021")
        #expect(request.data.method == .get)
        #expect(request.data.statusErrors[204] == .noContent)
        #expect(request.data.statusErrors[404] == .notFound)
        #expect(StatsLegacyYearInMusicRequest.maximumPayloadSize == 16 * 1_024 * 1_024)
        #expect(request.data.maximumResponseBytes == StatsLegacyYearInMusicRequest.maximumPayloadSize)
        #expect(throws: LBError.invalidParam) { _ = try StatsLegacyYearInMusicRequest(user: "listener", year: 2025) }

        let apiClient = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "TestClient/1.0 (+https://example.com)"
        )
        let slashURL = try #require(try apiClient.makeURLRequest(StatsLegacyYearInMusicRequest(user: "a/b", year: 2021)).url)
        #expect(slashURL.absoluteString.contains("/user/a%2Fb/year-in-music/legacy/2021"))
        let dotURL = try #require(try apiClient.makeURLRequest(StatsLegacyYearInMusicRequest(user: "..", year: 2021)).url)
        #expect(dotURL.absoluteString.contains("/user/%2E%2E/year-in-music/legacy/2021"))

        let decoded = try request.decodeResponse(Data("""
        { "payload": { "user_name": "listener", "year": 2021, "data": {
          "total_listen_count": 12,
          "top_artists": [{"artist_name":"Artist", "artist_mbids":["11111111-1111-1111-1111-111111111111"]}],
          "top_releases": [{"release_name":"Edition", "release_mbid":"22222222-2222-2222-2222-222222222222", "artist_name":"Artist", "listen_count":4}],
          "top_releases_coverart": {"22222222-2222-2222-2222-222222222222":"https://archive.org/cover.jpg"},
          "total_releases_count": 3
        } } }
        """.utf8), response: nil)
        #expect(decoded.payload.data.topArtists.first?.mbids?.count == 1)
        #expect(decoded.payload.data.topReleases.first?.title == "Edition")
        #expect(decoded.payload.data.topReleases.first?.releaseMBID != nil)
        #expect(decoded.payload.data.topReleasesCoverArt.count == 1)
        #expect(decoded.payload.data.totalReleasesCount == 3)
        let oversized = Data(repeating: 0, count: StatsLegacyYearInMusicRequest.maximumPayloadSize + 1)
        #expect(throws: LBError.invalidResponse) { _ = try request.decodeResponse(oversized, response: nil) }

        let noContent = LBStatisticsClient(MockAPIClient(result: .failure(.noContent)))
        #expect(try await noContent.legacyYearInMusic(user: "listener", year: 2024) == nil)
        let missing = LBStatisticsClient(MockAPIClient(result: .failure(.notFound)))
        await #expect(throws: LBError.notFound) { _ = try await missing.legacyYearInMusic(user: "listener", year: 2024) }
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
