import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class PopularityProviderTests: XCTestCase {
    func testRoutesConcreteReleaseAndReleaseGroupToDifferentTransportCalls() async throws {
        let transport = PopularityFixtureTransport()
        let provider = ListenBrainzPopularityProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            cache: PopularityCache()
        )
        let release = PopularityEntity(kind: .release, mbid: UUID())
        let releaseGroup = PopularityEntity(kind: .releaseGroup, mbid: UUID())

        _ = try await provider.popularity(for: release)
        _ = try await provider.popularity(for: releaseGroup)

        let calls = await transport.calls()
        XCTAssertEqual(calls, [.release(release.mbid), .releaseGroup(releaseGroup.mbid)])
    }

    func testFreshCachePreservesNullCountsWithoutANewRequest() async throws {
        let entity = PopularityEntity(kind: .artist, mbid: UUID())
        let transport = PopularityFixtureTransport(rows: [popularityFixture(mbid: entity.mbid, listens: nil, users: nil)])
        let provider = ListenBrainzPopularityProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            cache: PopularityCache()
        )

        let first = try await provider.popularity(for: entity)
        let second = try await provider.popularity(for: entity)

        XCTAssertNil(first.totalListenCount)
        XCTAssertNil(first.totalUserCount)
        XCTAssertEqual(second, first)
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testConcurrentDuplicateLoadsCoalesceToOneTransportRequest() async throws {
        let entity = PopularityEntity(kind: .recording, mbid: UUID())
        let transport = PopularityFixtureTransport(
            rows: [popularityFixture(mbid: entity.mbid, listens: 8, users: 3)],
            delay: .milliseconds(40)
        )
        let provider = ListenBrainzPopularityProvider(
            transport: transport,
            gate: RequestGate(minimumInterval: .zero),
            cache: PopularityCache()
        )

        async let first = provider.popularity(for: entity)
        async let second = provider.popularity(for: entity)
        let results = try await [first, second]

        XCTAssertEqual(results.map(\.totalListenCount), [8, 8])
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

}

private actor PopularityFixtureTransport: PopularityTransport {
    enum Call: Equatable {
        case artist(UUID)
        case recording(UUID)
        case release(UUID)
        case releaseGroup(UUID)
    }

    private let rows: [LBPopularity]
    private let delay: Duration
    private var recordedCalls: [Call] = []

    init(rows: [LBPopularity] = [], delay: Duration = .zero) {
        self.rows = rows
        self.delay = delay
    }

    func artists(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await record(Call.artist, mbids: mbids)
    }

    func recordings(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await record(Call.recording, mbids: mbids)
    }

    func releases(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await record(Call.release, mbids: mbids)
    }

    func releaseGroups(_ mbids: [UUID]) async throws -> [LBPopularity] {
        try await record(Call.releaseGroup, mbids: mbids)
    }

    func callCount() -> Int { recordedCalls.count }
    func calls() -> [Call] { recordedCalls }

    private func record(_ kind: (UUID) -> Call, mbids: [UUID]) async throws -> [LBPopularity] {
        guard let first = mbids.first else { return [] }
        recordedCalls.append(kind(first))
        if delay > .zero {
            try await ContinuousClock().sleep(for: delay)
        }
        return rows.isEmpty ? [popularityFixture(mbid: first, listens: nil, users: nil)] : rows
    }
}

private func popularityFixture(mbid: UUID, listens: Int?, users: Int?) -> LBPopularity {
    let payload = """
    [{"artist_mbid":"\(mbid)","total_listen_count":\(listens.map(String.init) ?? "null"),"total_user_count":\(users.map(String.init) ?? "null")}]
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode([LBPopularity].self, from: Data(payload.utf8))[0]
}
