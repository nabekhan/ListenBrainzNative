// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite(.serialized) struct LBUserDataExportTests {
    @Test("User-data exports decode ISO 8601 dates and preserve future states")
    func decoding() throws {
        let export = try JSONDecoder.ListenBrainz.decode(LBUserDataExport.self, from: Data("""
        {"export_id":17,"type":"export_all_user_data","available_until":"2026-10-27T11:12:13.456789+00:00","created":"2026-09-27T11:12:13+00:00","progress":"7%","status":"in_progress","filename":null,"start_time":1700000000,"end_time":1700000001}
        """.utf8))

        #expect(export.id == 17)
        #expect(export.status == .inProgress)
        #expect(!export.status.isTerminal)
        #expect(!export.status.canDownload)
        #expect(export.created.timeIntervalSince1970 == 1_790_507_533)
        #expect(export.availableUntil != nil)
        #expect(export.filename == nil)
        #expect(export.startTime == 1_700_000_000)

        let future = try JSONDecoder.ListenBrainz.decode(LBUserDataExport.self, from: Data("""
        {"export_id":18,"type":"export_all_user_data","available_until":null,"created":"2026-09-27T11:12:13Z","progress":"new","status":"future_state","filename":"archive.zip","start_time":null,"end_time":null}
        """.utf8))
        #expect(future.status == .unknown("future_state"))
        #expect(!future.status.canDownload)
    }

    @Test("Export requests retain documented paths, methods, bodies, and mappings")
    func requestSemantics() throws {
        let list = UserDataExportListRequest()
        #expect(list.data.path == "/1/export/list")
        #expect(list.data.method == .get)
        #expect(list.data.statusErrors[401] == .invalidAuth)
        #expect(list.data.statusErrors[503] == .unknownError)

        let full = CreateFullUserDataExportRequest()
        #expect(full.data.path == "/1/export/")
        #expect(full.data.method == .post)
        #expect(full.data.preservesTrailingSlash)
        #expect(full.data.body == nil)
        #expect(full.data.statusErrors[400] == .badRequest)
        #expect(full.data.maximumResponseBytes == 64 * 1_024)

        let range = try LBUserDataExportRange(startTime: 1_700_000_000, endTime: 1_700_000_001)
        let ranged = CreateRangedUserDataExportRequest(range: range)
        let body = try #require(ranged.data.body)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder.ListenBrainz.encode(body)) as? [String: Int]
        #expect(json == ["start_time": 1_700_000_000, "end_time": 1_700_000_001])

        #expect(UserDataExportStatusRequest(exportID: 3).data.path == "/1/export/3")
        #expect(DeleteUserDataExportRequest(exportID: 3).data.path == "/1/export/3/delete")
        let download = DownloadUserDataExportRequest(exportID: 3)
        #expect(download.data.path == "/1/export/3/download")
        #expect(download.data.method == .get)
        #expect(download.data.maximumDownloadBytes == DownloadUserDataExportRequest.maximumArchiveBytes)
        #expect(download.data.statusErrors[404] == .notFound)
        #expect(list.data.maximumResponseBytes == 1 * 1_024 * 1_024)
    }

    @Test("Invalid export identifiers and ranges are rejected before transport")
    func validation() async throws {
        #expect(throws: LBError.invalidParam) {
            _ = try LBUserDataExportRange()
        }
        #expect(throws: LBError.invalidParam) {
            _ = try LBUserDataExportRange(startTime: 9, endTime: 8)
        }

        let mock = MockAPIClient(result: .failure(.unknownError))
        let client = LBUserDataExportClient(mock)
        await #expect(throws: LBError.invalidParam) {
            _ = try await client.status(exportID: 0)
        }
        #expect(mock.request == nil)
        await #expect(throws: LBError.invalidParam) {
            try await client.delete(exportID: -1)
        }
        #expect(mock.request == nil)
        await #expect(throws: LBError.invalidParam) {
            _ = try await client.download(exportID: 0, to: URL(fileURLWithPath: "/tmp/archive.zip"))
        }
        #expect(mock.request == nil)
        let unknown = LBUserDataExport(
            exportID: 1, type: "export_all_user_data", availableUntil: nil,
            created: .now, progress: "untrusted", status: .unknown("future"),
            filename: nil, startTime: nil, endTime: nil
        )
        await #expect(throws: LBError.invalidParam) {
            _ = try await client.download(unknown, to: URL(fileURLWithPath: "/tmp/archive.zip"))
        }
        #expect(mock.request == nil)
    }

    @Test("Export lists reject an excessive decoded item count")
    func listCountLimit() {
        let item = #"{"export_id":1,"type":"export_all_user_data","available_until":null,"created":"2026-09-27T11:12:13Z","progress":"ready","status":"completed","filename":"archive.zip","start_time":null,"end_time":null}"#
        let data = Data(("[" + Array(repeating: item, count: 1_001).joined(separator: ",") + "]").utf8)
        #expect(throws: LBError.invalidResponse) {
            _ = try UserDataExportListRequest().decodeResponse(data, response: nil)
        }
    }

    @Test("Downloads require ZIP content, honor declared size, stream within the cap, and remove failures")
    func downloadPolicy() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ListenBrainzKit-ExportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let client = makeDownloadClient()
        let destination = root.appending(path: "archive.zip")

        DownloadURLProtocol.setResponse(status: 200, headers: ["Content-Type": "application/zip"], body: Data([0x50, 0x4B, 0x03, 0x04]))
        let saved = try await client.download(SmallArchiveDownloadRequest(maximumBytes: 4), to: destination)
        #expect(saved == destination)
        #expect(try Data(contentsOf: saved) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(DownloadURLProtocol.lastRequest?.url?.path == "/1/export/3/download")

        DownloadURLProtocol.setResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data([0x50]))
        let nonZip = root.appending(path: "not-zip.zip")
        await #expect(throws: LBError.invalidResponse) {
            _ = try await client.download(SmallArchiveDownloadRequest(maximumBytes: 4), to: nonZip)
        }
        #expect(!FileManager.default.fileExists(atPath: nonZip.path))

        DownloadURLProtocol.setResponse(status: 200, headers: ["Content-Type": "application/zip", "Content-Length": "5"], body: Data([0x50, 0x4B, 0x03, 0x04, 0x00]))
        let declaredOversize = root.appending(path: "declared-oversize.zip")
        await #expect(throws: LBError.invalidResponse) {
            _ = try await client.download(SmallArchiveDownloadRequest(maximumBytes: 4), to: declaredOversize)
        }
        #expect(!FileManager.default.fileExists(atPath: declaredOversize.path))

        DownloadURLProtocol.setResponse(status: 200, headers: ["Content-Type": "application/zip"], body: Data([0x50, 0x4B, 0x03, 0x04, 0x00]))
        let streamedOversize = root.appending(path: "streamed-oversize.zip")
        await #expect(throws: LBError.invalidResponse) {
            _ = try await client.download(SmallArchiveDownloadRequest(maximumBytes: 4), to: streamedOversize)
        }
        #expect(!FileManager.default.fileExists(atPath: streamedOversize.path))

        DownloadURLProtocol.setResponse(status: 404, headers: ["Content-Type": "application/zip"], body: Data())
        let missing = root.appending(path: "missing.zip")
        await #expect(throws: LBError.notFound) {
            _ = try await client.download(SmallArchiveDownloadRequest(maximumBytes: 4), to: missing)
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    private func makeDownloadClient() -> ListenBrainzAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocol.self]
        return ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://api.listenbrainz.org")!,
            userAgent: "ListenBrainzKitTests/1.0",
            session: URLSession(configuration: configuration)
        )
    }
}

private struct SmallArchiveDownloadRequest: APIRequest {
    typealias Result = NoResult
    let data: APIRequestData<NoBody>

    init(maximumBytes: Int) {
        data = .init(
            path: "/1/export/3/download",
            method: .get,
            statusErrors: [404: .notFound],
            maximumDownloadBytes: maximumBytes
        )
    }
}

private final class DownloadURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var configuredResponse = (status: 200, headers: [String: String](), body: Data())
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func setResponse(status: Int, headers: [String: String], body: Data) {
        lock.withLock {
            configuredResponse = (status, headers, body)
            lastRequest = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.lock.withLock { () -> (Int, [String: String], Data) in
            Self.lastRequest = request
            return Self.configuredResponse
        }
        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.0,
                httpVersion: nil,
                headerFields: response.1
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.2)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
