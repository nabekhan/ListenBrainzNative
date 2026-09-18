// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

protocol APIRequest {
    associatedtype Body: Encodable
    associatedtype Result

    var data: APIRequestData<Body> { get }
    func decodeResponse(_ data: Data, response: HTTPURLResponse?) throws -> Result
}

extension APIRequest where Result: Decodable {
    func decodeResponse(_ data: Data, response: HTTPURLResponse?) throws -> Result {
        try JSONDecoder.ListenBrainz.decode(Result.self, from: data)
    }
}

class NoBody: Encodable {}
class NoResult: Decodable {}

enum Method: String {
    case get = "GET"
    case post = "POST"
}

struct APIRequestData<Body: Encodable> {
    let path: String
    let method: Method
    let queryItems: [String: [String]]
    let headers: [String: String]
    let body: Body?
    let statusErrors: [Int: LBError]
    let preservesTrailingSlash: Bool
    /// `true` only when a request has already percent-encoded an individual
    /// path segment. This prevents `URL.appending(path:)` from escaping `%` a
    /// second time while keeping the default behavior unchanged for old calls.
    let pathIsPercentEncoded: Bool

    init(path: String,
         method: Method,
         queryItems: [String: [String]] = [:],
         headers: [String: String] = [:],
         body: Body? = nil,
         statusErrors: [Int: LBError] = [:],
         preservesTrailingSlash: Bool = false,
         pathIsPercentEncoded: Bool = false) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.statusErrors = statusErrors
        self.preservesTrailingSlash = preservesTrailingSlash
        self.pathIsPercentEncoded = pathIsPercentEncoded
    }
}
