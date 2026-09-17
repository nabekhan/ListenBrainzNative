// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import ListenBrainzKit
import Testing

@Suite struct LBMetadataTests {
    @Test("Release-group metadata uses its canonical terminal-slash endpoint")
    func releaseGroupCanonicalPath() {
        let mbid = UUID(uuidString: "6e335887-60ba-38f0-95af-fae7774336bf")!
        let request = MetadataReleaseGroupRequest(
            mbids: [mbid],
            including: [.artist, .tag, .release]
        )

        #expect(request.data.path == "/1/metadata/release_group/")
        #expect(request.data.preservesTrailingSlash)
        #expect(request.data.queryItems["release_group_mbids"] == [mbid.uuidString])
        #expect(request.data.queryItems["inc"] == ["artist tag release"])
    }

    @Test("Release-group dates retain MusicBrainz precision and decode correctly")
    func releaseGroupDate() throws {
        let value = try JSONDecoder.ListenBrainz.decode(
            LBReleaseGroupMeta.self,
            from: Data(#"{"caa_id":14926982777,"caa_release_mbid":"1a33443c-3fff-450f-8298-efbc65659d32","name":"In Rainbows","date":"2007-10-10","type":"Album"}"#.utf8)
        )

        #expect(value.dateString == "2007-10-10")
        #expect(value.caaId == 14_926_982_777)
        #expect(value.caaReleaseMbid == UUID(uuidString: "1a33443c-3fff-450f-8298-efbc65659d32"))
        let date = try #require(value.date)
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: date
        )
        #expect(components.year == 2007)
        #expect(components.month == 10)
        #expect(components.day == 10)
    }

    @Test("Manual mapping submission")
    func manualMap() async throws {
        let messyId = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let musicbrainzId = UUID(uuidString: "abababab-abab-abab-abab-abababababab")!

        let client = LBMetadataClient(MockAPIClient(result: .success(NoResult())))
        _ = try await client.submitManualMapping(msid: messyId, mbid: musicbrainzId)
        let request = try #require(((client.apiClient as? MockAPIClient)?.request as? MetadataSubmitMappingRequest)?.data)

        #expect(request.body?.recordingMsid == messyId)
        #expect(request.body?.recordingMbid == musicbrainzId)
    }

    @Test("LBManualMapping Decode")
    func decodeManualMap() async throws {
        let raw = """
        {"mapping": {"created": "Wed, 1 Jan 2025 00:00:00 GMT",
        "recording_msid": "12121212-1212-1212-1212-121212121212",
        "recording_mbid": "abababab-abab-abab-abab-abababababab",
         "user_id": 36427},
         "status": "ok"}
        """

        let mapping = try JSONDecoder.ListenBrainz.decode(LBManualMapping.self, from: raw.data(using: .utf8)!)
        #expect(mapping.msid.uuidString == "12121212-1212-1212-1212-121212121212")
        #expect(mapping.mbid.uuidString == "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")
    }
}
