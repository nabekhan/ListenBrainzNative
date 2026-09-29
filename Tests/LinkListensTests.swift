import ListenBrainzKit
import XCTest
@testable import Brainz

final class LinkListensTests: XCTestCase {
    @MainActor
    func testGroupsRowsByReleaseAndArtistWithStableOrdering() {
        let rows = [
            fixture(title: "B", artist: "Artist", release: "Album", seconds: 1),
            fixture(title: "A", artist: "Artist", release: "Album", seconds: 2),
            fixture(title: "C", artist: "Other", release: nil, seconds: 3),
        ]

        let groups = LinkListensGroup.make(from: rows)

        XCTAssertEqual(groups.map(\.title), ["Album", "No release"])
        XCTAssertEqual(groups.first?.artistName, "Artist")
        XCTAssertEqual(groups.first?.listens.map(\.recording.title), ["A", "B"])
    }

    func testProviderUsesOneBoundedReadAndBuildsMappingEligibleListens() async throws {
        let msid = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let source = LBMissingMusicBrainzListen(
            artistName: "  Artist  ",
            recordingName: " Track ",
            releaseName: " Album ",
            recordingMsid: msid,
            listenedAt: Date(timeIntervalSince1970: 100)
        )
        let duplicateSource = LBMissingMusicBrainzListen(
            artistName: "Artist",
            recordingName: "Alternate submitted title",
            releaseName: "Alternate release",
            recordingMsid: msid,
            listenedAt: Date(timeIntervalSince1970: 99)
        )
        let counter = LinkListensCallCounter()
        let provider = ListenBrainzLinkListensProvider(
            gate: RequestGate(minimumInterval: .zero, maximumConcurrentReads: 2),
            transport: { username, offset, count in
                await counter.record(username: username, offset: offset, count: count)
                return .init(
                    userName: username,
                    lastUpdated: Date(timeIntervalSince1970: 200),
                    count: 2,
                    totalDataCount: 2,
                    offset: 0,
                    data: [source, duplicateSource]
                )
            }
        )

        let page = try await provider.unmatchedListens(username: "listener")

        let calls = await counter.calls
        let lastOffset = await counter.lastOffset
        let lastCount = await counter.lastCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(lastOffset, 0)
        XCTAssertEqual(lastCount, 1_000)
        XCTAssertEqual(page.listens.count, 1, "Duplicate MSIDs should not create duplicate mapping rows")
        XCTAssertEqual(page.totalDataCount, 2)
        XCTAssertEqual(page.sourceRowCounts[msid], 2)
        XCTAssertEqual(page.listens.first?.recording.title, "Track")
        XCTAssertEqual(page.listens.first?.recording.artistName, "Artist")
        XCTAssertEqual(page.listens.first?.recording.releaseTitle, "Album")
        XCTAssertEqual(page.listens.first?.inspection?.recordingMSID, msid)
        XCTAssertNil(page.listens.first?.inspection?.submittedRecordingMBID)
    }

    func testProviderRejectsContradictoryEnvelope() async {
        let provider = ListenBrainzLinkListensProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: { _, _, _ in
                .init(
                    userName: "another-listener",
                    lastUpdated: nil,
                    count: 0,
                    totalDataCount: 0,
                    offset: 0,
                    data: []
                )
            }
        )

