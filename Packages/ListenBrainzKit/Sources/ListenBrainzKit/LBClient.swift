// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LBClient: Sendable {
    public let core: LBCoreClient
    public let metadata: LBMetadataClient
    public let recordings: LBRecordingsClient
    public let stats: LBStatisticsClient
    public let freshReleases: LBFreshReleasesClient
    public let recommendations: LBRecommendationsClient
    public let pins: LBPinsClient
    public let social: LBSocialClient

    public init(
        token: String,
        customRoot: URL? = nil,
        allowsTokenToCustomRoot: Bool = false,
        userAgent: String = "ListenBrainzKit/0.1.2"
    ) {
        let client = ListenBrainzAPIClient(
            token: token,
            root: customRoot,
            allowsTokenToCustomRoot: allowsTokenToCustomRoot,
            userAgent: userAgent
        )

        self.core = LBCoreClient(client)
        self.metadata = LBMetadataClient(client)
        self.recordings = LBRecordingsClient(client)
        self.stats = LBStatisticsClient(client)
        self.freshReleases = LBFreshReleasesClient(client)
        self.recommendations = LBRecommendationsClient(client)
        self.pins = LBPinsClient(client)
        self.social = LBSocialClient(client)
    }
}
