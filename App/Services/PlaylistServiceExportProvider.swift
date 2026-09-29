import Foundation
import ListenBrainzKit

protocol PlaylistServiceExportProviding: Sendable {
    func export(
        playlistMBID: UUID,
        to service: PlaylistExternalService,
        isPublic: Bool
    ) async throws -> URL
}

protocol PlaylistServiceExportTransport: Sendable {
    func export(
        playlistMBID: UUID,
        to service: PlaylistExternalService,
        isPublic: Bool
    ) async throws -> URL
}

private struct LivePlaylistServiceExportTransport: PlaylistServiceExportTransport {
    let client: LBClient

    func export(
        playlistMBID: UUID,
        to service: PlaylistExternalService,
        isPublic: Bool
    ) async throws -> URL {
        try await client.core.exportPlaylist(
            mbid: playlistMBID,
            to: service.listenBrainzValue,
            isPublic: isPublic
        )
    }
}

/// A one-shot boundary around ListenBrainz's synchronous service export.
///
/// The endpoint creates a new external playlist and has no idempotency key.
/// Once transport starts, cancellation or an unclassified failure is therefore
/// reported as indeterminate and must never be replayed automatically.
struct ListenBrainzPlaylistServiceExportProvider: PlaylistServiceExportProviding {
    private let transport: any PlaylistServiceExportTransport
    private let gate: RequestGate

    init(token: String, gate: RequestGate = .shared) {
        transport = LivePlaylistServiceExportTransport(client: LBClient(
            token: token,
            userAgent: "ListenBrainzNative/0.1 (+https://github.com/nabekhan/ListenBrainzNative)"
        ))
        self.gate = gate
    }

    init(transport: some PlaylistServiceExportTransport, gate: RequestGate) {
        self.transport = transport
        self.gate = gate
    }

    func export(
        playlistMBID: UUID,
        to service: PlaylistExternalService,
        isPublic: Bool
    ) async throws -> URL {
        let attempt = MutationAttemptState()
        do {
            return try await gate.perform({
                await attempt.markTransportStarted()
                return try await transport.export(
                    playlistMBID: playlistMBID,
                    to: service,
                    isPublic: isPublic
                )
            }) { error in
                guard case let LBError.rateLimited(resetIn) = error else { return nil }
                return .seconds(max(resetIn, 1))
            }
        } catch {
            // The server forwards downstream-provider statuses after invoking
            // the exporter, so even a 4xx or 429 can follow partial creation.
            // Only cancellation before transport admission is provably safe.
            guard await attempt.didStartTransport else {
                if error is CancellationError {
                    throw PlaylistServiceExportProviderError.cancelledBeforeTransport
                }
                if let error = error as? URLError, error.code == .cancelled {
                    throw PlaylistServiceExportProviderError.cancelledBeforeTransport
                }
                throw error
            }
            throw PlaylistServiceExportProviderError.indeterminateExport
        }
    }

    private actor MutationAttemptState {
        private(set) var didStartTransport = false

        func markTransportStarted() {
            didStartTransport = true
        }
    }
}

enum PlaylistServiceExportProviderError: Error, Equatable, Sendable {
    case cancelledBeforeTransport
    case indeterminateExport
}

private extension PlaylistExternalService {
    var listenBrainzValue: LBPlaylistService {
        switch self {
        case .spotify: .spotify
        case .appleMusic: .appleMusic
        case .soundCloud: .soundCloud
        }
    }
}
