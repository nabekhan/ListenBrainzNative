// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

protocol APIClient: Sendable {
    func execute<Request: APIRequest>(_ request: Request) async throws -> Request.Result
    func download<Request: APIRequest>(_ request: Request, to destination: URL) async throws -> URL
}

struct ListenBrainzAPIClient: APIClient {
    private static let officialRoot = URL(string: "https://api.listenbrainz.org")!
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(
            configuration: configuration,
            delegate: AuthenticatedRedirectDelegate(),
            delegateQueue: nil
        )
    }()

    let token: String
    let root: URL
    let userAgent: String
    private let allowsTokenToRoot: Bool
    private let session: URLSession

    init(
        token: String,
        root: URL?,
        allowsTokenToCustomRoot: Bool = false,
        userAgent: String,
        session: URLSession? = nil
    ) {
        self.token = token
        self.root = root ?? Self.officialRoot
        self.userAgent = userAgent
        self.session = session ?? Self.sharedSession
        self.allowsTokenToRoot = root == nil
            || allowsTokenToCustomRoot
            || AuthenticatedRedirectDelegate.sameOrigin(self.root, Self.officialRoot)
    }

    func execute<Request: APIRequest>(_ request: Request) async throws -> Request.Result {
        let req = try makeURLRequest(request)
        let data: Data
        let resp: URLResponse

        if let maximumResponseBytes = request.data.maximumResponseBytes {
            let (bytes, response) = try await session.bytes(for: req)
            if let httpResponse = response as? HTTPURLResponse,
               let error = responseError(from: httpResponse, for: request) {
                throw error
            }
            guard response.expectedContentLength <= Int64(maximumResponseBytes) else {
                throw LBError.invalidResponse
            }

            var boundedData = Data()
            if response.expectedContentLength > 0 {
                boundedData.reserveCapacity(Int(response.expectedContentLength))
            }
            for try await byte in bytes {
                try Task.checkCancellation()
                boundedData.append(byte)
                guard boundedData.count <= maximumResponseBytes else {
                    throw LBError.invalidResponse
                }
            }
            data = boundedData
            resp = response
        } else {
            (data, resp) = try await session.data(for: req)
        }

        if let httpResp = resp as? HTTPURLResponse,
           let error = responseError(from: httpResp, for: request) {
            throw error
        }

        return try request.decodeResponse(data, response: resp as? HTTPURLResponse)
    }

    func download<Request: APIRequest>(_ request: Request, to destination: URL) async throws -> URL {
        guard let maximumDownloadBytes = request.data.maximumDownloadBytes,
              maximumDownloadBytes > 0,
              destination.isFileURL,
              !FileManager.default.fileExists(atPath: destination.path)
        else { throw LBError.invalidParam }

        let req = try makeURLRequest(request)
        let (bytes, response) = try await session.bytes(for: req)
        let maximumBytes = Int64(maximumDownloadBytes)
        try validateDownloadResponse(response: response, request: request, maximumDownloadBytes: maximumBytes)

        var createdDestination = false
        do {
            let file = try createExclusiveFile(at: destination)
            createdDestination = true
            defer { try? file.close() }

            var receivedBytes: Int64 = 0
            var signature = Data()
            signature.reserveCapacity(4)
            var buffer = Data()
            buffer.reserveCapacity(64 * 1_024)
            for try await byte in bytes {
                try Task.checkCancellation()
                receivedBytes += 1
                guard receivedBytes <= maximumBytes else { throw LBError.invalidResponse }
                if signature.count < 4 { signature.append(byte) }
                buffer.append(byte)
                if buffer.count >= 64 * 1_024 {
                    try file.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                try file.write(contentsOf: buffer)
            }
            guard signature == Data([0x50, 0x4B, 0x03, 0x04]) else {
                throw LBError.invalidResponse
            }
            try file.synchronize()
            createdDestination = false
            return destination
        } catch {
            if createdDestination {
                try? FileManager.default.removeItem(at: destination)
            }
            throw error
        }
    }

    func validateDownloadResponse<Request: APIRequest>(
        response: URLResponse,
        request: Request,
        maximumDownloadBytes: Int64
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else { throw LBError.invalidResponse }
        if let error = responseError(from: httpResponse, for: request) { throw error }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard contentType == "application/zip",
              response.expectedContentLength <= maximumDownloadBytes || response.expectedContentLength < 0
        else { throw LBError.invalidResponse }
    }

    private func createExclusiveFile(at destination: URL) throws -> FileHandle {
        let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw LBError.invalidParam }
            throw LBError.unknownError
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destination.path
            )
            #endif
            #if canImport(Darwin)
            var protectedURL = destination
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try protectedURL.setResourceValues(resourceValues)
            #endif
            return handle
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw LBError.unknownError
        }
    }

    func makeURLRequest<Request: APIRequest>(_ request: Request) throws -> URLRequest {
        let relativePath = request.data.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint: URL
        var components: URLComponents?
        if request.data.pathIsPercentEncoded {
            components = URLComponents(url: root, resolvingAgainstBaseURL: false)
            let basePath = components?.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
            components?.percentEncodedPath = "/" + [basePath, relativePath]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
            endpoint = components?.url ?? root
        } else {
            endpoint = root.appending(path: relativePath)
            components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        }
        if request.data.preservesTrailingSlash && request.data.path.hasSuffix("/") {
            // Assigning through `path` decodes an already-escaped opaque
            // segment (for example a username containing `/`). Keep the
            // percent-encoded representation intact for slash-sensitive APIs.
            if request.data.pathIsPercentEncoded {
                components?.percentEncodedPath += "/"
            } else {
                components?.path += "/"
            }
        }
        components?.queryItems = request.data.queryItems.flatMap { entry in
            entry.value.map { URLQueryItem(name: entry.key, value: $0) }
        }
        let url = components?.url ?? endpoint

        var req = URLRequest(url: url)
        req.httpMethod = request.data.method.rawValue
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if !token.isEmpty {
            guard allowsTokenToRoot,
                  url.scheme?.lowercased() == "https"
            else { throw LBError.invalidParam }
            req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }

        for (header, value) in request.data.headers {
            req.addValue(value, forHTTPHeaderField: header)
        }

        if let body = request.data.body {
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let bodyData = try JSONEncoder.ListenBrainz.encode(body)
            if let maximumRequestBodyBytes = request.data.maximumRequestBodyBytes,
               bodyData.count > maximumRequestBodyBytes {
                throw LBError.invalidParam
            }
            req.httpBody = bodyData
        }
        return req
    }

    func rateLimitDelay(from response: HTTPURLResponse) -> Int {
        ["Retry-After", "X-RateLimit-Reset-In"]
            .compactMap { response.value(forHTTPHeaderField: $0) }
            .compactMap(Int.init)
            .max() ?? 10
    }

    func responseError<Request: APIRequest>(
        from response: HTTPURLResponse,
        for request: Request
    ) -> LBError? {
        if response.statusCode == 429 {
            return .rateLimited(resetIn: rateLimitDelay(from: response))
        }
        if let mappedError = request.data.statusErrors[response.statusCode] {
            return mappedError
        }
        return (200 ... 299).contains(response.statusCode) ? nil : .unknownError
    }
}

final class AuthenticatedRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func sameOrigin(_ source: URL, _ destination: URL) -> Bool {
        source.scheme?.lowercased() == destination.scheme?.lowercased()
            && source.host?.lowercased() == destination.host?.lowercased()
            && effectivePort(source) == effectivePort(destination)
    }

    func allowsAuthenticatedRedirect(
        from source: URL,
        to destination: URL,
        method: String? = "GET"
    ) -> Bool {
        guard method == "GET" || method == "HEAD" else { return false }
        return Self.sameOrigin(source, destination)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let originalRequest = task.originalRequest,
              originalRequest.value(forHTTPHeaderField: "Authorization") != nil,
              let source = originalRequest.url,
              let destination = request.url
        else {
            completionHandler(request)
            return
        }

        guard allowsAuthenticatedRedirect(
            from: source,
            to: destination,
            method: originalRequest.httpMethod
        ) else {
            completionHandler(nil)
            return
        }

        var authenticatedRequest = request
        authenticatedRequest.setValue(
            originalRequest.value(forHTTPHeaderField: "Authorization"),
            forHTTPHeaderField: "Authorization"
        )
        completionHandler(authenticatedRequest)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
