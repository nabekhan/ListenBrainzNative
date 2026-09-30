import Foundation

struct PlaylistServiceImportItem: Identifiable, Equatable, Sendable {
    let service: PlaylistExternalService
    let externalID: String
    let title: String
    let summary: String?
    let artworkURL: URL?
    let ownerName: String?
    let trackCount: Int?
    let isPublic: Bool?
    let isCollaborative: Bool

    var id: String { "\(service.rawValue):\(externalID)" }

    func matches(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        return [title, ownerName, summary]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(value) }
    }
}

struct PlaylistServiceImportList: Equatable, Sendable {
    let service: PlaylistExternalService
    let playlists: [PlaylistServiceImportItem]
    let isTruncated: Bool
}

struct PlaylistServiceImportCacheKey: Hashable, Sendable {
    let username: String
    let scope: RequestGate.ReadScope
    let service: PlaylistExternalService

    init(
        username: String,
        scope: RequestGate.ReadScope,
        service: PlaylistExternalService
    ) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.scope = scope
        self.service = service
    }
}

enum PlaylistServiceImportPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded(PlaylistServiceImportList)
    case failed(String)
}

enum PlaylistServiceImportNotice: Identifiable, Equatable, Sendable {
    case confirmed(id: UUID, playlist: PlaylistServiceImportItem, playlistMBID: UUID)
    case confirmedRecoveryNeeded(id: UUID, playlist: PlaylistServiceImportItem, message: String)
    case failed(id: UUID, message: String)
    case verificationNeeded(id: UUID, playlist: PlaylistServiceImportItem, message: String)

    var id: UUID {
        switch self {
        case let .confirmed(id, _, _),
             let .confirmedRecoveryNeeded(id, _, _),
             let .failed(id, _),
             let .verificationNeeded(id, _, _):
            id
        }
    }
}
