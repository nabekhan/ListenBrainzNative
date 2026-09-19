import Foundation
import ListenBrainzKit

protocol YearInMusicProviding: Sendable {
    /// One aggregate request; `nil` means ListenBrainz has no usable report.
    func report(username: String, year: Int) async throws -> YearInMusicReport?
}

protocol YearInMusicTransport: Sendable {
    func yearInMusic(username: String, year: Int) async throws -> LBYearInMusic?
}

private struct LiveYearInMusicTransport: YearInMusicTransport {
    let client: LBClient

    func yearInMusic(username: String, year: Int) async throws -> LBYearInMusic? {
        try await client.stats.yearInMusic(user: username, year: year)
    }
}

struct ListenBrainzYearInMusicProvider: YearInMusicProviding {
    private let transport: any YearInMusicTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        transport = LiveYearInMusicTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        transport: some YearInMusicTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func report(username: String, year: Int) async throws -> YearInMusicReport? {
        do {
            let report = try await gate.read(for: .yearInMusic(readScope, user: username, year: year)) {
                let source = try await transport.yearInMusic(username: username, year: year)
                return source.flatMap { YearInMusicReport(source: $0, requestedYear: year) }
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
            return report
        } catch LBError.notFound, LBError.noContent {
            // A year-specific route can legitimately be absent.  A 200 with
            // empty data follows the same unavailable path in the mapper.
            return nil
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }
}
