import Foundation
import XCTest

@testable import Brainz

final class ArtistPageContextDecoderTests: XCTestCase {
    func testDecoderPreservesRankAndDropsMalformedOrDuplicateRows() throws {
        let artist = UUID(uuidString: "b7ffd2af-418f-4be2-bdd1-22f8b48613da")!
        let recording = UUID(uuidString: "13dd61c7-ce73-4e97-9f0c-9f0e53144411")!
        let releaseGroup = UUID(uuidString: "d0991cc9-2277-4f5e-bd4d-2fa44507f623")!
        let release = UUID(uuidString: "488ef20e-7a2b-4daf-8bee-4f54fe26c7ab")!
        let neighbor = UUID(uuidString: "39ad19e5-c0b0-454a-985b-201fb92898a0")!
        let data = Data("""
        {
          "artist": { "name": " Nine Inch Nails " },
          "popularRecordings": [
            {
              "recording_mbid": "\(recording)",
              "artist_name": "Malformed row must not reserve this identifier"
            },
            {
              "recording_mbid": "\(recording)",
              "recording_name": "  Closer  ",
              "artist_name": "Nine   Inch Nails",
              "artist_mbids": ["\(artist)", "\(artist)", "broken"],
              "release_name": "The Downward Spiral",
              "release_mbid": "\(release)",
              "caa_release_mbid": "\(release)",
              "length": -1,
              "total_listen_count": 1380798,
              "total_user_count": -7
            },
            {
              "recording_mbid": "\(recording)",
              "recording_name": "Duplicate",
              "artist_name": "Nine Inch Nails"
            },
            { "recording_mbid": "not-a-uuid", "recording_name": "Broken" }
          ],
          "releaseGroups": [
            {
              "mbid": "\(releaseGroup)",
              "artist_credit_name": "Malformed row must not reserve this identifier"
            },
            {
              "mbid": "\(releaseGroup)",
              "name": "  The Downward Spiral  ",
              "artist_credit_name": "Nine Inch Nails",
              "type": "Album",
              "date": "1994-03-08",
              "caa_release_mbid": "\(release)",
              "total_listen_count": 2400000,
              "total_user_count": "120000"
            },
            { "mbid": "\(releaseGroup)", "name": "Duplicate" },
            { "mbid": "broken", "name": "Broken" }
          ],
          "similarArtists": {
            "artists": [
              { "artist_mbid": "\(artist)", "name": "Source", "score": 100 },
              { "artist_mbid": "\(neighbor)", "name": "  Neighbor  ", "score": "91.5" }
            ]
          }
        }
        """.utf8)

        let value = try ArtistPageContextDecoder.decode(data, sourceArtistMBID: artist)

        XCTAssertEqual(value.artistMBID, artist)
        XCTAssertEqual(value.highlights.recordings.count, 1)
        XCTAssertEqual(value.highlights.recordings[0].recordingMBID, recording)
        XCTAssertEqual(value.highlights.recordings[0].title, "Closer")
        XCTAssertEqual(value.highlights.recordings[0].artistName, "Nine Inch Nails")
        XCTAssertEqual(value.highlights.recordings[0].artistMBIDs, [artist])
        XCTAssertNil(value.highlights.recordings[0].durationMilliseconds)
        XCTAssertEqual(value.highlights.recordings[0].totalListenCount, 1_380_798)
        XCTAssertNil(value.highlights.recordings[0].totalUserCount)
        XCTAssertEqual(value.highlights.releaseGroups.count, 1)
        XCTAssertEqual(value.highlights.releaseGroups[0].mbid, releaseGroup)
        XCTAssertEqual(value.highlights.releaseGroups[0].title, "The Downward Spiral")
        XCTAssertEqual(value.highlights.releaseGroups[0].totalUserCount, 120_000)
        XCTAssertEqual(value.similarArtists?.artists.map(\.mbid), [neighbor])
        XCTAssertEqual(value.similarArtists?.artists.first?.name, "Neighbor")
        XCTAssertEqual(value.similarArtists?.artists.first?.score, 91.5)
    }

