// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

enum StatsRankingRequestLimits {
    /// Large enough for the server's bounded ranking payloads while preventing
    /// an unexpected response from accumulating without limit in memory.
    static let maximumResponseBytes = 2 * 1_024 * 1_024
}
