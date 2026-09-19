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
          "artist": { "name": "Source Artist" },
          "popularRecordings": [
            { "recording_mbid": "\(recording)", "recording_name": "Track", "artist_mbids": [] }
          ]
        }
        """.utf8)

        let value = try ArtistPageContextDecoder.decode(data, sourceArtistMBID: artist)

        XCTAssertEqual(value.highlights.recordings.first?.artistName, "Source Artist")
        XCTAssertEqual(value.highlights.recordings.first?.artistMBIDs, [artist])
        XCTAssertTrue(value.highlights.releaseGroups.isEmpty)
        XCTAssertNil(value.similarArtists)
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

final class ArtistPageContextProviderTests: XCTestCase {
    func testSeparateHighlightAndSimilarConsumersShareOneRequest() async throws {
        let artist = UUID()
        let transport = ArtistPageTransportFixture()
        let contextProvider = ListenBrainzArtistPageContextProvider(
            gate: RequestGate(minimumInterval: .zero),
            cache: EntityDetailCache(timeToLive: 120),
            transport: { artistMBID in try await transport.value(for: artistMBID) }
        )
        let highlights = ListenBrainzArtistHighlightsProvider(contextProvider: contextProvider)
        let similar = ListenBrainzSimilarArtistsProvider(contextProvider: contextProvider)

        async let loadedHighlights = highlights.highlights(for: artist, forceRefresh: false)
        async let loadedSimilar = similar.similarArtists(to: artist)
        let (highlightValue, similarValue) = try await (loadedHighlights, loadedSimilar)

        XCTAssertEqual(highlightValue?.recordings.count, 1)
        XCTAssertEqual(similarValue?.artists.count, 1)
        let calls = await transport.callCount()
        XCTAssertEqual(calls, 1)
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

    func testFailureIsNegativeCachedWithoutAutomaticRetry() async {
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
        let cooledDown = try? await provider.context(for: artist, forceRefresh: false)

        XCTAssertNil(cooledDown)
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
      "artist": { "name": "Artist" },
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
