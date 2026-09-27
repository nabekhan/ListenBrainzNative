// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct UserDataExportListRequest: APIRequest {
    typealias Result = [LBUserDataExport]
    let data = APIRequestData<NoBody>(
        path: "/1/export/list",
        method: .get,
        statusErrors: UserDataExportStatusErrors.read,
        maximumResponseBytes: 1 * 1_024 * 1_024
    )

    func decodeResponse(_ data: Data, response: HTTPURLResponse?) throws -> [LBUserDataExport] {
        let exports = try JSONDecoder.ListenBrainz.decode([LBUserDataExport].self, from: data)
        guard exports.count <= 1_000 else { throw LBError.invalidResponse }
        return exports
    }
}

struct CreateFullUserDataExportRequest: APIRequest {
    typealias Result = LBUserDataExport
    let data = APIRequestData<NoBody>(
        path: "/1/export/",
        method: .post,
        statusErrors: UserDataExportStatusErrors.create,
        preservesTrailingSlash: true,
        maximumResponseBytes: 64 * 1_024
    )
}

struct CreateRangedUserDataExportRequest: APIRequest {
    typealias Result = LBUserDataExport
    let data: APIRequestData<Body>

    init(range: LBUserDataExportRange) {
        data = .init(
            path: "/1/export/",
            method: .post,
            body: .init(startTime: range.startTime, endTime: range.endTime),
            statusErrors: UserDataExportStatusErrors.create,
            preservesTrailingSlash: true,
            maximumResponseBytes: 64 * 1_024
        )
    }

    struct Body: Encodable {
        let startTime: Int?
        let endTime: Int?
    }
}

struct UserDataExportStatusRequest: APIRequest {
    typealias Result = LBUserDataExport
    let data: APIRequestData<NoBody>

    init(exportID: Int) {
        data = .init(
            path: "/1/export/\(exportID)",
            method: .get,
            statusErrors: UserDataExportStatusErrors.read,
            maximumResponseBytes: 64 * 1_024
        )
    }
}

struct DeleteUserDataExportRequest: APIRequest {
    typealias Result = UserDataExportDeleteResponse
    let data: APIRequestData<NoBody>

    init(exportID: Int) {
        data = .init(
            path: "/1/export/\(exportID)/delete",
            method: .post,
            statusErrors: UserDataExportStatusErrors.read,
            maximumResponseBytes: 64 * 1_024
        )
    }
}

struct DownloadUserDataExportRequest: APIRequest {
    typealias Result = NoResult
    /// Upper limit for one archive. The response is streamed straight to disk.
    static let maximumArchiveBytes = 4 * 1_024 * 1_024 * 1_024
    let data: APIRequestData<NoBody>

    init(exportID: Int) {
        data = .init(
            path: "/1/export/\(exportID)/download",
            method: .get,
            statusErrors: UserDataExportStatusErrors.read,
            maximumDownloadBytes: Self.maximumArchiveBytes
        )
    }
}

struct UserDataExportDeleteResponse: Decodable {
    let success: Bool
}

private enum UserDataExportStatusErrors {
    static let read: [Int: LBError] = [
        401: .invalidAuth,
        404: .notFound,
        503: .unknownError,
    ]
    static let create: [Int: LBError] = [
        400: .badRequest,
        401: .invalidAuth,
        503: .unknownError,
    ]
}
