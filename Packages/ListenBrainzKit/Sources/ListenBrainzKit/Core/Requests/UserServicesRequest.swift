// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct UserServicesRequest: APIRequest {
    let data: APIRequestData<NoBody>

    init(username: String) {
        let allowed = CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/?#%")
        )
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: allowed) ?? username
        self.data = .init(
            path: "/1/user/\(encodedUsername)/services",
            method: .get,
            statusErrors: [401: .invalidAuth,
                           403: .forbidden,
                           404: .notFound],
            pathIsPercentEncoded: true
        )
    }

    struct Result: Decodable {
        var userName: String
        var services: [String]
    }
}
