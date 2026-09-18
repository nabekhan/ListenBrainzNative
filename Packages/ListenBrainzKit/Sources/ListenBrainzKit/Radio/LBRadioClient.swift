// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Generates server-side ListenBrainz Radio playlists from Troi prompts.
public struct LBRadioClient: Sendable {
    let apiClient: any APIClient

    init(_ client: some APIClient) {
        self.apiClient = client
    }

    /// Generate one JSPF playlist from an LB Radio prompt.
    ///
    /// This endpoint requires an authenticated ListenBrainz client. The
    /// returned recording identities do not guarantee that playable audio can
    /// be resolved on the caller's device.
    public func generate(prompt: String, mode: LBRadioMode) async throws -> LBGeneratedRadio {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw LBError.invalidParam }

        let result = try await apiClient.execute(
            GeneratedRadioRequest(prompt: prompt, mode: mode)
        )
        return LBGeneratedRadio(raw: result)
    }
}
