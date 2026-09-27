// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Access to the authenticated user's ListenBrainz data-export archives.
///
/// Every method performs exactly one request. This client intentionally does
/// not poll, retry, or delete exports automatically.
public struct LBUserDataExportClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) { self.apiClient = client }

    /// Lists existing export jobs, newest first.
    public func list() async throws -> [LBUserDataExport] {
        try await apiClient.execute(UserDataExportListRequest())
    }

    /// Creates a full-history export for the authenticated user.
    @discardableResult
    public func createFull() async throws -> LBUserDataExport {
        try await apiClient.execute(CreateFullUserDataExportRequest())
    }

    /// Creates an export whose listens lie in the supplied inclusive bounds.
    @discardableResult
    public func create(range: LBUserDataExportRange) async throws -> LBUserDataExport {
        try await apiClient.execute(CreateRangedUserDataExportRequest(range: range))
    }

    /// Fetches the current state of one export job.
    public func status(exportID: Int) async throws -> LBUserDataExport {
        guard exportID > 0 else { throw LBError.invalidParam }
        return try await apiClient.execute(UserDataExportStatusRequest(exportID: exportID))
    }

    /// Explicitly and permanently deletes an export owned by the authenticated user.
    public func delete(exportID: Int) async throws {
        guard exportID > 0 else { throw LBError.invalidParam }
        let response = try await apiClient.execute(DeleteUserDataExportRequest(exportID: exportID))
        guard response.success else { throw LBError.invalidResponse }
    }

    /// Streams a completed ZIP archive directly to a destination that does not already exist.
    @discardableResult
    public func download(exportID: Int, to destination: URL) async throws -> URL {
        guard exportID > 0 else { throw LBError.invalidParam }
        return try await apiClient.download(
            DownloadUserDataExportRequest(exportID: exportID),
            to: destination
        )
    }

    /// Streams this completed export directly to a destination that does not already exist.
    /// Unknown or incomplete server states are intentionally not downloadable.
    @discardableResult
    public func download(_ export: LBUserDataExport, to destination: URL) async throws -> URL {
        guard export.status.canDownload else { throw LBError.invalidParam }
        return try await download(exportID: export.exportID, to: destination)
    }
}
