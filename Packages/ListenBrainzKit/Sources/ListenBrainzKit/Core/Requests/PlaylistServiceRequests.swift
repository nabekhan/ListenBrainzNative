// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct ExportPlaylistToServiceRequest: APIRequest {
    typealias Result = PlaylistServiceExportResponse

    let data: APIRequestData<NoBody>

    init(mbid: UUID, service: LBPlaylistService, isPublic: Bool) {
        data = .init(
            path: "/1/playlist/\(mbid.uuidString)/export/\(service.rawValue)",
            method: .post,
            queryItems: ["is_public": [String(isPublic)]],
            statusErrors: [
                400: .badRequest,
                401: .invalidAuth,
                403: .forbidden,
                404: .notFound,
            ],
            maximumResponseBytes: 64 * 1_024
        )
    }
}

struct PlaylistServiceExportResponse: Decodable {
    let externalUrl: String
}
