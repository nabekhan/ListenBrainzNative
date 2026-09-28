import Foundation
import ListenBrainzKit

protocol CommunityChartsProviding: Sendable {
    func page(
        query: CommunityChartQuery,
        offset: Int,
        limit: Int
    ) async throws -> CommunityChartPage
}

struct CommunityChartTransportPage: Sendable {
    let items: [CommunityChartItem]
    let rawResultCount: Int
    let requestedCount: Int?
    let offset: Int?
    let range: String?
    let totalResultCount: Int?
    let lastUpdated: Date?
    let isNoContent: Bool

    static func noContent() -> Self {
        .init(
            items: [],
            rawResultCount: 0,
            requestedCount: nil,
            offset: nil,
            range: nil,
            totalResultCount: 0,
            lastUpdated: nil,
            isNoContent: true
        )
    }
}

protocol CommunityChartsTransport: Sendable {
    func page(
        kind: CommunityChartKind,
        range: LBStatRange,
        offset: Int,
        count: Int
    ) async throws -> CommunityChartTransportPage
}

struct ListenBrainzCommunityChartsProvider: CommunityChartsProviding {
    static let maximumPageSize = 25

    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope
    private let transport: any CommunityChartsTransport

    init(gate: RequestGate = .shared) {
        self.gate = gate
        readScope = .anonymous
        transport = LiveCommunityChartsTransport()
    }

    init(
        gate: RequestGate,
        transport: some CommunityChartsTransport
    ) {
        self.gate = gate
        readScope = .isolated()
        self.transport = transport
    }

    func page(
        query: CommunityChartQuery,
        offset: Int,
        limit: Int
    ) async throws -> CommunityChartPage {
        let effectiveOffset = max(offset, 0)
        let effectiveLimit = min(max(limit, 1), Self.maximumPageSize)
        let range = ListenBrainzProvider.range(for: query.period)
        let response = try await read(
            .communityCharts(
                readScope,
                kind: query.kind.rawValue,
                range: range.rawValue,
                offset: effectiveOffset,
                count: effectiveLimit
            )
        ) {
            try await transport.page(
                kind: query.kind,
                range: range,
                offset: effectiveOffset,
                count: effectiveLimit
            )
        }

        if response.isNoContent {
            return CommunityChartPage(
                items: [],
                offset: effectiveOffset,
                rawResultCount: 0,
                totalResultCount: 0,
                lastUpdated: nil,
                allowsPagination: false
            )
        }

        if let requestedCount = response.requestedCount,
           requestedCount != effectiveLimit {
            throw CommunityChartsProviderError.invalidResponse
        }
        if let returnedOffset = response.offset,
           returnedOffset != effectiveOffset {
            throw CommunityChartsProviderError.invalidResponse
        }
        if let returnedRange = response.range,
           returnedRange != range.rawValue {
            throw CommunityChartsProviderError.invalidResponse
        }

        guard response.rawResultCount >= response.items.count,
              response.rawResultCount <= effectiveLimit,
              response.items.allSatisfy({ $0.listenCount >= 0 }),
              response.totalResultCount.map({ $0 >= 0 }) != false
        else {
            throw CommunityChartsProviderError.invalidResponse
        }

        let hasCompletePageMetadata = response.requestedCount != nil
            && response.offset != nil
            && response.range != nil
            && response.totalResultCount != nil
        if hasCompletePageMetadata,
           let totalResultCount = response.totalResultCount {
            let (pageEnd, overflowed) = effectiveOffset.addingReportingOverflow(response.rawResultCount)
            guard !overflowed,
                  pageEnd <= totalResultCount,
                  response.rawResultCount > 0 || effectiveOffset >= totalResultCount
            else { throw CommunityChartsProviderError.invalidResponse }
        }

        return CommunityChartPage(
            items: response.items,
            offset: effectiveOffset,
            rawResultCount: response.rawResultCount,
            totalResultCount: response.totalResultCount,
            lastUpdated: response.lastUpdated,
            allowsPagination: hasCompletePageMetadata
        )
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
}

enum CommunityChartsProviderError: LocalizedError, Sendable {
    case invalidResponse

    var errorDescription: String? {
        String(localized: "ListenBrainz returned an unexpected community ranking.")
    }
}

private struct LiveCommunityChartsTransport: CommunityChartsTransport {
    private let client = LBClient(
        token: "",
        userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
    )

    func page(
        kind: CommunityChartKind,
        range: LBStatRange,
        offset: Int,
        count: Int
    ) async throws -> CommunityChartTransportPage {
        switch kind {
        case .artists:
            guard let value = try await client.stats.topArtistsSitewide(
                count: count,
                offset: offset,
                range: range
            ) else { return .noContent() }
            return .init(
                items: value.artists.map {
                    .artist(.init(
                        mbid: $0.mbid,
                        name: Self.nonempty($0.name) ?? String(localized: "Unknown artist"),
                        listenCount: $0.listenCount
                    ))
                },
                rawResultCount: value.artists.count,
                requestedCount: value.requestedCount,
                offset: value.offset,
                range: value.range,
                totalResultCount: value.totalArtistCount,
                lastUpdated: value.lastUpdated,
                isNoContent: false
            )

        case .releaseGroups:
            guard let value = try await client.stats.topReleaseGroupsSitewide(
                count: count,
                offset: offset,
                range: range
            ) else { return .noContent() }
            return .init(
                items: value.releaseGroups.map {
                    .releaseGroup(.init(
                        mbid: $0.releaseGroupMbid,
                        name: Self.nonempty($0.releaseGroupName) ?? String(localized: "Unknown album"),
                        artistName: Self.nonempty($0.artistName) ?? String(localized: "Unknown artist"),
                        artistMBIDs: $0.artistMbids ?? [],
                        listenCount: $0.listenCount
                    ))
                },
                rawResultCount: value.releaseGroups.count,
                requestedCount: value.requestedCount,
                offset: value.offset,
                range: value.range,
                totalResultCount: value.totalReleaseGroupCount,
                lastUpdated: value.lastUpdated,
                isNoContent: false
            )

        case .recordings:
            guard let value = try await client.stats.topRecordingsSitewide(
                count: count,
                offset: offset,
                range: range
            ) else { return .noContent() }
            return .init(
                items: value.recordings.map {
                    .recording(.init(
                        mbid: $0.recordingMbid,
                        releaseMBID: $0.releaseMbid,
                        title: Self.nonempty($0.trackName) ?? String(localized: "Unknown track"),
                        artistName: Self.nonempty($0.artistName) ?? String(localized: "Unknown artist"),
                        artistMBIDs: $0.artistMbids ?? [],
                        releaseTitle: Self.nonempty($0.releaseName),
                        listenCount: $0.listenCount
                    ))
                },
                rawResultCount: value.recordings.count,
                requestedCount: value.requestedCount,
                offset: value.offset,
                range: value.range,
                totalResultCount: value.totalRecordingCount,
                lastUpdated: value.lastUpdated,
                isNoContent: false
            )
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
