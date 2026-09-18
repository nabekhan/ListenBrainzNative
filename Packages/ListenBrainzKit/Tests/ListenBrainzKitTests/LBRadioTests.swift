// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import ListenBrainzKit

@Suite
struct LBRadioTests {
    @Test("Generated radio decodes JSPF tracks and feedback")
    func generatedPlaylist() async throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            RawGeneratedRadioResponse.self,
            from: Data(Self.generatedFixture.utf8)
        )
        let mock = MockAPIClient(result: .success(response))
        let generated = try await LBRadioClient(mock).generate(
            prompt: "  artist:(Björk) tag:(art pop)::or  ",
            mode: .medium
        )

        #expect(generated.title == "A curious mix")
        #expect(generated.annotation == "Made by LB Radio")
        #expect(generated.feedback == ["Using similar artists", "24 recordings selected"])
        #expect(generated.tracks.count == 2)

        let first = try #require(generated.tracks.first)
        #expect(first.title == "Hidden Place")
        #expect(first.artistCreditName == "Björk")
        #expect(first.releaseName == "Vespertine")
        #expect(first.durationMilliseconds == 329_000)
        #expect(first.recordingMBID == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        #expect(first.releaseMBID == UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        #expect(first.caaReleaseMBID == UUID(uuidString: "33333333-3333-4333-8333-333333333333"))

        let request = try #require(mock.request as? GeneratedRadioRequest)
        #expect(request.data.path == "/1/explore/lb-radio")
        #expect(request.data.method == .get)
        #expect(request.data.queryItems["prompt"] == ["artist:(Björk) tag:(art pop)::or"])
        #expect(request.data.queryItems["mode"] == ["medium"])
        #expect(request.data.statusErrors[400] == .badRequest)
        #expect(request.data.statusErrors[401] == .invalidAuth)
        #expect(request.data.statusErrors[403] == .forbidden)
    }

    @Test("Generated radio accepts the server's plural empty-track fallback")
    func pluralEmptyTracks() throws {
        let response = try JSONDecoder.ListenBrainz.decode(
            RawGeneratedRadioResponse.self,
            from: Data(#"{"payload":{"jspf":{"playlist":{"tracks":[]}},"feedback":null}}"#.utf8)
        )
        let generated = LBGeneratedRadio(raw: response)
        #expect(generated.title == nil)
        #expect(generated.tracks.isEmpty)
        #expect(generated.feedback.isEmpty)
    }

    @Test("Generated radio rejects an empty prompt before transport")
    func emptyPrompt() async {
        let mock = MockAPIClient(result: .failure(.unknownError))
        await #expect(throws: LBError.invalidParam) {
            _ = try await LBRadioClient(mock).generate(prompt: " \n ", mode: .easy)
        }
        #expect(mock.request == nil)
    }

    @Test("Generated radio prompt uses one encoded query value")
    func encodedPrompt() throws {
        let client = ListenBrainzAPIClient(
            token: "",
            root: URL(string: "https://example.invalid"),
            userAgent: "Tests"
        )
        let request = GeneratedRadioRequest(
            prompt: "artist:(Björk) tag:(dream pop)::or & more",
            mode: .hard
        )
        let url = try #require(try client.makeURLRequest(request).url)
        let values = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(values.filter { $0.name == "prompt" }.map(\.value) == ["artist:(Björk) tag:(dream pop)::or & more"])
        #expect(values.filter { $0.name == "mode" }.map(\.value) == ["hard"])
    }

    @Test("Malformed generated radio does not masquerade as an empty mix")
    func malformedResponse() {
        let request = GeneratedRadioRequest(prompt: "#ambient", mode: .easy)
        #expect(throws: DecodingError.self) {
            _ = try request.decodeResponse(
                Data(#"{"payload":{"feedback":[]}}"#.utf8),
                response: nil
            )
        }
    }

    private static let generatedFixture = #"""
    {
      "payload": {
        "jspf": {
          "playlist": {
            "title": "A curious mix",
            "annotation": "Made by LB Radio",
            "track": [
              {
                "title": "Hidden Place",
                "creator": "Björk",
                "album": "Vespertine",
                "duration": 329000,
                "identifier": ["https://musicbrainz.org/recording/11111111-1111-4111-8111-111111111111"],
                "extension": {
                  "https://musicbrainz.org/doc/jspf#track": {
                    "artist_identifiers": ["https://musicbrainz.org/artist/44444444-4444-4444-8444-444444444444"],
                    "release_identifier": "https://musicbrainz.org/release/22222222-2222-4222-8222-222222222222",
                    "additional_metadata": {
                      "caa_release_mbid": "33333333-3333-4333-8333-333333333333",
                      "caa_id": 42
                    }
                  }
                }
              },
              {
                "title": "Unmapped but visible",
                "creator": "Unknown Artist"
              }
            ]
          }
        },
        "feedback": ["Using similar artists", "24 recordings selected"]
      }
    }
    """#
}
