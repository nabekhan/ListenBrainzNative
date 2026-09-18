// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

struct GeneratedRadioRequest: APIRequest {
    typealias Result = RawGeneratedRadioResponse

    let data: APIRequestData<NoBody>

    init(prompt: String, mode: LBRadioMode) {
        data = .init(
            path: "/1/explore/lb-radio",
            method: .get,
            queryItems: [
                "prompt": [prompt],
                "mode": [mode.rawValue],
            ],
            statusErrors: [
                400: .badRequest,
                401: .invalidAuth,
                403: .forbidden,
            ]
        )
    }
}
