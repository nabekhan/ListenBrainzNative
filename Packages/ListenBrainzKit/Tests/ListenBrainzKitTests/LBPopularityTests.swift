// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import ListenBrainzKit

@Suite
struct LBPopularityTests {
    private let first = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test("Popularity batch requests use canonical paths and JSON keys")
    func requestSemantics() throws {
        let cases: [(PopularityEntityKind, String, String)] = [
            (.artist, "/1/popularity/artist", "artist_mbids"),
            (.recording, "/1/popularity/recording", "recording_mbids"),
            (.release, "/1/popularity/release", "release_mbids"),
            (.releaseGroup, "/1/popularity/release-group", "release_group_mbids"),
        ]

        for (kind, path, key) in cases {
            let request = try PopularityBatchRequest(kind: kind, mbids: [second, first])
            #expect(request.data.path == path)
            #expect(request.data.method == .post)
            #expect(request.data.statusErrors[400] == .badRequest)
            let data = try JSONEncoder.ListenBrainz.encode(request.data.body!)
            let body = try JSONSerialization.jsonObject(with: data) as? [String: [String]]
            #expect(body?[key] == [second.uuidString.lowercased(), first.uuidString.lowercased()])
        }
    }

    @Test("Popularity requests reject empty and oversized batches")
    func requestValidation() throws {
        #expect(throws: LBError.invalidParam) {
            _ = try PopularityBatchRequest(kind: .artist, mbids: [])
        }
        #expect(throws: LBError.invalidParam) {
            _ = try PopularityBatchRequest(kind: .artist, mbids: Array(repeating: first, count: 1_001))
        }
        #expect(throws: Never.self) {
            _ = try PopularityBatchRequest(kind: .artist, mbids: [first, first])
        }
    }

    @Test("Popularity response preserves order and nullable counts")
    func responseDecoding() throws {
        let values = try JSONDecoder.ListenBrainz.decode(
            PopularityBatchRequest.Result.self,
            from: Data("""
            [
              { "recording_mbid": "\(second)", "total_listen_count": null, "total_user_count": 9 },
              { "recording_mbid": "\(first)", "total_listen_count": 42, "total_user_count": null }
            ]
            """.utf8)
        )

        #expect(values.map(\.mbid) == [second, first])
        #expect(values.map(\.totalListenCount) == [nil, 42])
        #expect(values.map(\.totalUserCount) == [9, nil])
    }

    @Test("Popularity client executes the matching typed batch request")
    func clientExecution() async throws {
        let expected = [LBPopularityFixture.make(mbid: first, listens: 5, users: 2)]
        let mock = MockAPIClient(result: .success(expected))
        let client = LBPopularityClient(mock)

        let values = try await client.releaseGroups([first])

        #expect(values == expected)
        let request = try #require(mock.request as? PopularityBatchRequest)
        #expect(request.data.path == "/1/popularity/release-group")
    }
}

private enum LBPopularityFixture {
    static func make(mbid: UUID, listens: Int?, users: Int?) -> LBPopularity {
        let data = Data("""
        [{ "artist_mbid": "\(mbid)", "total_listen_count": \(listens.map(String.init) ?? "null"), "total_user_count": \(users.map(String.init) ?? "null") }]
        """.utf8)
        return try! JSONDecoder.ListenBrainz.decode([LBPopularity].self, from: data)[0]
    }
}
