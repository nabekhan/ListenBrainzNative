import Foundation
import ListenBrainzKit

protocol LinkListensProviding: Sendable {
    func unmatchedListens(username: String) async throws -> LinkListensPage
}

struct LinkListensPage: Sendable, Hashable {
    let listens: [Listen]
    let totalDataCount: Int
    let lastUpdated: Date?
    let sourceRowCounts: [UUID: Int]

    init(
        listens: [Listen],
        totalDataCount: Int,
        lastUpdated: Date?,
        sourceRowCounts: [UUID: Int]? = nil
    ) {
        self.listens = listens
        self.totalDataCount = totalDataCount
        self.lastUpdated = lastUpdated
        self.sourceRowCounts = sourceRowCounts ?? Dictionary(
            listens.compactMap(\.recording.identity.msid).map { ($0, 1) },
            uniquingKeysWith: +
        )
    }
}

struct ListenBrainzLinkListensProvider: LinkListensProviding {
    static let maximumRetainedRows = 1_000
    private let transport: @Sendable (String, Int, Int) async throws -> LBMissingMusicBrainzPage
    private let gate: RequestGate

    init(gate: RequestGate = .shared) {
        let client = LBClient(token: "", userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)")
        transport = { try await client.missingMusicBrainz.listens(username: $0, offset: $1, count: $2) }
        self.gate = gate
    }

    init(
        gate: RequestGate,
        transport: @escaping @Sendable (String, Int, Int) async throws -> LBMissingMusicBrainzPage
    ) {
        self.gate = gate
        self.transport = transport
    }

    func unmatchedListens(username: String) async throws -> LinkListensPage {
        do {
            let page = try await gate.read(
                for: .missingMusicBrainz(
                    .anonymous,
                    user: username,
                    offset: 0,
                    count: Self.maximumRetainedRows
                )
            ) {
                try await transport(username, 0, Self.maximumRetainedRows)
            } deferralForError: { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }

            guard page.userName == username,
                  page.offset == 0,
                  page.count == page.data.count,
                  (0 ... Self.maximumRetainedRows).contains(page.count),
                  page.totalDataCount >= page.count
            else { throw LinkListensProviderError.invalidResponse }

            var seen = Set<UUID>()
            let sourceRowCounts = Dictionary(
                page.data.map { ($0.recordingMsid, 1) },
                uniquingKeysWith: +
            )
            let listens = page.data.prefix(Self.maximumRetainedRows).compactMap { source -> Listen? in
                guard seen.insert(source.recordingMsid).inserted else { return nil }
                return Self.map(source)
            }
            return .init(
                listens: listens,
                totalDataCount: max(page.totalDataCount, page.data.count),
                lastUpdated: page.lastUpdated,
                sourceRowCounts: sourceRowCounts
            )
        } catch let LBError.rateLimited(resetIn) {
            throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
        } catch LBError.notFound {
            throw LinkListensProviderError.userNotFound
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LinkListensProviderError {
            throw error
        } catch {
            throw LinkListensProviderError.unavailable
        }
    }

    private static func map(_ source: LBMissingMusicBrainzListen) -> Listen? {
        let title = source.recordingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = source.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let release = source.releaseName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let recording = Recording(
            identity: .init(mbid: nil, msid: source.recordingMsid),
            title: title,
            artistName: artist,
            artistMBIDs: [],
            releaseTitle: release,
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: nil,
            source: nil
        )
        return Listen(
            recording: recording,
            listenedAt: source.listenedAt,
            insertedAt: nil,
            isPlayingNow: false,
            inspection: .init(
                submittedArtist: artist,
                submittedTrack: title,
                submittedRelease: release,
                recordingMSID: source.recordingMsid,
                submittedRecordingMSID: source.recordingMsid,
                submittedArtistMBIDs: [], submittedRecordingMBID: nil, submittedReleaseMBID: nil,
                submittedReleaseGroupMBID: nil, submittedTrackMBID: nil, submittedWorkMBIDs: [],
                resolvedArtistMBIDs: [], resolvedRecordingMBID: nil, resolvedReleaseMBID: nil,
                resolvedReleaseGroupMBID: nil, resolvedRecordingName: nil, trackNumber: nil,
                isrc: nil, spotifyID: nil, tags: [], mediaPlayer: nil, mediaPlayerVersion: nil,
                submissionClient: nil, submissionClientVersion: nil, musicService: nil,
                musicServiceName: nil, originURL: nil, durationMilliseconds: nil
            )
        )
    }
}

enum LinkListensProviderError: LocalizedError, Equatable {
    case userNotFound
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .userNotFound:
            String(localized: "ListenBrainz couldn’t find this account.")
        case .invalidResponse:
            String(localized: "ListenBrainz sent an unexpected response. Try again later.")
        case .unavailable:
            String(localized: "Check your connection, then try again.")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