    func testDecoderToleratesMissingShelvesAndUsesSourceArtistFallback() throws {
        let artist = UUID()
        let recording = UUID()
        let data = Data("""
        {
          "artist": { "artist_mbid": null, "mbid": null, "name": "Source Artist" },
          "popularRecordings": [
            { "recording_mbid": "\(recording)", "recording_name": "Track", "artist_mbids": [] }
          ],
          "listeningStats": {
            "artist_mbid": null,
            "total_listen_count": 9
          }
        }
        """.utf8)

        let value = try ArtistPageContextDecoder.decode(data, sourceArtistMBID: artist)

        XCTAssertEqual(value.highlights.recordings.first?.artistName, "Source Artist")
        XCTAssertEqual(value.highlights.recordings.first?.artistMBIDs, [artist])
        XCTAssertTrue(value.highlights.releaseGroups.isEmpty)
        XCTAssertNil(value.similarArtists)
        XCTAssertEqual(value.popularity?.totalListenCount, 9)
    }

    func testDecoderRejectsANonObjectRoot() {
        XCTAssertThrowsError(
            try ArtistPageContextDecoder.decode(Data("[]".utf8), sourceArtistMBID: UUID())
        ) { error in
            guard case SimilarArtistsProviderError.invalidResponse = error else {
                return XCTFail("Expected invalid response")
            }
        }
    }

    func testDecoderRejectsAMismatchedEchoedArtistIdentity() {
        let requested = UUID()
        let different = UUID()
        let data = Data("""
        {"artist":{"artist_mbid":"\(different)","name":"Wrong artist"}}
        """.utf8)

        XCTAssertThrowsError(
            try ArtistPageContextDecoder.decode(data, sourceArtistMBID: requested)
        ) { error in
            guard case SimilarArtistsProviderError.invalidResponse = error else {
                return XCTFail("Expected invalid response")
            }
        }
    }

