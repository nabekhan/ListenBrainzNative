import Foundation
import XCTest
import ListenBrainzKit

@testable import Brainz

@MainActor
final class ConnectedServicesModelTests: XCTestCase {
    func testKnownAndUnknownIdentifiersRemainVisible() {
        let services = ConnectedServices(identifiers: [
            " spotify ", "musicbrainz-prod", "future-service", "SPOTIFY", ""
        ])

        XCTAssertEqual(Set(services.services.map(\.identifier)), ["spotify", "musicbrainz-prod", "future-service"])
        XCTAssertEqual(services.services.count, 3)
        XCTAssertEqual(services.services.first(where: { $0.identifier == "spotify" })?.label, "Spotify")
        XCTAssertEqual(services.services.first(where: { $0.identifier == "musicbrainz-prod" })?.label, "MusicBrainz")
        XCTAssertNil(services.services.first(where: { $0.identifier == "future-service" })?.label)
    }

    func testCacheKeyNormalizesUsernameWithoutChangingWireIdentityElsewhere() {
        let scope = RequestGate.ReadScope.isolated()
        XCTAssertEqual(
            ConnectedServicesCacheKey(username: " Listener ", scope: scope),
            ConnectedServicesCacheKey(username: "listener", scope: scope)
        )
    }

    func testFreshCredentialScopedCacheAvoidsASecondRead() async {
        let account = Account(username: "listener", token: "token")
        let provider = ConnectedServicesFixtureProvider(results: [.success(["spotify"])])
        let cache = EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices>()
        let scope = RequestGate.ReadScope.isolated()
        let first = ConnectedServicesModel(account: account, scope: scope, provider: provider, cache: cache)
        let second = ConnectedServicesModel(account: account, scope: scope, provider: provider, cache: cache)

        await first.load()
        await second.load()

        XCTAssertEqual(first.phase, .loaded(ConnectedServices(identifiers: ["spotify"])))
        XCTAssertEqual(second.phase, .loaded(ConnectedServices(identifiers: ["spotify"])))
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testExplicitRefreshRequestsCurrentServicesAgain() async {
        let account = Account(username: "listener", token: "token")
        let provider = ConnectedServicesFixtureProvider(results: [.success(["spotify"]), .success(["lastfm"])])
        let model = ConnectedServicesModel(account: account, provider: provider, cache: EntityDetailCache())

        await model.load()
        await model.refresh()

        XCTAssertEqual(model.phase, .loaded(ConnectedServices(identifiers: ["lastfm"])))
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testStaleServicesRemainVisibleWhenRefreshFails() async {
        let account = Account(username: "listener", token: "token")
        let cache = EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices>(timeToLive: -1)
        let scope = RequestGate.ReadScope.isolated()
        let saved = ConnectedServices(identifiers: ["spotify"])
        await cache.save(saved, for: .init(username: account.username, scope: scope))
        let model = ConnectedServicesModel(
            account: account,
            scope: scope,
            provider: ConnectedServicesFixtureProvider(results: [.failure]),
            cache: cache
        )

        await model.load()

        XCTAssertEqual(model.phase, .loaded(saved))
        XCTAssertEqual(model.refreshMessage, "Couldn’t refresh your connected services. Showing the last saved list.")
    }

    func testPublicAccountDoesNotInvokeTheProvider() async {
        let provider = ConnectedServicesFixtureProvider(results: [.success(["spotify"])])
        let model = ConnectedServicesModel(
            account: Account(username: "public-listener", token: ""),
            provider: provider,
            cache: EntityDetailCache()
        )

        await model.load()

        XCTAssertEqual(
            model.phase,
            .failed("Sign in to view the services linked to your ListenBrainz account.")
        )
        let callCount = await provider.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testAuthenticationFailureDoesNotKeepStaleServicesVisible() async {
        let account = Account(username: "listener", token: "token")
        let cache = EntityDetailCache<ConnectedServicesCacheKey, ConnectedServices>(timeToLive: -1)
        let scope = RequestGate.ReadScope.isolated()
        let cacheKey = ConnectedServicesCacheKey(username: account.username, scope: scope)
        await cache.save(ConnectedServices(identifiers: ["spotify"]), for: cacheKey)
        let model = ConnectedServicesModel(
            account: account,
            scope: scope,
            provider: AuthenticationFailureProvider(),
            cache: cache
        )

        await model.load()

        XCTAssertEqual(
            model.phase,
            .failed("Your ListenBrainz sign-in needs attention. Sign in again to view connected services.")
        )
        XCTAssertNil(model.refreshMessage)
        let cachedAfterFailure = await cache.value(for: cacheKey)
        XCTAssertNil(cachedAfterFailure)

        let followUpProvider = ConnectedServicesFixtureProvider(results: [.success(["lastfm"])])
        let followUp = ConnectedServicesModel(
            account: account,
            scope: scope,
            provider: followUpProvider,
            cache: cache
        )
        await followUp.load()
        XCTAssertEqual(followUp.phase, .loaded(ConnectedServices(identifiers: ["lastfm"])))
        let followUpCalls = await followUpProvider.callCount()
        XCTAssertEqual(followUpCalls, 1)
    }

    func testCancelledInitialLoadCanStartAgain() async {
        let account = Account(username: "listener", token: "token")
        let provider = CancellationAwareConnectedServicesProvider()
        let model = ConnectedServicesModel(
            account: account,
            provider: provider,
            cache: EntityDetailCache()
        )

        let firstLoad = Task { await model.load() }
        while await provider.callCount() == 0 { await Task.yield() }
        XCTAssertEqual(model.phase, .loading)

        model.cancel()
        firstLoad.cancel()
        await firstLoad.value
        await model.load()

        XCTAssertEqual(model.phase, .loaded(ConnectedServices(identifiers: ["spotify"])))
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 2)
    }
}

@MainActor
final class ConnectedServicesProviderTests: XCTestCase {
    func testEquivalentConcurrentOwnAccountReadsAreCoalesced() async throws {
        let transport = ConnectedServicesTransportFixture(response: ["spotify"])
        let provider = ListenBrainzConnectedServicesProvider(
            gate: RequestGate(minimumInterval: .zero),
            transport: { _ in try await transport.value() }
        )

        async let first = provider.connectedServices(username: "listener")
        async let second = provider.connectedServices(username: "listener")
        let loaded = try await [first, second]

        XCTAssertEqual(loaded, [ConnectedServices(identifiers: ["spotify"]), ConnectedServices(identifiers: ["spotify"])])
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }
}

private actor ConnectedServicesFixtureProvider: ConnectedServicesProviding {
    enum Result: Sendable { case success([String]), failure }
    private let results: [Result]
    private var calls = 0

    init(results: [Result]) { self.results = results }

    func connectedServices(username: String) async throws -> ConnectedServices {
        let index = calls
        calls += 1
        switch results.indices.contains(index) ? results[index] : results.last ?? .failure {
        case let .success(identifiers): return ConnectedServices(identifiers: identifiers)
        case .failure: throw ConnectedServicesFixtureError.failed
        }
    }

    func callCount() -> Int { calls }
}

private actor ConnectedServicesTransportFixture {
    private let response: [String]
    private var calls = 0

    init(response: [String]) { self.response = response }

    func value() async throws -> [String] {
        calls += 1
        try await ContinuousClock().sleep(for: .milliseconds(25))
        return response
    }

    func callCount() -> Int { calls }
}

private enum ConnectedServicesFixtureError: LocalizedError {
    case failed
    var errorDescription: String? { "Fixture request failed." }
}

private struct AuthenticationFailureProvider: ConnectedServicesProviding {
    func connectedServices(username: String) async throws -> ConnectedServices {
        throw LBError.invalidAuth
    }
}

private actor CancellationAwareConnectedServicesProvider: ConnectedServicesProviding {
    private var calls = 0

    func connectedServices(username: String) async throws -> ConnectedServices {
        calls += 1
        if calls == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        return ConnectedServices(identifiers: ["spotify"])
    }

    func callCount() -> Int { calls }
}
