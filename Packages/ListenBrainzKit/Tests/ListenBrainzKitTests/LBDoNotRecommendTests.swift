// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBDoNotRecommendTests {
    private let recordingMBID = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!

    @Test("Do-not-recommend entries use the documented public path and bounds")
    func entriesRequest() async throws {
        let page = LBDoNotRecommendPage(entries: [], totalCount: 0, count: 0, offset: 0, userID: "7")
        let mock = MockAPIClient(result: .success(page))

        _ = try await LBDoNotRecommendClient(mock).entries(user: "listener", count: 4_000, offset: -2)

        let request = try #require(mock.request as? DoNotRecommendEntriesRequest)
        #expect(request.data.path == "/1/user/listener/do-not-recommend")
        #expect(request.data.method == .get)
        #expect(request.data.queryItems == ["count": ["1000"], "offset": ["0"]])
        #expect(request.data.statusErrors == [404: .notFound])
        #expect(request.data.maximumResponseBytes == 1 * 1_024 * 1_024)
        #expect(request.data.pathIsPercentEncoded)

        let encodedMock = MockAPIClient(result: .success(page))
        _ = try await LBDoNotRecommendClient(encodedMock).entries(user: "listener/../?%#")
        let encoded = try #require(encodedMock.request as? DoNotRecommendEntriesRequest)
        #expect(encoded.data.path == "/1/user/listener%2F%2E%2E%2F%3F%25%23/do-not-recommend")
        #expect(encoded.data.pathIsPercentEncoded)
        let client = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "Test/1"
        )
        let encodedURL = try #require(try client.makeURLRequest(encoded).url)
        #expect(
            URLComponents(url: encodedURL, resolvingAgainstBaseURL: false)?.percentEncodedPath
                == "/1/user/listener%2F%2E%2E%2F%3F%25%23/do-not-recommend"
        )
    }

    @Test("Do-not-recommend mutations use canonical IDs and exact JSON bodies")
    func mutationRequests() async throws {
        let status = LBDoNotRecommendStatus(status: "ok")
        let addMock = MockAPIClient(result: .success(status))
        let until = Date(timeIntervalSince1970: 1_700_000_123.987)

        let addResult = try await LBDoNotRecommendClient(addMock).add(
            entity: .recording,
            entityMBID: recordingMBID,
            until: until
        )

        let add = try #require(addMock.request as? AddDoNotRecommendRequest)
        #expect(addResult.status == "ok")
        #expect(add.data.path == "/1/do-not-recommend/add")
        #expect(add.data.method == .post)
        #expect(add.data.headers["Content-Type"] == "application/json")
        #expect(add.data.statusErrors == [400: .invalidJSON, 401: .invalidAuth])
        #expect(add.data.maximumResponseBytes == 64 * 1_024)
        #expect(add.data.maximumRequestBodyBytes == 64 * 1_024)
        let addJSON = try jsonObject(add.data.body)
        #expect(addJSON?["entity"] as? String == "recording")
        #expect(addJSON?["entity_mbid"] as? String == recordingMBID.uuidString)
        #expect(addJSON?["until"] as? Int == 1_700_000_123)

        let removeMock = MockAPIClient(result: .success(status))
        _ = try await LBDoNotRecommendClient(removeMock).remove(entity: .recording, entityMBID: recordingMBID)
        let remove = try #require(removeMock.request as? RemoveDoNotRecommendRequest)
        #expect(remove.data.path == "/1/do-not-recommend/remove")
        #expect(remove.data.method == .post)
        #expect(remove.data.headers["Content-Type"] == "application/json")
        #expect(remove.data.statusErrors == [400: .invalidJSON, 401: .invalidAuth])
        #expect(remove.data.maximumResponseBytes == 64 * 1_024)
        #expect(remove.data.maximumRequestBodyBytes == 64 * 1_024)
        let removeJSON = try jsonObject(remove.data.body)
        #expect(removeJSON?["entity"] as? String == "recording")
        #expect(removeJSON?["entity_mbid"] as? String == recordingMBID.uuidString)
    }

    @Test("Do-not-recommend entries decode dates, entity types, and user ID")
    func decoding() throws {
        let page = try JSONDecoder.ListenBrainz.decode(
            LBDoNotRecommendPage.self,
            from: Data(#"""
            {"offset":3,"count":1,"total_count":7,"user_id":"42","results":[
              {"entity":"release_group","entity_mbid":"526bd613-fddd-4bd6-9137-ab709ac74cab","until":null,"created":1700000123}
            ]}
            """#.utf8)
        )

        #expect(page.offset == 3)
        #expect(page.count == 1)
        #expect(page.totalCount == 7)
        #expect(page.userID == "42")
        #expect(page.entries.first?.entity == .releaseGroup)
        #expect(page.entries.first?.entityMBID == recordingMBID)
        #expect(page.entries.first?.until == nil)
        #expect(page.entries.first?.created.timeIntervalSince1970 == 1_700_000_123)
    }

    @Test("An invalid expiry is rejected before a request is made")
    func invalidExpiry() async {
        let mock = MockAPIClient(result: .success(LBDoNotRecommendStatus(status: "ok")))
        await #expect(throws: LBError.invalidParam) {
            _ = try await LBDoNotRecommendClient(mock).add(
                entity: .recording,
                entityMBID: recordingMBID,
                until: .distantPast
            )
        }
        #expect(mock.request == nil)

        await #expect(throws: LBError.invalidParam) {
            _ = try await LBDoNotRecommendClient(mock).add(
                entity: .recording,
                entityMBID: recordingMBID,
                until: Date(timeIntervalSince1970: .infinity)
            )
        }
        #expect(mock.request == nil)

        await #expect(throws: LBError.invalidParam) {
            _ = try await LBDoNotRecommendClient(mock).add(
                entity: .recording,
                entityMBID: recordingMBID,
                until: Date(timeIntervalSince1970: Double(Int.max))
            )
        }
        #expect(mock.request == nil)
    }
}

private func jsonObject<Body: Encodable>(_ body: Body?) throws -> [String: Any]? {
    guard let body else { return nil }
    return try JSONSerialization.jsonObject(with: JSONEncoder.ListenBrainz.encode(body)) as? [String: Any]
}
