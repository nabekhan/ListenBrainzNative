import Foundation
import ListenBrainzKit

protocol RadioProviding: Sendable {
    func generate(options: RadioGenerationOptions) async throws -> RadioMix
}

protocol RadioTransport: Sendable {
    func generate(prompt: String, mode: LBRadioMode) async throws -> LBGeneratedRadio
    func recordingMetadata(mbids: [UUID]) async throws -> [UUID: RadioRecordingMetadata]
}

struct RadioRecordingMetadata: Sendable {
    let title: String
    let artistName: String?
    let artistMBIDs: [UUID]
    let releaseTitle: String?
    let releaseMBID: UUID?
    let releaseGroupMBID: UUID?
    let artworkReleaseMBID: UUID?
    let durationMilliseconds: Int?
}

private struct LiveRadioTransport: RadioTransport {
    let client: LBClient

    func generate(prompt: String, mode: LBRadioMode) async throws -> LBGeneratedRadio {
        try await client.radio.generate(prompt: prompt, mode: mode)
    }

    func recordingMetadata(mbids: [UUID]) async throws -> [UUID: RadioRecordingMetadata] {
        let values = try await client.metadata.recordings(
            mbids: mbids,
            including: [LBMetaInclusion.artist, .release]
        )
        return values.mapValues { value in
            RadioRecordingMetadata(
                title: value.recording.name,
                artistName: value.artist?.name,
                artistMBIDs: value.artist?.artists.map(\.id) ?? [],
                releaseTitle: value.release?.name,
                releaseMBID: value.release?.mbid,
                releaseGroupMBID: value.release?.releaseGroupMbid,
                artworkReleaseMBID: value.release?.caaReleaseMbid ?? value.release?.mbid,
                durationMilliseconds: value.recording.length
            )
        }
    }
}

struct ListenBrainzRadioProvider: RadioProviding {
    private let transport: any RadioTransport
    private let gate: RequestGate
    private let readScope: RequestGate.ReadScope

    init(token: String, gate: RequestGate = .shared) {
        transport = LiveRadioTransport(
            client: LBClient(
                token: token,
                userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
            )
        )
        self.gate = gate
        readScope = .authenticated(token: token)
    }

    init(
        transport: some RadioTransport,
        gate: RequestGate,
        readScope: RequestGate.ReadScope = .isolated()
    ) {
        self.transport = transport
        self.gate = gate
        self.readScope = readScope
    }

    func generate(options: RadioGenerationOptions) async throws -> RadioMix {
        let prompt = options.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = try await read(.radioPlaylist(readScope, prompt: prompt, mode: options.mode.rawValue)) {
            try await transport.generate(prompt: prompt, mode: options.mode)
        }
        try Task.checkCancellation()

        let recordingMBIDs = Self.uniqueRecordingMBIDs(in: generated.tracks)
        var metadata: [UUID: RadioRecordingMetadata] = [:]
        var metadataEnrichmentFailed = false
        if !recordingMBIDs.isEmpty {
            do {
                metadata = try await read(.radioMetadata(readScope, mbids: recordingMBIDs)) {
                    try await transport.recordingMetadata(mbids: recordingMBIDs)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The generated JSPF is still useful without optional artwork
                // enrichment. Do not force a second expensive radio generation.
                metadataEnrichmentFailed = true
            }
        }
        try Task.checkCancellation()

        return RadioMix(
            options: options,
            title: Self.nonempty(generated.title) ?? "LB Radio mix",
            annotation: Self.nonempty(generated.annotation),
            feedback: Self.normalizedFeedback(generated.feedback),
            tracks: generated.tracks.enumerated().map { index, track in
                PlaylistTrack(
                    position: index + 1,
                    recording: Self.recording(
                        from: track,
                        metadata: track.recordingMBID.flatMap { metadata[$0] }
                    ),
                    addedAt: nil,
                    addedBy: nil
                )
            },
            metadataEnrichmentFailed: metadataEnrichmentFailed,
            generatedAt: .now
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
        } catch let error as LBError {
            switch error {
            case let .rateLimited(resetIn):
                throw ProviderError.rateLimited(retryAfterSeconds: max(resetIn, 1))
            case .invalidAuth, .forbidden, .noToken:
                throw RadioProviderError.invalidAuthentication
            case .badRequest, .invalidParam:
                throw RadioProviderError.invalidPrompt
            case .invalidJSON, .invalidResponse, .unknownError, .notFound, .noContent:
                throw RadioProviderError.generationUnavailable
            }
        }
    }

    private static func uniqueRecordingMBIDs(in tracks: [LBPlaylistTrack]) -> [UUID] {
        var seen = Set<UUID>()
        return tracks.compactMap(\.recordingMBID).filter { seen.insert($0).inserted }
    }

    private static func recording(
        from track: LBPlaylistTrack,
        metadata: RadioRecordingMetadata?
    ) -> Recording {
        let releaseMBID = metadata?.releaseMBID ?? track.releaseMBID
        return Recording(
            identity: .init(mbid: track.recordingMBID, msid: nil),
            title: nonempty(metadata?.title) ?? nonempty(track.title) ?? "Unknown recording",
            artistName: nonempty(metadata?.artistName) ?? nonempty(track.artistCreditName) ?? "Unknown artist",
            artistMBIDs: metadata?.artistMBIDs.isEmpty == false
                ? metadata?.artistMBIDs ?? []
                : track.artistMBIDs,
            releaseTitle: nonempty(metadata?.releaseTitle) ?? nonempty(track.releaseName),
            releaseMBID: releaseMBID,
            releaseGroupMBID: metadata?.releaseGroupMBID,
            artworkReleaseMBID: metadata?.artworkReleaseMBID
                ?? track.caaReleaseMBID
                ?? releaseMBID,
            durationMilliseconds: metadata?.durationMilliseconds ?? track.durationMilliseconds,
            source: "LB Radio"
        )
    }

    private static func normalizedFeedback(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let value = nonempty(value) else { return nil }
            let key = value.lowercased()
            return seen.insert(key).inserted ? value : nil
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum RadioProviderError: LocalizedError, Sendable {
    case invalidAuthentication
    case invalidPrompt
    case generationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAuthentication:
            "Your ListenBrainz sign-in is no longer valid. Reconnect your token to tune LB Radio."
        case .invalidPrompt:
            "ListenBrainz could not understand that radio recipe. Adjust the source or prompt and try again."
        case .generationUnavailable:
            "ListenBrainz could not generate this mix right now. Your previous mix, if any, is still here."
        }
    }
}
