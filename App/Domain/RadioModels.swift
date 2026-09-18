import Foundation
import ListenBrainzKit

enum RadioPromptSource: String, CaseIterable, Identifiable, Sendable {
    case listening
    case recommendations
    case artist
    case tag
    case advanced

    var id: String { rawValue }
    var requiresInput: Bool { self == .artist || self == .tag || self == .advanced }

    func prompt(username: String, input: String) -> String? {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)

        switch self {
        case .listening:
            guard !username.isEmpty else { return nil }
            return "stats:\(username)::all_time"
        case .recommendations:
            guard !username.isEmpty else { return nil }
            return "recs:\(username)::unlistened"
        case .artist:
            guard Self.canWrap(input) else { return nil }
            return "artist:(\(input))"
        case .tag:
            guard Self.canWrap(input) else { return nil }
            return "tag:(\(input))"
        case .advanced:
            return input.count >= RadioGenerationOptions.minimumPromptLength ? input : nil
        }
    }

    private static func canWrap(_ value: String) -> Bool {
        value.count >= 2
            && !value.contains("(")
            && !value.contains(")")
            && !value.contains("\n")
            && !value.contains("\r")
    }
}

struct RadioGenerationOptions: Hashable, Sendable {
    static let minimumPromptLength = 4

    let prompt: String
    let mode: LBRadioMode

    init?(prompt: String, mode: LBRadioMode) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count >= Self.minimumPromptLength else { return nil }
        self.prompt = prompt
        self.mode = mode
    }

    var listenBrainzURL: URL? {
        var components = URLComponents(string: "https://listenbrainz.org/explore/lb-radio/")
        components?.queryItems = [
            URLQueryItem(name: "prompt", value: prompt),
            URLQueryItem(name: "mode", value: mode.rawValue),
        ]
        return components?.url
    }
}

struct RadioMix: Hashable, Sendable {
    let options: RadioGenerationOptions
    let title: String
    let annotation: String?
    let feedback: [String]
    let tracks: [PlaylistTrack]
    let metadataEnrichmentFailed: Bool
    let generatedAt: Date
}
