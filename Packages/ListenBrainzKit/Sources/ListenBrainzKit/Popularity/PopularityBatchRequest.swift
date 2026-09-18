// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

enum PopularityEntityKind: Sendable {
    case artist
    case recording
    case release
    case releaseGroup

    var path: String {
        switch self {
        case .artist: "/1/popularity/artist"
        case .recording: "/1/popularity/recording"
        case .release: "/1/popularity/release"
        case .releaseGroup: "/1/popularity/release-group"
        }
    }

    var requestKey: String {
        switch self {
        case .artist: "artistMbids"
        case .recording: "recordingMbids"
        case .release: "releaseMbids"
        case .releaseGroup: "releaseGroupMbids"
        }
    }
}

struct PopularityBatchRequest: APIRequest {
    let data: APIRequestData<PopularityBatchBody>

    init(kind: PopularityEntityKind, mbids: [UUID]) throws {
        try Self.validate(mbids)
        self.data = .init(
            path: kind.path,
            method: .post,
            body: PopularityBatchBody(key: kind.requestKey, mbids: mbids),
            statusErrors: [400: .badRequest]
        )
    }

    static func validate(_ mbids: [UUID]) throws {
        guard !mbids.isEmpty, mbids.count <= 1_000 else {
            throw LBError.invalidParam
        }
    }

    typealias Result = [LBPopularity]
}

struct PopularityBatchBody: Encodable {
    let key: String
    let mbids: [UUID]

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(mbids, forKey: DynamicCodingKey(key))
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
