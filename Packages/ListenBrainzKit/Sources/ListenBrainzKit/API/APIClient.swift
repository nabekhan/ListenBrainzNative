// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

protocol APIClient: Sendable {
    func execute<Request: APIRequest>(_ request: Request) async throws -> Request.Result
}

struct ListenBrainzAPIClient: APIClient {
    private static let officialRoot = URL(string: "https://api.listenbrainz.org")!
    private static let session: URLSession = {
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

    init(
        token: String,
        root: URL?,
        allowsTokenToCustomRoot: Bool = false,
        userAgent: String
    ) {
        self.token = token
        self.root = root ?? Self.officialRoot
        self.userAgent = userAgent
        self.allowsTokenToRoot = root == nil
            || allowsTokenToCustomRoot
            || AuthenticatedRedirectDelegate.sameOrigin(self.root, Self.officialRoot)
    }

    func execute<Request: APIRequest>(_ request: Request) async throws -> Request.Result {
        let req = try makeURLRequest(request)
        let (data, resp) = try await Self.session.data(for: req)

        if let httpResp = resp as? HTTPURLResponse,
           !(200 ... 299).contains(httpResp.statusCode) {
            let code = httpResp.statusCode
            if code == 429 {
                throw LBError.rateLimited(resetIn: rateLimitDelay(from: httpResp))
            }
            throw request.data.statusErrors[httpResp.statusCode] ?? .unknownError
        }

        return try JSONDecoder.ListenBrainz.decode(Request.Result.self, from: data)
    }

    func makeURLRequest<Request: APIRequest>(_ request: Request) throws -> URLRequest {
        let relativePath = request.data.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = root
            .appending(path: relativePath)
            .appending(queryItems: request.data.queryItems.flatMap { entry in
                entry.value.map { URLQueryItem(name: entry.key, value: $0) }
            })

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
            let bodyData = try JSONEncoder.ListenBrainz.encode(body)
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
}

final class AuthenticatedRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func sameOrigin(_ source: URL, _ destination: URL) -> Bool {
        source.scheme?.lowercased() == destination.scheme?.lowercased()
            && source.host?.lowercased() == destination.host?.lowercased()
            && effectivePort(source) == effectivePort(destination)
    }

    func allowsAuthenticatedRedirect(from source: URL, to destination: URL) -> Bool {
        Self.sameOrigin(source, destination)
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

        guard allowsAuthenticatedRedirect(from: source, to: destination) else {
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