        do {
            _ = try await provider.unmatchedListens(username: "listener")
            XCTFail("Expected an invalid response")
        } catch let error as LinkListensProviderError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testFreshCachePreventsRepeatedNavigationReadButRefreshReadsAgain() async {
        let counter = LinkListensCallCounter()
        let provider = LinkListensFixtureProvider(
            page: .init(
                listens: [fixture(title: "One", artist: "Artist", release: nil)],
                totalDataCount: 1,
                lastUpdated: nil
            ),
            counter: counter
        )
        let cache = EntityDetailCache<LinkListensCacheKey, LinkListensPage>()
        let account = Account(username: "fixture", token: "token")

        let first = LinkListensModel(account: account, provider: provider, cache: cache)
        await first.load()
        XCTAssertEqual(first.phase, .loaded)

        let reopened = LinkListensModel(account: account, provider: provider, cache: cache)
        await reopened.load()
        XCTAssertEqual(reopened.phase, .loaded)
        var calls = await counter.calls
        XCTAssertEqual(calls, 1)

        await reopened.refresh()
        calls = await counter.calls
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testConfirmedMappingRemovesOnlyMatchingMSIDAndUpdatesCache() async throws {
        let first = fixture(title: "One", artist: "Artist", release: nil)
        let second = fixture(title: "Two", artist: "Artist", release: nil)
        let firstMSID = try XCTUnwrap(first.recording.identity.msid)
        let cache = EntityDetailCache<LinkListensCacheKey, LinkListensPage>()
        let model = LinkListensModel(
            account: .init(username: "fixture", token: "token"),
            provider: LinkListensFixtureProvider(
                page: .init(
                    listens: [first, second],
                    totalDataCount: 3,
                    lastUpdated: nil,
                    sourceRowCounts: [firstMSID: 2]
                )
            ),
            cache: cache
        )

        await model.load()
        await model.removeMapped(msid: firstMSID)

        XCTAssertEqual(model.page.listens, [second])
        XCTAssertEqual(model.page.totalDataCount, 1)
        XCTAssertNil(model.page.sourceRowCounts[firstMSID])
        let cached = await cache.value(for: .init(username: "fixture"))
        XCTAssertEqual(cached?.value.listens, [second])
    }

    @MainActor
    func testInitialFailureAndStaleRefreshFailureRemainExplicit() async {
        let account = Account(username: "fixture", token: "token")
        let failed = LinkListensModel(
            account: account,
            provider: LinkListensFixtureProvider(error: URLError(.notConnectedToInternet)),
            cache: EntityDetailCache()
        )

        await failed.load()
        guard case .failed = failed.phase else {
            return XCTFail("Expected an initial failure")
        }

        let staleCache = EntityDetailCache<LinkListensCacheKey, LinkListensPage>(
            timeToLive: 0,
            maximumEntryCount: 1
        )
        await staleCache.save(
            .init(
                listens: [fixture(title: "Saved", artist: "Artist", release: nil)],
                totalDataCount: 1,
                lastUpdated: nil
            ),
            for: .init(username: account.username)
        )
        let stale = LinkListensModel(
            account: account,
            provider: LinkListensFixtureProvider(error: URLError(.notConnectedToInternet)),
            cache: staleCache
        )

        await stale.load()

        XCTAssertEqual(stale.phase, .loaded)
        XCTAssertEqual(stale.retainedCount, 1)
        XCTAssertNotNil(stale.refreshMessage)
    }

    private func fixture(
        title: String,
        artist: String,
        release: String?,
        seconds: TimeInterval = 0
    ) -> Listen {
        let msid = UUID()
        return .init(
            recording: .init(
                identity: .init(mbid: nil, msid: msid),
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: release,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: Date(timeIntervalSince1970: 1_000 + seconds),
            insertedAt: nil,
            isPlayingNow: false
        )
    }
}

private actor LinkListensCallCounter {
    private(set) var calls = 0
    private(set) var lastOffset: Int?
    private(set) var lastCount: Int?

    func record(username _: String, offset: Int, count: Int) {
        calls += 1
        lastOffset = offset
        lastCount = count
    }

    func increment() {
        calls += 1
    }
}

private struct LinkListensFixtureProvider: LinkListensProviding {
    let page: LinkListensPage
    let error: (any Error)?
    let counter: LinkListensCallCounter?

    init(
        page: LinkListensPage = .init(listens: [], totalDataCount: 0, lastUpdated: nil),
        error: (any Error)? = nil,
        counter: LinkListensCallCounter? = nil
    ) {
        self.page = page
        self.error = error
        self.counter = counter
    }

    func unmatchedListens(username _: String) async throws -> LinkListensPage {
        await counter?.increment()
        if let error { throw error }
        return page
    }
}
