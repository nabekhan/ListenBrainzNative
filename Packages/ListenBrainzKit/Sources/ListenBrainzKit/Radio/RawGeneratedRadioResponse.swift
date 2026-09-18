// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

struct RawGeneratedRadioResponse: Decodable {
    let payload: Payload

    struct Payload: Decodable {
        let jspf: JSPF
        let feedback: [String]

        enum CodingKeys: String, CodingKey {
            case jspf
            case feedback
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            jspf = try values.decode(JSPF.self, forKey: .jspf)
            feedback = try values.decodeIfPresent([String].self, forKey: .feedback) ?? []
        }
    }

    struct JSPF: Decodable {
        let playlist: Playlist
    }

    struct Playlist: Decodable {
        let title: String?
        let annotation: String?
        let tracks: [RawPlaylistTrack]

        enum CodingKeys: String, CodingKey {
            case title
            case annotation
            case track
            case tracks
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            title = try values.decodeIfPresent(String.self, forKey: .title)
            annotation = try values.decodeIfPresent(String.self, forKey: .annotation)
            tracks = try values.decodeIfPresent([RawPlaylistTrack].self, forKey: .track)
                ?? values.decodeIfPresent([RawPlaylistTrack].self, forKey: .tracks)
                ?? []
        }
    }
}
