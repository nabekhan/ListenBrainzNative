import Foundation
import ListenBrainzKit
import CryptoKit

struct ListenBrainzProvider: ListeningProvider {
    private let client: LBClient
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope
    private let deletionTransport: any ListenDeletionTransport

    init(token: String, gate: RequestGate = .shared) {
        self.client = LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        self.gate = gate
        readScope = .authenticated(token: token)
        deletionTransport = LiveListenDeletionTransport(client: client)
    }

    init(token: String, gate: RequestGate, deletionTransport: some ListenDeletionTransport) {
        let client = LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        )
        self.client = client
        self.gate = gate
        readScope = .authenticated(token: token)
        self.deletionTransport = deletionTransport
    }

    func validateToken() async throws -> String {
        try await read(.tokenValidation(readScope)) {
            let info = try await client.core.isTokenValid()
            guard info.valid, let username = info.userName, !username.isEmpty else {
                throw ProviderError.invalidToken
            }
            return username
        }
    }

    func recentListens(username: String, before: Date?, after: Date? = nil, count: Int) async throws -> [Listen] {
        let safeCount = min(max(count, 1), 100)
        return try await read(.historyRecent(readScope, user: username, before: before, after: after, count: safeCount)) {
            let result = try await client.core.userListens(
                username: username,
                latest: before,
                earliest: after,
                count: safeCount
            )
            return result.listens.map(Self.map)
        }
    }

    func playingNow(username: String) async throws -> Listen? {
        try await read(.playingNow(readScope, user: username)) {
            guard let value = try await client.core.userPlayingNow(username: username) else {
                return nil
            }
            return Listen(
                recording: Self.map(value.trackMetadata, msid: nil),
                listenedAt: .now,
                insertedAt: nil,
                isPlayingNow: value.playingNow
            )
        }
    }

    func listenCount(username: String) async throws -> Int {
        try await read(.listenCount(readScope, user: username)) { try await client.core.userListensCount(username: username) }
    }

    func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
        let safeCount = max(count, 1)
        return try await read(.topArtists(readScope, user: username, count: safeCount)) {
            let value = try await client.stats.topArtists(user: username, count: safeCount, range: .allTime)
            return value?.artists.map {
                RankedArtist(mbid: $0.mbid, name: $0.name, listenCount: $0.listenCount)
            } ?? []
        }
    }

    func topReleases(username: String, count: Int) async throws -> [RankedRelease] {
        let safeCount = max(count, 1)
        return try await read(.topReleases(readScope, user: username, count: safeCount)) {
            let value = try await client.stats.topReleases(user: username, count: safeCount, range: .allTime)
            return value?.releases.map {
                RankedRelease(
                    mbid: $0.releaseMbid,
                    name: $0.releaseName,
                    artistName: $0.artistName,
                    artistMBIDs: $0.artistMbids ?? [],
                    listenCount: $0.listenCount
                )
            } ?? []
        }
    }

    func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
        let safeCount = max(count, 1)
        return try await read(.topRecordings(readScope, user: username, count: safeCount)) {
            let value = try await client.stats.topRecordings(user: username, count: safeCount, range: .allTime)
            return value?.recordings.map {
                RankedRecording(
                    mbid: $0.recordingMbid,
                    releaseMBID: $0.releaseMbid,
                    title: $0.trackName,
                    artistName: $0.artistName,
                    artistMBIDs: $0.artistMbids ?? [],
                    releaseTitle: $0.releaseName,
                    listenCount: $0.listenCount
                )
            } ?? []
        }
    }

    func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
        let rangeName = Self.range(for: period).rawValue
        return try await read(.listeningActivity(readScope, user: username, period: rangeName)) {
            let result = try await client.stats.listenActivity(user: username, range: Self.range(for: period))
            guard let result else {
                return ListeningActivity(
                    period: period,
                    from: .distantPast,
                    to: .distantPast,
                    lastUpdated: .distantPast,
                    buckets: []
                )
            }
            return ListeningActivity(
                period: period,
                from: result.from,
                to: result.to,
                lastUpdated: Date(timeIntervalSince1970: TimeInterval(result.lastUpdated)),
                buckets: result.activity.map {
                    .init(label: $0.timeRange, from: $0.from, to: $0.to, listenCount: $0.listenCount)
                }
            )
        }
    }

    func dailyActivity(username: String, period: ListeningActivityPeriod) async throws -> DailyActivity? {
        let rangeName = Self.range(for: period).rawValue
        return try await read(.dailyActivity(readScope, user: username, period: rangeName)) {
            guard let result = try await client.stats.dailyActivity(user: username, range: Self.range(for: period)) else {
                return nil
            }
            return DailyActivity(
                period: period,
                from: result.from,
                to: result.to,
                lastUpdated: Date(timeIntervalSince1970: TimeInterval(result.lastUpdated)),
                dailyActivity: result.dailyActivity.mapValues { values in
                    values.map { .init(hour: $0.hour, listenCount: $0.listenCount) }
                }
            )
        }
    }

    func eraActivity(username: String, period: ListeningActivityPeriod) async throws -> EraActivity? {
        let rangeName = Self.range(for: period).rawValue
        return try await read(.eraActivity(readScope, user: username, period: rangeName)) {
            guard let result = try await client.stats.eraActivity(user: username, range: Self.range(for: period)) else {
                return nil
            }
            return EraActivity(
                period: period,
                from: result.from,
                to: result.to,
                lastUpdated: Date(timeIntervalSince1970: TimeInterval(result.lastUpdated)),
                years: result.eraActivity.map {
                    .init(year: $0.year, listenCount: $0.listenCount)
                }
            )
        }
    }

    func artistEvolutionActivity(
        username: String,
        period: ListeningActivityPeriod
    ) async throws -> ArtistEvolutionActivity? {
        let rangeName = Self.range(for: period).rawValue
        return try await read(.artistEvolution(readScope, user: username, period: rangeName)) {
            guard let result = try await client.stats.artistEvolutionActivity(
                user: username,
                range: Self.range(for: period)
            ) else {
                return nil
            }
            return ArtistEvolutionActivity(
                period: period,
                from: result.from,
                to: result.to,
                lastUpdated: Date(timeIntervalSince1970: TimeInterval(result.lastUpdated)),
                rows: result.artistEvolutionActivity.map {
                    .init(
                        timeUnit: $0.timeUnit,
                        artistMBID: $0.artistMBID.flatMap(UUID.init(uuidString:)),
                        artistName: $0.artistName,
                        listenCount: $0.listenCount
                    )
                }
            )
        }
    }

    func genreActivity(
        username: String,
        period: ListeningActivityPeriod
    ) async throws -> GenreActivity? {
        let rangeName = Self.range(for: period).rawValue
        return try await read(.genreActivity(readScope, user: username, period: rangeName)) {
            guard let result = try await client.stats.genreActivity(
                user: username,
                range: Self.range(for: period)
            ) else {
                return nil
            }
            return GenreActivity(
                period: period,
                from: result.from,
                to: result.to,
                lastUpdated: Date(timeIntervalSince1970: TimeInterval(result.lastUpdated)),
                rows: result.genreActivity.map {
                    .init(genre: $0.genre, hour: $0.hour, listenCount: $0.listenCount)
                }
            )
        }
    }

    func artistOrigins(username: String, period: ListeningActivityPeriod) async throws -> ArtistOrigins? {
        let rangeName = Self.range(for: period).rawValue
        return try await read(.artistOrigins(readScope, user: username, period: rangeName)) {
            guard let result = try await client.stats.artistMap(user: username, range: Self.range(for: period)) else {
                return nil
            }
            return ArtistOrigins(
                period: period,
                from: result.from,
                to: result.to,
                lastUpdated: Date(timeIntervalSince1970: TimeInterval(result.lastUpdated)),
                rows: result.artistMap.map {
                    .init(
                        countryCode: $0.country,
                        artistCount: $0.artistCount,
                        listenCount: $0.listenCount,
                        artists: $0.artists.map {
                            .init(
                                mbid: $0.artistMBID.flatMap(UUID.init(uuidString:)),
                                name: $0.artistName,
                                listenCount: $0.listenCount
                            )
                        }
                    )
                }
            )
        }
    }

    func artistActivity(username: String, period: ListeningActivityPeriod) async throws -> ArtistActivity? {
        let rangeName = Self.range(for: period).rawValue
        return try await read(.artistActivity(readScope, user: username, period: rangeName)) {
            guard let result = try await client.stats.artistActivity(user: username, range: Self.range(for: period)) else { return nil }
            return ArtistActivity(period: period, from: result.from, to: result.to,
                                  lastUpdated: Date(timeIntervalSince1970: TimeInterval(result.lastUpdated)),
                                  rows: result.artistActivity.map { artist in
                .init(creditedName: artist.name, canonicalName: artist.artistName,
                      artistMBID: artist.artistMBID.flatMap(UUID.init(uuidString:)), listenCount: artist.listenCount,
                      albums: artist.albums.map { .init(name: $0.name, releaseGroupMBID: $0.releaseGroupMBID.flatMap(UUID.init(uuidString:)), listenCount: $0.listenCount) })
            })
        }
    }

    func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] {
        let requestUser = scope == .forYou ? username : nil
        return try await read(.freshReleases(readScope, user: requestUser, scopeName: scope.rawValue)) {
            let result: LBFreshReleases?
            switch scope {
            case .forYou:
                result = try await client.freshReleases.personalized(user: username, days: 7)
            case .all:
                result = try await client.freshReleases.sitewide(days: 7)
            }
            let releases = result?.releases.enumerated().map { index, release in
                Self.map(release, sourcePosition: index)
            } ?? []
            return releases.sorted(by: Self.freshReleaseComesFirst)
        }
    }

    func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {
        if let mbid = recording.identity.mbid {
            try await perform {
                let score = LBScore(rawValue: feedback.rawValue) ?? .none
                try await client.recordings.submitFeedback(
                    mbid: mbid,
                    msid: recording.identity.msid,
                    score: score
                )
            }
        } else if let msid = recording.identity.msid {
            try await perform {
                let score = LBScore(rawValue: feedback.rawValue) ?? .none
                try await client.recordings.submitFeedback(msid: msid, mbid: nil, score: score)
            }
        } else {
            throw ProviderError.feedbackNeedsIdentifier
        }
    }

    func deleteListen(listenedAt: Date, recordingMSID: UUID) async throws {
        let attempt = ListenDeletionAttemptState()
        do {
            try await gate.perform {
                await attempt.markTransportStarted()
                try await deletionTransport.deleteListen(listenedAt: listenedAt, recordingMSID: recordingMSID)
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch let error as LBError {
            switch error {
            case .invalidAuth, .noToken:
                throw ProviderError.invalidToken
            case .invalidJSON, .invalidParam, .badRequest:
                // These response-backed validation/authentication failures are
                // definite pre-acceptance outcomes and remain retryable.
                throw ProviderError.deleteListenRejected
            case .invalidResponse, .noContent, .unknownError, .notFound, .forbidden:
                throw ProviderError.deleteListenOutcomeUnknown
            case .rateLimited:
                // RequestGate's deferral closure leaves this branch only if a
                // nonstandard client returned it outside the normal path.
                throw error
            }
        } catch let error as ProviderError {
            // `perform` maps response-backed throttling to this app-facing
            // error. It is likewise safe to retain the listen and let the
            // user decide whether to try again later.
            throw error
        } catch is CancellationError {
            guard await attempt.didStartTransport else { throw CancellationError() }
            throw ProviderError.deleteListenOutcomeUnknown
        } catch {
            // URLSession failures and cancellation can happen after the POST
            // leaves the device. Never turn that ambiguity into a replay.
            throw ProviderError.deleteListenOutcomeUnknown
        }
    }

    private func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await gate.perform(operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            let delay = max(resetIn, 1)
            throw ProviderError.rateLimited(retryAfterSeconds: delay)
        }
    }

    private func read<Result: Sendable>(
        _ key: RequestGate.ReadKey,
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        do {
            return try await gate.read(for: key, operation) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        }
    }

    private static func map(_ listen: LBListen) -> Listen {
        Listen(
            recording: map(listen.trackMetadata, msid: listen.recordingMsid),
            listenedAt: listen.listenedAt,
            insertedAt: listen.insertedAt,
            isPlayingNow: false
        )
    }

    static func range(for period: ListeningActivityPeriod) -> LBStatRange {
        switch period {
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        case .thisYear: .thisYear
        case .lastWeek: .week
        case .lastMonth: .month
        case .lastYear: .year
        case .allTime: .allTime
        }
    }

    static func freshReleaseComesFirst(_ lhs: FreshRelease, _ rhs: FreshRelease) -> Bool {
        switch (lhs.releaseDateValue, rhs.releaseDateValue) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.sourcePosition < rhs.sourcePosition
        }
    }

    static func map(_ metadata: LBTrackMetadata, msid: UUID?) -> Recording {
        let mapped = metadata.mbidMapping
        let additional = metadata.additionalInfo
        return Recording(
            identity: .init(mbid: mapped?.recordingMbid ?? additional?.recordingMbid, msid: msid),
            title: mapped?.recordingName ?? metadata.track,
            artistName: metadata.artist,
            artistMBIDs: mapped?.artistMbids ?? additional?.artistMbids ?? [],
            releaseTitle: metadata.release,
            releaseMBID: mapped?.releaseMbid ?? additional?.releaseMbid,
            releaseGroupMBID: mapped?.releaseGroupMbid ?? additional?.releaseGroupMbid,
            artworkReleaseMBID: mapped?.caaReleaseMbid ?? mapped?.releaseMbid ?? additional?.releaseMbid,
            durationMilliseconds: additional?.durationMs ?? additional?.duration.map { $0 * 1_000 },
            source: additional?.musicServiceName
                ?? additional?.musicService
                ?? additional?.submissionClient
                ?? additional?.mediaPlayer
        )
    }

    private static func map(_ release: LBFreshReleases.Release, sourcePosition: Int) -> FreshRelease {
        FreshRelease(
            releaseMBID: release.releaseMBID.flatMap(UUID.init(uuidString:)),
            releaseGroupMBID: release.releaseGroupMBID.flatMap(UUID.init(uuidString:)),
            title: release.releaseName,
            artistName: release.artistCreditName,
            artistMBIDs: release.artistMBIDs.compactMap(UUID.init(uuidString:)),
            releaseDate: release.releaseDate,
            primaryType: release.primaryType,
            secondaryType: release.secondaryType,
            tags: release.tags,
            confidence: release.confidence,
            listenCount: release.listenCount,
            artworkReleaseMBID: (release.caaReleaseMBID ?? release.releaseMBID).flatMap(UUID.init(uuidString:)),
            sourcePosition: sourcePosition
        )
    }
}

