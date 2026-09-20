import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class YearInMusicModelTests: XCTestCase {
    func testMappingNormalizesTotalsLeapDaysAndStableMediaIdentities() throws {
        let artistA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let artistB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let releaseGroup = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let release = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let recordingA = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let recordingB = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let report = try yearInMusic("""
        {
          "user_name": "listener", "year": 2024,
          "data": {
            "total_listen_count": -1, "total_listening_time": -7,
            "total_artists_count": -2, "total_recordings_count": 7,
            "total_release_groups_count": -3, "total_new_artists_discovered": -4,
            "listens_per_day": [
              {"from_ts": 1709164800, "time_range": "29 February 2024", "listen_count": 2},
              {"from_ts": 1709164800, "time_range": "2024-02-29", "listen_count": -8}
            ],
            "top_artists": [
              {"artist_mbid": "\(artistA)", "artist_name": "Shared", "listen_count": 3},
              {"artist_mbid": "\(artistB)", "artist_name": "Shared", "listen_count": 7},
              {"artist_mbid": "\(artistA)", "artist_name": "Shared", "listen_count": 2}
            ],
            "top_release_groups": [
              {"release_group_mbid": "\(releaseGroup)", "release_group_name": "Album", "artist_name": "Artist", "artist_mbids": ["\(artistA)"], "listen_count": 2, "caa_id": 8, "caa_release_mbid": "\(release)"},
              {"release_group_mbid": "\(releaseGroup)", "release_group_name": "Album deluxe", "artist_name": "Artist", "artist_mbids": ["\(artistB)"], "listen_count": -9, "caa_id": 4, "caa_release_mbid": "\(release)"}
            ],
            "top_recordings": [
              {"recording_mbid": "\(recordingA)", "track_name": "Same", "artist_name": "Artist", "release_mbid": "\(release)", "listen_count": 2, "caa_id": 10},
              {"recording_mbid": "\(recordingA)", "track_name": "Same (Remaster)", "artist_name": "Artist", "release_mbid": "\(release)", "listen_count": 4, "caa_id": 8},
              {"recording_mbid": "\(recordingB)", "track_name": "Same", "artist_name": "Artist", "release_mbid": "\(release)", "listen_count": 3, "caa_id": 9},
              {"track_name": "Unmapped", "artist_name": "Artist", "release_mbid": "\(release)", "listen_count": 1}
            ]
          }
        }
        """)
        let mapped = try XCTUnwrap(YearInMusicReport(source: report, requestedYear: 2024))

        XCTAssertEqual(mapped.totals.listenCount, 0)
        XCTAssertEqual(mapped.totals.listeningTime, 0)
        XCTAssertEqual(mapped.totals.recordingCount, 7)
        XCTAssertEqual(mapped.listeningDays.count, 1)
        XCTAssertEqual(mapped.listeningDays[0].listenCount, 2)
        XCTAssertEqual(utcComponents(mapped.listeningDays[0].day), DateComponents(year: 2024, month: 2, day: 29))
        XCTAssertEqual(mapped.topArtists.count, 2)
        XCTAssertEqual(Set(mapped.topArtists.compactMap(\.mbid)), Set([artistA, artistB]))
        XCTAssertEqual(mapped.topArtists.first(where: { $0.mbid == artistA })?.listenCount, 5)
        XCTAssertEqual(mapped.topReleaseGroups.count, 1)
        XCTAssertEqual(mapped.topReleaseGroups[0].releaseGroupMBID, releaseGroup)
        XCTAssertEqual(mapped.topReleaseGroups[0].artworkReleaseMBID, release)
        XCTAssertEqual(mapped.topReleaseGroups[0].coverArtArchiveID, 4)
        XCTAssertEqual(mapped.topReleaseGroups[0].artistMBIDs, [artistA, artistB])
        XCTAssertEqual(mapped.topRecordings.count, 3)
        XCTAssertEqual(Set(mapped.topRecordings.compactMap { $0.recording.identity.mbid }), Set([recordingA, recordingB]))
        XCTAssertEqual(mapped.topRecordings.first(where: { $0.recording.identity.mbid == recordingA })?.listenCount, 6)
        XCTAssertEqual(
            mapped.topRecordings.first(where: { $0.recording.identity.mbid == recordingA })?.detailDestination?.identity.mbid,
            recordingA
        )
        let unmapped = try XCTUnwrap(mapped.topRecordings.first(where: { $0.recording.title == "Unmapped" }))
        XCTAssertEqual(unmapped.recording.releaseMBID, release)
        XCTAssertNil(unmapped.detailDestination)
    }

    func testEmptyReportMapsToUnavailableRatherThanEmptyRetrospective() throws {
        let source = try yearInMusic("{ \"user_name\": \"listener\", \"year\": 2025, \"data\": {} }")
        XCTAssertNil(YearInMusicReport(source: source, requestedYear: 2025))
    }

    func testIdentityChapterNormalizesPresenceTagsWeekdayAndReleaseDecades() throws {
        let source = try yearInMusic("""
        { "user_name": "listener", "year": 2024, "data": {
          "total_listen_count": 1,
          "total_new_artists_discovered": 0,
          "day_of_week": " WED ",
          "top_genres": [
            {"genre": "Dream Pop", "genre_count": 4, "genre_count_percent": 12.5},
            {"genre": "dream pop ", "genre_count": -9, "genre_count_percent": -2},
            {"genre": "Ambient", "genre_count": 3, "genre_count_percent": 300},
            {"genre": "  ", "genre_count": 99, "genre_count_percent": 99}
          ],
          "most_listened_year": {
            "2010": 2, "2019": 4, "2020": -1,
            "1849": 8, "2026": 7, "not a year": 6
          }
        } }
        """)

        let mapped = try XCTUnwrap(YearInMusicReport(source: source, requestedYear: 2024))

        XCTAssertTrue(mapped.totals.hasNewArtistCount)
        XCTAssertEqual(mapped.totals.newArtistCount, 0)
        XCTAssertEqual(mapped.mostActiveWeekday, .init(name: "Wednesday", order: 2))
        XCTAssertEqual(mapped.topGenres.count, 2)
        XCTAssertEqual(mapped.topGenres[0].name, "Dream Pop")
        XCTAssertEqual(mapped.topGenres[0].listenCount, 4)
        XCTAssertTrue(mapped.topGenres[0].hasListenCount)
        XCTAssertEqual(mapped.topGenres[0].percentage, 12.5)
        XCTAssertEqual(mapped.topGenres[1].name, "Ambient")
        XCTAssertEqual(mapped.topGenres[1].percentage, 100)
        XCTAssertEqual(mapped.releaseDecades, [.init(decade: 2010, listenCount: 6)])
        XCTAssertTrue(mapped.hasIdentityContent)
    }

    func testIdentityChapterOmitsUnavailableAndInvalidValues() throws {
        let source = try yearInMusic("""
        { "user_name": "listener", "year": 2021, "data": {
          "total_listen_count": 1,
          "total_new_artists_discovered": -1,
          "day_of_week": "everyday",
          "top_genres": [{"genre": "Noise"}],
          "most_listened_year": {"2020": 0}
        } }
        """)

        let mapped = try XCTUnwrap(YearInMusicReport(source: source, requestedYear: 2021, sourceKind: .archive))

        XCTAssertFalse(mapped.totals.hasNewArtistCount)
        XCTAssertNil(mapped.mostActiveWeekday)
        XCTAssertEqual(mapped.topGenres, [.init(name: "Noise", listenCount: 0, percentage: nil, hasListenCount: false)])
        XCTAssertTrue(mapped.releaseDecades.isEmpty)
        XCTAssertTrue(mapped.hasIdentityContent, "A supplied tag name remains useful even without a count.")
    }

    func testArchiveMapsConcreteReleasesAndMissingTotalsTruthfully() throws {
        let source = try yearInMusic("""
        { "user_name": "listener", "year": 2021, "data": {
          "total_listen_count": 9,
          "top_artists": [{"artist_name":"Artist", "artist_mbids":["11111111-1111-1111-1111-111111111111"], "listen_count": 9}],
          "top_releases": [{"release_name":"Edition", "release_mbid":"22222222-2222-2222-2222-222222222222", "artist_name":"Artist", "artist_credit_mbids":["11111111-1111-1111-1111-111111111111"], "listen_count":9}],
          "top_releases_coverart": {"22222222-2222-2222-2222-222222222222":"https://archive.org/download/edition/cover.jpg"}
        } }
        """)
        let mapped = try XCTUnwrap(YearInMusicReport(source: source, requestedYear: 2021, sourceKind: .archive))
        XCTAssertEqual(mapped.source, .archive)
        XCTAssertEqual(mapped.topArtists.first?.mbid?.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(mapped.topReleases.count, 1)
        XCTAssertEqual(mapped.topReleases.first?.seed?.mbid.uuidString, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(mapped.topReleases.first?.artworkURL?.absoluteString, "https://archive.org/download/edition/cover.jpg")
        XCTAssertFalse(mapped.totals.hasArtistCount)
        XCTAssertFalse(mapped.totals.hasRecordingCount)
        XCTAssertFalse(mapped.totals.hasReleaseCount)
        XCTAssertFalse(mapped.totals.hasListeningTime)
    }

    func testProviderUsesExactlyOneTransportCallAndMapsUnavailableForms() async throws {
        let transport = CountingTransport(result: .report(try yearInMusic("{ \"user_name\": \"listener\", \"year\": 2025, \"data\": { \"total_listen_count\": 1 } }")))
        let provider = ListenBrainzYearInMusicProvider(transport: transport, gate: RequestGate(minimumInterval: .zero))

        let loaded = try await provider.report(username: "listener", year: 2025)

        XCTAssertEqual(loaded?.totals.listenCount, 1)
        XCTAssertEqual(transport.callCount, 1)
        XCTAssertEqual(transport.currentCallCount, 1)
        XCTAssertEqual(transport.legacyCallCount, 0)

        transport.result = .notFound
        let unavailable404 = try await provider.report(username: "listener", year: 2024)
        XCTAssertNil(unavailable404)
        XCTAssertEqual(transport.callCount, 2)
        XCTAssertEqual(transport.currentCallCount, 1)
        XCTAssertEqual(transport.legacyCallCount, 1)

        transport.result = .noContent
        let unavailable204 = try await provider.report(username: "listener", year: 2024)
        XCTAssertNil(unavailable204)
        XCTAssertEqual(transport.callCount, 3)

        transport.result = .report(try yearInMusic("{ \"user_name\": \"listener\", \"year\": 2024, \"data\": {} }"))
        let unavailableEmpty = try await provider.report(username: "listener", year: 2024)
        XCTAssertNil(unavailableEmpty)
        XCTAssertEqual(transport.callCount, 4)
        XCTAssertEqual(transport.currentCallCount, 1)
        XCTAssertEqual(transport.legacyCallCount, 3)
    }

    func testProviderMapsRateLimitConsistently() async throws {
        let transport = CountingTransport(result: .rateLimited(3))
        let provider = ListenBrainzYearInMusicProvider(transport: transport, gate: RequestGate(minimumInterval: .zero))

        do {
            _ = try await provider.report(username: "listener", year: 2025)
            XCTFail("Expected rate limit")
        } catch let ProviderError.rateLimited(seconds) {
            XCTAssertEqual(seconds, 3)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testModelCachesByNormalizedUserAndYear() async throws {
        let cache = EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>()
        let provider = YearInMusicFixtureProvider(result: .success(try mappedReport(listens: 4)))
        let first = YearInMusicModel(account: .init(username: " Listener ", token: ""), year: 2025, provider: provider, cache: cache)
        await first.load()
        await first.load()
        let firstCallCount = await provider.callCount()
        XCTAssertEqual(firstCallCount, 1)

        let same = YearInMusicModel(account: .init(username: "listener", token: ""), year: 2025, provider: provider, cache: cache)
        await same.load()
        let sameCallCount = await provider.callCount()
        XCTAssertEqual(sameCallCount, 1)

        let otherYear = YearInMusicModel(account: .init(username: "listener", token: ""), year: 2024, provider: provider, cache: cache)
        await otherYear.load()
        let otherYearCallCount = await provider.callCount()
        XCTAssertEqual(otherYearCallCount, 2)

        let samePublicArchive = YearInMusicModel(account: .init(username: "listener", token: "another-token"), year: 2024, provider: provider, cache: cache)
        await samePublicArchive.load()
        let publicArchiveCallCount = await provider.callCount()
        XCTAssertEqual(publicArchiveCallCount, 2, "Public archives should share their anonymous cache scope")

        let otherAuthenticatedCurrent = YearInMusicModel(account: .init(username: "listener", token: "another-token"), year: 2025, provider: provider, cache: cache)
        await otherAuthenticatedCurrent.load()
        let authenticatedCurrentCallCount = await provider.callCount()
        XCTAssertEqual(authenticatedCurrentCallCount, 3, "Current reports remain isolated by authenticated scope")
    }

    func testStaleReportRemainsVisibleOnRefreshFailure() async throws {
        let cache = EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>(timeToLive: -1)
        let stale = try mappedReport(listens: 7)
        await cache.save(
            stale,
            for: .init(
                username: "listener",
                scope: .authenticated(token: ""),
                year: 2025
            )
        )
        let provider = YearInMusicFixtureProvider(result: .failure, delay: .milliseconds(30))
        let model = YearInMusicModel(account: .init(username: "listener", token: ""), year: 2025, provider: provider, cache: cache)

        let task = Task { await model.load() }
        while await provider.callCount() == 0 { try await ContinuousClock().sleep(for: .milliseconds(1)) }
        XCTAssertEqual(model.state, .refreshing)
        XCTAssertEqual(model.report?.totals.listenCount, 7)
        await task.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.report?.totals.listenCount, 7)
        XCTAssertNotNil(model.refreshMessage)
    }

    func testUnavailableCancellationAndLateResponsesAreTruthful() async throws {
        let unavailable = YearInMusicModel(
            account: .init(username: "listener", token: ""), year: 2025,
            provider: YearInMusicFixtureProvider(result: .unavailable), cache: EntityDetailCache()
        )
        await unavailable.load()
        XCTAssertEqual(unavailable.state, .unavailable)

        let provider = YearInMusicFixtureProvider(
            results: [.success(try mappedReport(listens: 1)), .success(try mappedReport(listens: 9))],
            delays: [.milliseconds(80), .zero], ignoresCancellation: true
        )
        let model = YearInMusicModel(account: .init(username: "listener", token: ""), year: 2025, provider: provider, cache: EntityDetailCache())
        let first = Task { await model.load() }
        while await provider.callCount() == 0 { try await ContinuousClock().sleep(for: .milliseconds(1)) }
        await model.refresh()
        first.cancel()
        await first.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.report?.totals.listenCount, 9)

        let cancellableProvider = YearInMusicFixtureProvider(
            result: .success(try mappedReport(listens: 3)), delay: .seconds(1)
        )
        let cancellable = YearInMusicModel(
            account: .init(username: "listener", token: ""), year: 2025,
            provider: cancellableProvider, cache: EntityDetailCache()
        )
        let cancelledLoad = Task { await cancellable.load() }
        while await cancellableProvider.callCount() == 0 {
            try await ContinuousClock().sleep(for: .milliseconds(1))
        }
        cancelledLoad.cancel()
        await cancelledLoad.value
        XCTAssertEqual(cancellable.state, .idle)
        XCTAssertNil(cancellable.report)
    }

    func testCalendarLayoutUsesMondayFirstUTCLeapYearGrid() throws {
        let leapDay = try XCTUnwrap(utcDate(year: 2024, month: 2, day: 29))
        let layout = YearInMusicCalendarLayout(
            year: 2024,
            listeningDays: [
                .init(day: leapDay, listenCount: 8, sourceTimeRange: nil),
            ]
        )

        XCTAssertEqual(layout.leadingDayCount, 0) // 1 January 2024 was Monday.
        XCTAssertEqual(layout.days.count, 366)
        XCTAssertEqual(layout.weekCount, 53)
        XCTAssertEqual(layout.activeDayCount, 1)
        XCTAssertEqual(layout.busiestDay?.date, leapDay)
        XCTAssertEqual(layout.day(week: 0, weekday: 0)?.date, utcDate(year: 2024, month: 1, day: 1))
        XCTAssertEqual(layout.intensity(for: 8), 1)
        XCTAssertTrue(layout.shortDayLabel(leapDay).contains("29"))
        XCTAssertFalse(layout.shortDayLabel(leapDay).contains("28"))
    }

    func testCalendarLayoutFillsMissingDaysAndUsesSquareRootIntensity() throws {
        let januaryFirst = try XCTUnwrap(utcDate(year: 2025, month: 1, day: 1))
        let januarySecond = try XCTUnwrap(utcDate(year: 2025, month: 1, day: 2))
        let layout = YearInMusicCalendarLayout(
            year: 2025,
            listeningDays: [
                .init(day: januaryFirst, listenCount: 9, sourceTimeRange: nil),
                .init(day: januarySecond, listenCount: 1, sourceTimeRange: nil),
            ]
        )

        XCTAssertEqual(layout.leadingDayCount, 2) // Wednesday in a Monday-first grid.
        XCTAssertNil(layout.day(week: 0, weekday: 0))
        XCTAssertEqual(layout.day(week: 0, weekday: 2)?.date, januaryFirst)
        XCTAssertEqual(layout.days[2].listenCount, 0)
        XCTAssertEqual(layout.intensity(for: 1), 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertTrue(layout.accessibilitySummary.contains("2 active days"))
    }

    private func mappedReport(listens: Int) throws -> YearInMusicReport {
        try XCTUnwrap(YearInMusicReport(source: yearInMusic("{ \"user_name\": \"listener\", \"year\": 2025, \"data\": { \"total_listen_count\": \(listens) } }"), requestedYear: 2025))
    }

    private func yearInMusic(_ json: String) throws -> LBYearInMusic {
        struct Envelope: Decodable { let payload: LBYearInMusic }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Envelope.self, from: Data("{ \"payload\": \(json) }".utf8)).payload
    }

    private func utcComponents(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    private func utcDate(year: Int, month: Int, day: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

private final class CountingTransport: YearInMusicTransport, @unchecked Sendable {
    enum Result { case report(LBYearInMusic), notFound, noContent, rateLimited(Int) }
    var result: Result
    private(set) var currentCallCount = 0
    private(set) var legacyCallCount = 0
    var callCount: Int { currentCallCount + legacyCallCount }

    init(result: Result) { self.result = result }

    func yearInMusic(username: String, year: Int) async throws -> LBYearInMusic? {
        currentCallCount += 1
        return try resultValue()
    }

    func legacyYearInMusic(username: String, year: Int) async throws -> LBYearInMusic? {
        legacyCallCount += 1
        return try resultValue()
    }

    private func resultValue() throws -> LBYearInMusic? {
        switch result {
        case let .report(report): return report
        case .notFound: throw LBError.notFound
        case .noContent: throw LBError.noContent
        case let .rateLimited(seconds): throw LBError.rateLimited(resetIn: seconds)
        }
    }

}

private actor YearInMusicFixtureProvider: YearInMusicProviding {
    enum Result: Sendable { case success(YearInMusicReport), unavailable, failure }
    private var results: [Result]
    private var delays: [Duration]
    private let ignoresCancellation: Bool
    private var calls = 0

    init(result: Result, delay: Duration = .zero) {
        results = [result]
        delays = [delay]
        ignoresCancellation = false
    }

    init(results: [Result], delays: [Duration], ignoresCancellation: Bool) {
        self.results = results
        self.delays = delays
        self.ignoresCancellation = ignoresCancellation
    }

    func report(username: String, year: Int) async throws -> YearInMusicReport? {
        let index = calls
        calls += 1
        let delay = delays.indices.contains(index) ? delays[index] : .zero
        if delay > .zero {
            do { try await Task.sleep(for: delay) }
            catch where ignoresCancellation { }
        }
        let result = results.indices.contains(index) ? results[index] : results.last ?? .unavailable
        switch result {
        case let .success(report): return report
        case .unavailable: return nil
        case .failure: throw FixtureError.failed
        }
    }

    func callCount() -> Int { calls }
}

private enum FixtureError: LocalizedError { case failed
    var errorDescription: String? { "Fixture failed" }
}