    func testDecoderPreservesBoundedIdentityArtworkAndAllTimeCommunityContext() throws {
        let artist = UUID()
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">
          <rect width="400" height="400" fill="#334455"/>
        </svg>
        """
        let listeners = (0..<14).map { index in
            [
                "user_name": index == 0 ? "  listener zero  " : "listener-\(index)",
                "listen_count": 1_000 - index,
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "artist": [
                "artist_mbid": artist.uuidString,
                "mbid": artist.uuidString,
                "name": "  Alvvays  ",
                "type": "Group",
                "area": "Toronto, Ontario, Canada",
                "begin_year": 2011,
                "end_year": NSNull(),
            ],
            "coverArt": svg,
            "listeningStats": [
                "artist_mbid": artist.uuidString,
                "range": "all_time",
                "total_listen_count": "2418731",
                "total_user_count": 148_206,
                "listeners": listeners,
            ],
        ])

        let value = try ArtistPageContextDecoder.decode(data, sourceArtistMBID: artist)

        XCTAssertEqual(value.identity?.artistMBID, artist)
        XCTAssertEqual(value.identity?.name, "Alvvays")
        XCTAssertEqual(value.identity?.type, "Group")
        XCTAssertEqual(value.identity?.area, "Toronto, Ontario, Canada")
        XCTAssertEqual(value.identity?.beginYear, 2011)
        XCTAssertNil(value.identity?.endYear)
        XCTAssertEqual(value.coverArtSVG, svg)
        XCTAssertEqual(value.popularity?.entity, PopularityEntity(kind: .artist, mbid: artist))
        XCTAssertEqual(value.popularity?.totalListenCount, 2_418_731)
        XCTAssertEqual(value.popularity?.totalUserCount, 148_206)
        XCTAssertEqual(value.topListeners?.entity, TopListenersEntity(kind: .artist, mbid: artist))
        XCTAssertEqual(value.topListeners?.listeners.count, ArtistPageContextDecoder.maximumTopListenerCount)
        XCTAssertEqual(value.topListeners?.listeners.first?.username, "listener zero")
        XCTAssertEqual(value.topListeners?.totalListenCount, 2_418_731)
    }

    func testDecoderRejectsMismatchedStatsAndDropsUnsafeOrOversizedArtwork() throws {
        let artist = UUID()
        let different = UUID()
        let mismatched = try JSONSerialization.data(withJSONObject: [
            "artist": ["artist_mbid": artist.uuidString],
            "listeningStats": ["artist_mbid": different.uuidString],
        ])
        XCTAssertThrowsError(
            try ArtistPageContextDecoder.decode(mismatched, sourceArtistMBID: artist)
        ) { error in
            guard case SimilarArtistsProviderError.invalidResponse = error else {
                return XCTFail("Expected invalid response")
            }
        }

        let unsafe = try JSONSerialization.data(withJSONObject: [
            "artist": ["artist_mbid": artist.uuidString],
            "coverArt": "<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"https://example.com/track.png\"/></svg>",
            "listeningStats": [
                "artist_mbid": artist.uuidString,
                "range": "month",
                "total_listen_count": 42,
            ],
        ])
        let unsafeValue = try ArtistPageContextDecoder.decode(unsafe, sourceArtistMBID: artist)
        XCTAssertNil(unsafeValue.coverArtSVG)
        XCTAssertNil(unsafeValue.popularity)
        XCTAssertNil(unsafeValue.topListeners)

        let oversizedSVG = "<svg>" + String(
            repeating: " ",
            count: ArtistPageContextDecoder.maximumCoverArtBytes
        ) + "</svg>"
        let oversized = try JSONSerialization.data(withJSONObject: ["coverArt": oversizedSVG])
        XCTAssertNil(
            try ArtistPageContextDecoder.decode(oversized, sourceArtistMBID: artist).coverArtSVG
        )
    }

    func testDecoderBoundsEveryEmbeddedCollection() throws {
        let artist = UUID()
        let artistIDs = (0..<25).map { _ in UUID().uuidString }
        let recordings = (0..<12).map { index in
            [
                "recording_mbid": UUID().uuidString,
                "recording_name": "Track \(index)",
                "artist_name": "Artist",
                "artist_mbids": artistIDs,
            ] as [String: Any]
        }
        let releaseGroups = (0..<12).map { index in
            [
                "mbid": UUID().uuidString,
                "name": "Release \(index)",
                "artist_credit_name": "Artist",
            ]
        }
        let similarArtists = (0..<24).map { index in
            [
                "artist_mbid": UUID().uuidString,
                "name": "Similar artist \(index)",
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "artist": ["artist_mbid": artist.uuidString, "name": "Artist"],
            "popularRecordings": recordings,
            "releaseGroups": releaseGroups,
            "similarArtists": ["artists": similarArtists],
        ])

        let value = try ArtistPageContextDecoder.decode(data, sourceArtistMBID: artist)

        XCTAssertEqual(value.highlights.recordings.count, ArtistHighlights.maximumRecordingCount)
        XCTAssertEqual(value.highlights.recordings.first?.artistMBIDs.count, 20)
        XCTAssertEqual(value.highlights.releaseGroups.count, ArtistHighlights.maximumReleaseGroupCount)
        XCTAssertEqual(value.similarArtists?.artists.count, SimilarArtists.maximumCount)
    }
}

final class ArtistHeroPresentationTests: XCTestCase {
    func testMetadataAndArtworkAccessibilityCopyStayConciseAndComplete() {
        let artist = UUID()
        let presentation = ArtistHeroPresentation(
            artistName: "Alvvays",
            identity: ArtistPageIdentity(
                artistMBID: artist,
                name: "Alvvays",
                type: "Group",
                area: "Toronto, Ontario, Canada",
                beginYear: 2011,
                endYear: nil
            )
        )

        XCTAssertEqual(presentation.metadataLine, "Since 2011 · Toronto, Ontario, Canada")
        XCTAssertEqual(presentation.artworkAccessibilityLabel, "Artwork for Alvvays")
    }

    func testMetadataUsesBoundedYearsAndOmitsAnEmptyLine() {
        let artist = UUID()
        XCTAssertEqual(
            ArtistHeroPresentation(
                artistName: "Artist",
                identity: ArtistPageIdentity(
                    artistMBID: artist,
                    name: "Artist",
                    type: nil,
                    area: nil,
                    beginYear: 1987,
                    endYear: 2001
                )
            ).metadataLine,
            "1987–2001"
        )
        XCTAssertNil(ArtistHeroPresentation(artistName: "Artist", identity: nil).metadataLine)
    }
}

final class ArtistPageContextProviderTests: XCTestCase {
    func testAllArtistPageConsumersShareOneRequest() async throws {
        let artist = UUID()
        let transport = ArtistPageTransportFixture()
        let contextProvider = ListenBrainzArtistPageContextProvider(
            gate: RequestGate(minimumInterval: .zero),
            cache: EntityDetailCache(timeToLive: 120),
            transport: { artistMBID in try await transport.value(for: artistMBID) }
        )
        let highlights = ListenBrainzArtistHighlightsProvider(contextProvider: contextProvider)
        let similar = ListenBrainzSimilarArtistsProvider(contextProvider: contextProvider)
        let popularity = ArtistPageContextPopularityProvider(contextProvider: contextProvider)
        let topListeners = ArtistPageContextTopListenersProvider(contextProvider: contextProvider)

        async let loadedContext = contextProvider.context(for: artist, forceRefresh: false)
        async let loadedHighlights = highlights.highlights(for: artist, forceRefresh: false)
        async let loadedSimilar = similar.similarArtists(to: artist)
        async let loadedPopularity = popularity.popularity(
            for: PopularityEntity(kind: .artist, mbid: artist)
        )
        async let loadedTopListeners = topListeners.topListeners(
            for: TopListenersEntity(kind: .artist, mbid: artist)
        )
        let (contextValue, highlightValue, similarValue, popularityValue, listenersValue) = try await (
            loadedContext,
            loadedHighlights,
            loadedSimilar,
            loadedPopularity,
            loadedTopListeners
        )

        XCTAssertEqual(contextValue?.identity?.name, "Artist")
        XCTAssertEqual(highlightValue?.recordings.count, 1)
        XCTAssertEqual(similarValue?.artists.count, 1)
        XCTAssertEqual(popularityValue.totalListenCount, 30)
        XCTAssertEqual(popularityValue.totalUserCount, 12)
        XCTAssertEqual(listenersValue?.listeners.first?.username, "top-listener")
        let calls = await transport.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testPageAdaptersDoNotFanOutOrDuplicateErrorsAfterPageFailure() async throws {
        // Repeat with an immediate failure so scheduler ordering cannot hide a
        // cache-publication race between independently mounted sections.
        for _ in 0 ..< 20 {
            let artist = UUID()
            let transport = FailingArtistPageTransportFixture()
            let contextProvider = ListenBrainzArtistPageContextProvider(
                gate: RequestGate(minimumInterval: .zero),
                cache: EntityDetailCache(timeToLive: 120),
                transport: { artistMBID in try await transport.value(for: artistMBID) }
            )
            let popularity = ArtistPageContextPopularityProvider(contextProvider: contextProvider)
            let topListeners = ArtistPageContextTopListenersProvider(contextProvider: contextProvider)
            let highlights = ListenBrainzArtistHighlightsProvider(
                contextProvider: contextProvider,
                suppressesErrors: true
            )
            let similar = ListenBrainzSimilarArtistsProvider(
                contextProvider: contextProvider,
                suppressesErrors: true
            )

            async let popularityValue = popularity.popularity(
                for: PopularityEntity(kind: .artist, mbid: artist)
            )
            async let listenerValue = topListeners.topListeners(
                for: TopListenersEntity(kind: .artist, mbid: artist)
            )
            async let highlightValue = highlights.highlights(for: artist, forceRefresh: false)
            async let similarValue = similar.similarArtists(to: artist)
            let (loadedPopularity, loadedListeners, loadedHighlights, loadedSimilar) = try await (
                popularityValue,
                listenerValue,
                highlightValue,
                similarValue
            )

            XCTAssertNil(loadedPopularity.totalListenCount)
            XCTAssertNil(loadedPopularity.totalUserCount)
            XCTAssertNil(loadedListeners)
            XCTAssertNil(loadedHighlights)
            XCTAssertNil(loadedSimilar)
            let calls = await transport.callCount()
            XCTAssertEqual(calls, 1)
        }
    }

    func testFreshContextCacheAvoidsAnotherReadAndExplicitRefreshMakesOne() async throws {
        let artist = UUID()
        let transport = ArtistPageTransportFixture()
        let provider = ListenBrainzArtistPageContextProvider(
            gate: RequestGate(minimumInterval: .zero),
            cache: EntityDetailCache(timeToLive: 120),
            transport: { artistMBID in try await transport.value(for: artistMBID) }
        )

        _ = try await provider.context(for: artist, forceRefresh: false)
        _ = try await provider.context(for: artist, forceRefresh: false)
        var calls = await transport.callCount()
        XCTAssertEqual(calls, 1)

        _ = try await provider.context(for: artist, forceRefresh: true)
        calls = await transport.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testFailureRemainsAnErrorWhenNegativeCachedWithoutAutomaticRetry() async {
        let artist = UUID()
        let transport = FailingArtistPageTransportFixture()
        let provider = ListenBrainzArtistPageContextProvider(
            gate: RequestGate(minimumInterval: .zero),
            cache: EntityDetailCache(timeToLive: 120),
            transport: { artistMBID in try await transport.value(for: artistMBID) }
        )

        do {
            _ = try await provider.context(for: artist, forceRefresh: false)
            XCTFail("Expected the first request to fail")
        } catch {
            XCTAssertEqual(error as? ArtistHighlightsFixtureError, .failed)
        }
        do {
            _ = try await provider.context(for: artist, forceRefresh: false)
            XCTFail("Expected the cached failure to remain visible")
        } catch {
            guard case SimilarArtistsProviderError.server(status: 0) = error else {
                return XCTFail("Expected a cached provider failure")
            }
        }

        let calls = await transport.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testChildFirstFailureStillReachesThePageOwnerWithoutAnotherRead() async {
        let artist = UUID()
        let transport = FailingArtistPageTransportFixture()
        let contextProvider = ListenBrainzArtistPageContextProvider(
            gate: RequestGate(minimumInterval: .zero),
            cache: EntityDetailCache(timeToLive: 120),
            transport: { artistMBID in try await transport.value(for: artistMBID) }
        )
        let child = ListenBrainzSimilarArtistsProvider(
            contextProvider: contextProvider,
            suppressesErrors: true
        )

        let childValue = try? await child.similarArtists(to: artist)
        XCTAssertNil(childValue)
        do {
            _ = try await contextProvider.context(for: artist, forceRefresh: false)
            XCTFail("Expected the page owner to receive the cached failure")
        } catch {
            guard case SimilarArtistsProviderError.server(status: 0) = error else {
                return XCTFail("Expected a cached provider failure")
            }
        }

        let calls = await transport.callCount()
        XCTAssertEqual(calls, 1)
    }
}

@MainActor
final class ArtistHighlightsModelTests: XCTestCase {
    func testPickerSwitchesLocallyWithoutAnotherProviderRead() async {
        let artist = UUID()
        let value = artistHighlightsFixture(artist: artist)
        let provider = ArtistHighlightsFixtureProvider(results: [.success(value)])
        let model = ArtistHighlightsModel(artistMBID: artist, provider: provider)

        await model.load()
        model.select(.releases)
        model.select(.tracks)
        await model.load()

        XCTAssertEqual(model.phase, .loaded(value))
        XCTAssertEqual(model.selection, .tracks)
        let calls = await provider.calls()
        XCTAssertEqual(calls.map(\.forceRefresh), [false])
    }

    func testReleasesBecomeDefaultWhenTracksAreUnavailable() async {
        let artist = UUID()
        let fixture = artistHighlightsFixture(artist: artist)
        let value = ArtistHighlights(
            artistMBID: artist,
            recordings: [],
            releaseGroups: fixture.releaseGroups
        )
        let provider = ArtistHighlightsFixtureProvider(results: [.success(value)])
        let model = ArtistHighlightsModel(artistMBID: artist, provider: provider)

        await model.load()

        XCTAssertEqual(model.phase, .loaded(value))
        XCTAssertEqual(model.selection, .releases)
    }

    func testExplicitRetryBypassesTheNegativeCacheBoundary() async {
        let artist = UUID()
        let value = artistHighlightsFixture(artist: artist)
        let provider = ArtistHighlightsFixtureProvider(results: [.failure, .success(value)])
        let model = ArtistHighlightsModel(artistMBID: artist, provider: provider)

        await model.load()
        guard case .failed = model.phase else { return XCTFail("Expected the first load to fail") }

        await model.retry()

        XCTAssertEqual(model.phase, .loaded(value))
        let calls = await provider.calls()
        XCTAssertEqual(calls.map(\.forceRefresh), [false, true])
    }
}

private actor ArtistPageTransportFixture {
    private var count = 0

    func value(for artistMBID: UUID) async throws -> Data? {
        count += 1
        try await ContinuousClock().sleep(for: .milliseconds(25))
        return artistPageJSON(artist: artistMBID)
    }

    func callCount() -> Int { count }
}

private actor FailingArtistPageTransportFixture {
    private var count = 0

    func value(for artistMBID: UUID) async throws -> Data? {
        count += 1
        throw ArtistHighlightsFixtureError.failed
    }

    func callCount() -> Int { count }
}

private actor ArtistHighlightsFixtureProvider: ArtistHighlightsProviding {
    struct Call: Equatable {
        let artistMBID: UUID
        let forceRefresh: Bool
    }

    enum Result: Sendable {
        case success(ArtistHighlights?)
        case failure
    }

    private let results: [Result]
    private var recordedCalls: [Call] = []

    init(results: [Result]) { self.results = results }

    func highlights(for artistMBID: UUID, forceRefresh: Bool) async throws -> ArtistHighlights? {
        let index = recordedCalls.count
        recordedCalls.append(Call(artistMBID: artistMBID, forceRefresh: forceRefresh))
        switch results.indices.contains(index) ? results[index] : results.last ?? .failure {
        case let .success(value): return value
        case .failure: throw ArtistHighlightsFixtureError.failed
        }
    }

    func calls() -> [Call] { recordedCalls }
}

private enum ArtistHighlightsFixtureError: LocalizedError, Equatable {
    case failed
    var errorDescription: String? { "Fixture request failed." }
}

private func artistHighlightsFixture(artist: UUID) -> ArtistHighlights {
    ArtistHighlights(
        artistMBID: artist,
        recordings: [
            ArtistPopularRecording(
                recordingMBID: UUID(),
                title: "Track",
                artistName: "Artist",
                artistMBIDs: [artist],
                releaseTitle: "Release",
                releaseMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: 180_000,
                totalListenCount: 10,
                totalUserCount: 4
            ),
        ],
        releaseGroups: [
            ArtistPopularReleaseGroup(
                mbid: UUID(),
                title: "Album",
                artistName: "Artist",
                primaryType: "Album",
                firstReleaseDate: "2024",
                artworkReleaseMBID: nil,
                totalListenCount: 20,
                totalUserCount: 8
            ),
        ]
    )
}

private func artistPageJSON(artist: UUID) -> Data {
    let recording = UUID()
    let releaseGroup = UUID()
    let similar = UUID()
    return Data("""
    {
      "artist": {
        "artist_mbid": "\(artist)",
        "name": "Artist",
        "area": "Fixture City",
        "begin_year": 2001
      },
      "listeningStats": {
        "artist_mbid": "\(artist)",
        "stats_range": "all_time",
        "total_listen_count": 30,
        "total_user_count": 12,
        "listeners": [
          { "user_name": "top-listener", "listen_count": 25 }
        ]
      },
      "popularRecordings": [
        {
          "recording_mbid": "\(recording)",
          "recording_name": "Track",
          "artist_name": "Artist",
          "artist_mbids": ["\(artist)"],
          "total_listen_count": 10,
          "total_user_count": 4
        }
      ],
      "releaseGroups": [
        {
          "mbid": "\(releaseGroup)",
          "name": "Album",
          "artist_credit_name": "Artist",
          "total_listen_count": 20,
          "total_user_count": 8
        }
      ],
      "similarArtists": {
        "artists": [
          { "artist_mbid": "\(similar)", "name": "Neighbor", "score": 90 }
        ]
      }
    }
    """.utf8)
}