protocol ListenDeletionTransport: Sendable {
    func deleteListen(listenedAt: Date, recordingMSID: UUID) async throws
}

private struct LiveListenDeletionTransport: ListenDeletionTransport {
    let client: LBClient

    func deleteListen(listenedAt: Date, recordingMSID: UUID) async throws {
        try await client.core.deleteListen(listenedAt: listenedAt, recordingMsid: recordingMSID)
    }
}

private actor ListenDeletionAttemptState {
    private(set) var didStartTransport = false

    func markTransportStarted() { didStartTransport = true }
}

actor RequestGate {
    static let shared = RequestGate()

    /// An opaque process-local account boundary. Its digest is never persisted
    /// or emitted in telemetry, and a new process receives a new key.
    struct ReadScope: Hashable, Sendable {
        private static let processKey = SymmetricKey(size: .bits256)
        private let digest: Data

        private init(digest: Data) {
            self.digest = digest
        }

        static var anonymous: Self { .init(digest: Data()) }

        static func authenticated(token: String) -> Self {
            let digest = HMAC<SHA256>.authenticationCode(
                for: Data(token.utf8),
                using: processKey
            )
            return .init(digest: Data(digest))
        }

        /// A unique boundary for injected transports that do not represent a
        /// real credential. This prevents unrelated fixtures/adapters from
        /// coalescing merely because neither has a token.
        static func isolated() -> Self {
            let digest = HMAC<SHA256>.authenticationCode(
                for: Data(UUID().uuidString.utf8),
                using: processKey
            )
            return .init(digest: Data(digest))
        }
    }

    enum ReadFeature: String, Sendable {
        case coreTokenValidation
        case historyRecent
        case historyPlayingNow
        case historyListenCount
        case profileSummary
        case statsTopArtists
        case statsTopReleases
        case statsTopRecordings
        case statsListeningActivity
        case statsDailyActivity
        case statsEraActivity
        case statsArtistEvolution
        case statsGenreActivity
        case statsArtistOrigins
        case statsArtistActivity
        case searchResults
        case discoveryFreshReleases
        case feedPage
        case playlistList
        case playlistDetail
        case metadataArtist
        case metadataRelease
        case metadataRecording
        case recommendationsMetadata
        case artworkYearInMusic
        case radioPlaylist
        case radioMetadata
        case socialUserSearch
        case socialFollowers
        case socialFollowing
        case socialSimilarUsers
        case socialCompatibility
        case recommendationsRecordings
        case recommendationsPlaylists
        case recommendationsFeedback
        case popularitySummary
        case yearInMusicSummary
        case pinsCurrent
        case pinsHistory
        case profilePlaylists
        case recordingShareFollowers
        case searchListenBrainzUsers
        case searchListenBrainzPlaylists
    }

    struct ReadKey: Hashable, Sendable {
        /// A stable caller-supplied identity for an endpoint-specific read.
        /// `feature` is intentionally the only part exposed by diagnostics;
        /// identity components may include request-specific values and must
        /// never be logged.
        private let scope: ReadScope
        let feature: ReadFeature
        private let identityComponents: [String]

        init(scope: ReadScope, feature: ReadFeature, identityComponents: [String]) {
            self.scope = scope
            self.feature = feature
            self.identityComponents = identityComponents
        }

        // Endpoint-specific factories keep sensitive request identity out of
        // call sites and make coalescing match the exact shaped request.
        private static func endpoint(_ scope: ReadScope, _ feature: ReadFeature, _ components: [String]) -> Self {
            .init(scope: scope, feature: feature, identityComponents: components)
        }
        static func tokenValidation(_ scope: ReadScope) -> Self { endpoint(scope, .coreTokenValidation, []) }
        static func playingNow(_ scope: ReadScope, user: String) -> Self { endpoint(scope, .historyPlayingNow, [userID(user)]) }
        static func listenCount(_ scope: ReadScope, user: String) -> Self { endpoint(scope, .historyListenCount, [userID(user)]) }
        static func topArtists(_ scope: ReadScope, user: String, count: Int) -> Self { endpoint(scope, .statsTopArtists, [userID(user), String(count), "all-time"]) }
        static func topReleases(_ scope: ReadScope, user: String, count: Int) -> Self { endpoint(scope, .statsTopReleases, [userID(user), String(count), "all-time"]) }
        static func topRecordings(_ scope: ReadScope, user: String, count: Int) -> Self { endpoint(scope, .statsTopRecordings, [userID(user), String(count), "all-time"]) }
        static func listeningActivity(_ scope: ReadScope, user: String, period: String) -> Self { endpoint(scope, .statsListeningActivity, [userID(user), period]) }
        static func dailyActivity(_ scope: ReadScope, user: String, period: String) -> Self { endpoint(scope, .statsDailyActivity, [userID(user), period]) }
        static func eraActivity(_ scope: ReadScope, user: String, period: String) -> Self { endpoint(scope, .statsEraActivity, [userID(user), period]) }
        static func artistEvolution(_ scope: ReadScope, user: String, period: String) -> Self { endpoint(scope, .statsArtistEvolution, [userID(user), period]) }
        static func genreActivity(_ scope: ReadScope, user: String, period: String) -> Self { endpoint(scope, .statsGenreActivity, [userID(user), period]) }
        static func artistOrigins(_ scope: ReadScope, user: String, period: String) -> Self { endpoint(scope, .statsArtistOrigins, [userID(user), period]) }
        static func artistActivity(_ scope: ReadScope, user: String, period: String) -> Self { endpoint(scope, .statsArtistActivity, [userID(user), period]) }
        static func freshReleases(_ scope: ReadScope, user: String?, scopeName: String) -> Self {
            endpoint(
                scope,
                .discoveryFreshReleases,
                [scopeName, "7"] + (user.map { [userID($0)] } ?? [])
            )
        }
        static func currentPin(_ scope: ReadScope, user: String) -> Self { endpoint(scope, .pinsCurrent, [userID(user)]) }
        static func recommendations(_ scope: ReadScope, user: String, offset: Int, count: Int) -> Self { endpoint(scope, .recommendationsRecordings, [userID(user), String(offset), String(count)]) }
        static func recommendationPlaylists(_ scope: ReadScope, user: String) -> Self { endpoint(scope, .recommendationsPlaylists, [userID(user)]) }
        static func radioPlaylist(_ scope: ReadScope, prompt: String, mode: String) -> Self { endpoint(scope, .radioPlaylist, [prompt, mode]) }
        static func socialFollowers(_ scope: ReadScope, user: String) -> Self { endpoint(scope, .socialFollowers, [userID(user)]) }
        static func socialFollowing(_ scope: ReadScope, user: String) -> Self { endpoint(scope, .socialFollowing, [userID(user)]) }
        static func similarUsers(_ scope: ReadScope, user: String) -> Self { endpoint(scope, .socialSimilarUsers, [userID(user)]) }
        static func recordingShareFollowers(_ scope: ReadScope, user: String) -> Self { endpoint(scope, .recordingShareFollowers, [userID(user)]) }
        static func compatibility(_ scope: ReadScope, viewer: String, user: String) -> Self { endpoint(scope, .socialCompatibility, [userID(viewer), userID(user)]) }
        static func yearInMusic(_ scope: ReadScope, user: String, year: Int) -> Self { endpoint(scope, .yearInMusicSummary, [userID(user), String(year)]) }
        static func searchUsers(_ scope: ReadScope, query: String) -> Self { endpoint(scope, .searchListenBrainzUsers, [query]) }
        static func searchPlaylists(_ scope: ReadScope, query: String, count: Int) -> Self { endpoint(scope, .searchListenBrainzPlaylists, [query, String(count)]) }
        static func historyRecent(_ scope: ReadScope, user: String, before: Date?, after: Date?, count: Int) -> Self { endpoint(scope, .historyRecent, [userID(user), epoch(before), epoch(after), String(count)]) }
        static func feedPage(_ scope: ReadScope, user: String, mode: String, before: Date?, minimum: Date?, count: Int) -> Self { endpoint(scope, .feedPage, [userID(user), mode, epoch(before), epoch(minimum), String(count)]) }
        static func pinHistory(_ scope: ReadScope, user: String, count: Int, offset: Int) -> Self { endpoint(scope, .pinsHistory, [userID(user), String(count), String(offset)]) }
        static func profilePlaylists(_ scope: ReadScope, user: String, category: String, offset: Int, count: Int) -> Self { endpoint(scope, .profilePlaylists, [userID(user), category, String(offset), String(count)]) }
        static func releaseGroup(_ scope: ReadScope, mbid: UUID) -> Self { endpoint(scope, .metadataRelease, [uuid(mbid), "artist", "tag"]) }
        static func playlistDetail(_ scope: ReadScope, mbid: UUID) -> Self { endpoint(scope, .playlistDetail, [uuid(mbid)]) }
        static func popularity(_ scope: ReadScope, kind: String, mbid: UUID) -> Self { endpoint(scope, .popularitySummary, [kind, uuid(mbid)]) }
        static func radioMetadata(_ scope: ReadScope, mbids: [UUID]) -> Self { endpoint(scope, .radioMetadata, mbids.map(uuid)) }
        static func recommendationMetadata(_ scope: ReadScope, mbids: [UUID]) -> Self { endpoint(scope, .recommendationsMetadata, mbids.map(uuid)) }
        static func recommendationFeedback(_ scope: ReadScope, user: String, mbids: [UUID]) -> Self { endpoint(scope, .recommendationsFeedback, [userID(user)] + mbids.map(uuid)) }
        static func yearInMusicArtwork(_ scope: ReadScope, user: String, year: Int, variant: String, anonymous: Bool?) -> Self { endpoint(scope, .artworkYearInMusic, [userID(user), String(year), variant, anonymous.map(String.init) ?? "nil"]) }
        private static func uuid(_ id: UUID) -> String { id.uuidString.lowercased() }
        // Usernames stay byte-for-byte aligned with the value sent by the
        // provider. Normalizing only the key could merge distinct wire URLs.
        private static func userID(_ user: String) -> String { user }
        private static func epoch(_ date: Date?) -> String { date.map { String(Int($0.timeIntervalSince1970)) } ?? "nil" }
    }

    enum ReadError: Swift.Error, Sendable {
        /// The same read identity was requested with incompatible result
        /// types. Do not cast or share the value in this case.
        case incompatibleReadResultType
    }

    private enum ReadLifecycle: String, Sendable {
        case started
        case coalesced
        case finished
        case failed
        case cancelled
    }

    #if DEBUG
    struct ReadTelemetry: Sendable, Equatable {
        /// A telemetry-safe feature label supplied by the caller. Read-key
        /// identity components, tokens, payloads, and parameters are omitted.
        let feature: ReadFeature
        let lifecycle: String
        let coalescedWaiterCount: Int
        let inFlightReadCount: Int
    }
    #endif

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct ReadFlight {
        let id: UUID
        let resultType: ObjectIdentifier
        let task: Task<Void, Never>
        let feature: ReadFeature
        var waiters: [UUID: CheckedContinuation<any Sendable, any Swift.Error>]
    }

    private struct ReadSlotWaiter {
        let flightID: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct ReadWaiterIdentity: Hashable {
        let key: ReadKey
        let flightID: UUID
        let waiterID: UUID
    }

    private struct DrainingWaiterIdentity: Hashable {
        let flightID: UUID
        let waiterID: UUID
    }

    private let minimumInterval: Duration
    private var nextRequestAt = ContinuousClock.now
    private var deferredUntil = ContinuousClock.now
    private var requestInFlight = false
    private var waiters: [Waiter] = []
    private let maximumConcurrentReads: Int
    private var readFlights: [ReadKey: ReadFlight] = [:]
    private var activeReadIDs: Set<UUID> = []
    private var queuedReadWaiters: [ReadSlotWaiter] = []
    private var preCancelledReadWaiters: Set<ReadWaiterIdentity> = []
    private var drainingWaiters: [UUID: [UUID: CheckedContinuation<Void, any Swift.Error>]] = [:]
    private var preCancelledDrainingWaiters: Set<DrainingWaiterIdentity> = []

    #if DEBUG
    private var readTelemetry: [ReadTelemetry] = []
    private let maximumTelemetryEventCount = 128
    #endif

    init(minimumInterval: Duration = .seconds(1), maximumConcurrentReads: Int = 2) {
        self.minimumInterval = minimumInterval
        self.maximumConcurrentReads = max(1, maximumConcurrentReads)
    }

    func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result,
        deferralForError: @escaping @Sendable (any Error) -> Duration? = { _ in nil }
    ) async throws -> Result {
        try await acquire()
        var operationStarted = false

        do {
            try await waitUntilAllowed()
            try Task.checkCancellation()
            operationStarted = true
            let result = try await operation()
            finishRequest(operationStarted: operationStarted)
            return result
        } catch {
            if let delay = deferralForError(error) {
                applyDeferral(for: delay)
            }
            finishRequest(operationStarted: operationStarted)
            throw error
        }
    }

    func deferRequests(for delay: Duration) {
        applyDeferral(for: delay)
    }

    /// Runs a read in the bounded, coalescing lane. This does not retry a
    /// failed operation. Server deferrals are shared with `perform`, so a
    /// read-side 429 also delays a following mutation.
    func read<Result: Sendable>(
        for key: ReadKey,
        _ operation: @escaping @Sendable () async throws -> Result,
        deferralForError: @escaping @Sendable (any Swift.Error) -> Duration? = { _ in nil }
    ) async throws -> Result {
        try Task.checkCancellation()
        let requestedType = ObjectIdentifier(Result.self)
        let flight: ReadFlight

        if let existing = readFlights[key] {
            if existing.waiters.isEmpty {
                // A cancelled final waiter leaves the transport draining. Its
                // key remains reserved until termination so a replacement
                // caller cannot overlap an equivalent request.
                try await waitForDrainingFlight(key: key, flightID: existing.id)
                return try await read(for: key, operation, deferralForError: deferralForError)
            }
            guard existing.resultType == requestedType else {
                throw ReadError.incompatibleReadResultType
            }
            recordReadTelemetry(
                feature: existing.feature,
                lifecycle: .coalesced,
                coalescedWaiterCount: existing.waiters.count
            )
            flight = existing
        } else {
            let flightID = UUID()
            let task = Task {
                await self.executeRead(
                    key: key,
                    flightID: flightID,
                    operation: operation,
                    deferralForError: deferralForError
                )
            }
            let created = ReadFlight(
                id: flightID,
                resultType: requestedType,
                task: task,
                feature: key.feature,
                waiters: [:]
            )
            readFlights[key] = created
            flight = created
        }

        do {
            let waiterID = UUID()
            let value = try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    registerReadWaiter(waiterID, for: key, flightID: flight.id, continuation: continuation)
                }
            }, onCancel: {
                Task { await self.cancelReadWaiter(waiterID, for: key, flightID: flight.id) }
            })
            try Task.checkCancellation()
            guard let typedValue = value as? Result else {
                throw ReadError.incompatibleReadResultType
            }
            return typedValue
        } catch is CancellationError {
            throw CancellationError()
        }
    }

    #if DEBUG
    func queuedRequestCountForTesting() -> Int { waiters.count }
    func readTelemetryForTesting() -> [ReadTelemetry] { readTelemetry }
    func activeReadCountForTesting() -> Int { activeReadIDs.count }
    func queuedReadCountForTesting() -> Int { queuedReadWaiters.count }
    func readWaiterCountForTesting(_ key: ReadKey) -> Int {
        readFlights[key]?.waiters.count ?? 0
    }
    func isReadDrainingForTesting(_ key: ReadKey) -> Bool {
        readFlights[key]?.waiters.isEmpty == true
    }
    func drainingWaiterCountForTesting(_ key: ReadKey) -> Int {
        guard let flightID = readFlights[key]?.id else { return 0 }
        return drainingWaiters[flightID]?.count ?? 0
    }
    #endif

    private func acquire() async throws {
        try Task.checkCancellation()
        guard requestInFlight else {
            requestInFlight = true
            return
        }

        let id = UUID()
        let ownershipGranted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
        guard ownershipGranted else { throw CancellationError() }
    }

    private func waitUntilAllowed() async throws {
        let clock = ContinuousClock()
        while true {
            let now = clock.now
            let allowedTime = max(nextRequestAt, deferredUntil)
            if now < allowedTime {
                try await clock.sleep(until: allowedTime)
            }

            // A response on another task may extend the server delay while this
            // owner is asleep. Re-read shared state before beginning the call.
            if clock.now >= max(nextRequestAt, deferredUntil) {
                return
            }
        }
    }

    private func waitUntilReadAllowed() async throws {
        let clock = ContinuousClock()
        while true {
            let now = clock.now
            if now < deferredUntil {
                try await clock.sleep(until: deferredUntil)
            }
            if clock.now >= deferredUntil { return }
        }
    }

    private func applyDeferral(for delay: Duration) {
        let deferredTime = ContinuousClock.now.advanced(by: delay)
        deferredUntil = max(deferredUntil, deferredTime)
    }

    private func finishRequest(operationStarted: Bool) {
        if operationStarted {
            nextRequestAt = max(
                nextRequestAt,
                ContinuousClock.now.advanced(by: minimumInterval)
            )
        }

        if waiters.isEmpty {
            requestInFlight = false
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    private func executeRead<Result: Sendable>(
        key: ReadKey,
        flightID: UUID,
        operation: @escaping @Sendable () async throws -> Result,
        deferralForError: @escaping @Sendable (any Swift.Error) -> Duration?
    ) async {
        do {
            guard try await acquireReadSlot(for: flightID) else { throw CancellationError() }
            try await waitUntilReadAllowed()
            try Task.checkCancellation()
            recordReadTelemetry(feature: key.feature, lifecycle: .started)
            let result = try await operation()
            completeRead(for: key, flightID: flightID, result: .success(result), lifecycle: .finished)
        } catch {
            if let delay = deferralForError(error) {
                applyDeferral(for: delay)
            }
            completeRead(
                for: key,
                flightID: flightID,
                result: .failure(error),
                lifecycle: error is CancellationError ? .cancelled : .failed
            )
        }
    }

    private func acquireReadSlot(for flightID: UUID) async throws -> Bool {
        try Task.checkCancellation()
        if activeReadIDs.count < maximumConcurrentReads {
            activeReadIDs.insert(flightID)
            return true
        }

        let admitted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queuedReadWaiters.append(.init(flightID: flightID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelQueuedReadSlot(for: flightID) }
        }
        return admitted
    }

    private func completeRead(
        for key: ReadKey,
        flightID: UUID,
        result: Result<any Sendable, any Swift.Error>,
        lifecycle: ReadLifecycle
    ) {
        guard let flight = readFlights[key], flight.id == flightID else {
            releaseReadSlot(for: flightID)
            return
        }
        readFlights.removeValue(forKey: key)
        preCancelledReadWaiters = preCancelledReadWaiters.filter {
            !($0.key == key && $0.flightID == flightID)
        }
        releaseReadSlot(for: flightID)
        recordReadTelemetry(feature: flight.feature, lifecycle: lifecycle)
        for continuation in flight.waiters.values {
            switch result {
            case let .success(value): continuation.resume(returning: value)
            case let .failure(error): continuation.resume(throwing: error)
            }
        }
        let drainContinuations = drainingWaiters.removeValue(forKey: flightID).map { Array($0.values) } ?? []
        preCancelledDrainingWaiters = preCancelledDrainingWaiters.filter { $0.flightID != flightID }
        for continuation in drainContinuations { continuation.resume() }
    }

    private func releaseReadSlot(for flightID: UUID) {
        guard activeReadIDs.remove(flightID) != nil else { return }
        while !queuedReadWaiters.isEmpty, activeReadIDs.count < maximumConcurrentReads {
            let waiter = queuedReadWaiters.removeFirst()
            activeReadIDs.insert(waiter.flightID)
            waiter.continuation.resume(returning: true)
        }
    }

    private func cancelQueuedReadSlot(for flightID: UUID) {
        guard let index = queuedReadWaiters.firstIndex(where: { $0.flightID == flightID }) else { return }
        let waiter = queuedReadWaiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func registerReadWaiter(
        _ waiterID: UUID,
        for key: ReadKey,
        flightID: UUID,
        continuation: CheckedContinuation<any Sendable, any Swift.Error>
    ) {
        guard var flight = readFlights[key], flight.id == flightID else {
            continuation.resume(throwing: CancellationError())
            return
        }
        let identity = ReadWaiterIdentity(key: key, flightID: flightID, waiterID: waiterID)
        if preCancelledReadWaiters.remove(identity) != nil {
            continuation.resume(throwing: CancellationError())
            if flight.waiters.isEmpty {
                readFlights[key] = flight
                recordReadTelemetry(feature: flight.feature, lifecycle: .cancelled)
                flight.task.cancel()
            }
            return
        }
        flight.waiters[waiterID] = continuation
        readFlights[key] = flight
    }

    private func cancelReadWaiter(_ waiterID: UUID, for key: ReadKey, flightID: UUID) {
        guard var flight = readFlights[key], flight.id == flightID else { return }
        guard let continuation = flight.waiters.removeValue(forKey: waiterID) else {
            preCancelledReadWaiters.insert(.init(key: key, flightID: flightID, waiterID: waiterID))
            return
        }
        continuation.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            // Keep a tombstone until the cancelled transport actually exits;
            // otherwise a new equal key could start a duplicate transport.
            readFlights[key] = flight
            recordReadTelemetry(feature: flight.feature, lifecycle: .cancelled)
            flight.task.cancel()
        } else {
            readFlights[key] = flight
        }
    }

    private func waitForDrainingFlight(key: ReadKey, flightID: UUID) async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard readFlights[key]?.id == flightID else {
                    continuation.resume()
                    return
                }
                let identity = DrainingWaiterIdentity(flightID: flightID, waiterID: waiterID)
                if preCancelledDrainingWaiters.remove(identity) != nil {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                drainingWaiters[flightID, default: [:]][waiterID] = continuation
            }
        }, onCancel: {
            Task { await self.cancelDrainingWaiter(waiterID, key: key, flightID: flightID) }
        })
    }

    private func cancelDrainingWaiter(_ waiterID: UUID, key: ReadKey, flightID: UUID) {
        guard readFlights[key]?.id == flightID else { return }
        guard let continuation = drainingWaiters[flightID]?.removeValue(forKey: waiterID) else {
            preCancelledDrainingWaiters.insert(.init(flightID: flightID, waiterID: waiterID))
            return
        }
        if drainingWaiters[flightID]?.isEmpty == true {
            drainingWaiters.removeValue(forKey: flightID)
        }
        continuation.resume(throwing: CancellationError())
    }

    private func recordReadTelemetry(
        feature: ReadFeature,
        lifecycle: ReadLifecycle,
        coalescedWaiterCount: Int = 0
    ) {
        #if DEBUG
        readTelemetry.append(
            .init(
                feature: feature,
                lifecycle: lifecycle.rawValue,
                coalescedWaiterCount: coalescedWaiterCount,
                inFlightReadCount: activeReadIDs.count
            )
        )
        if readTelemetry.count > maximumTelemetryEventCount {
            readTelemetry.removeFirst(readTelemetry.count - maximumTelemetryEventCount)
        }
        #endif
    }
}
