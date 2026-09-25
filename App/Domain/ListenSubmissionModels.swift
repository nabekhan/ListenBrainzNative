import CryptoKit
import Foundation

enum ListenSubmissionMode: String, CaseIterable, Identifiable, Sendable {
    case listen
    case playingNow

    var id: Self { self }
}

/// The intentionally small, explicit submission payload. It is kept separate
/// from display models so writing a listen never triggers metadata reads.
struct ListenSubmissionPayload: Hashable, Sendable {
    let mode: ListenSubmissionMode
    let artist: String
    let track: String
    let release: String?
    let listenedAt: Date?
    let artistMBIDs: [UUID]
    let recordingMBID: UUID?
    let releaseMBID: UUID?
    let releaseGroupMBID: UUID?
    let durationMilliseconds: Int?
    let appVersion: String

    /// A stable identity for one logical submission. Transport-only metadata,
    /// such as the app version, is deliberately excluded so an app update
    /// cannot bypass a persisted replay barrier.
    var fingerprint: String {
        let fields = [
            mode.rawValue, artist, track, release ?? "", listenedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "",
            artistMBIDs.map { $0.uuidString.lowercased() }.joined(separator: ","),
            recordingMBID?.uuidString.lowercased() ?? "", releaseMBID?.uuidString.lowercased() ?? "",
            releaseGroupMBID?.uuidString.lowercased() ?? "", durationMilliseconds.map(String.init) ?? ""
        ].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(fields.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ListenSubmissionDraft: Sendable {
    static let maximumFieldLength = 500
    static let maximumDurationMilliseconds = 2_073_600_000
    static let minimumDate = Date(timeIntervalSince1970: 1_033_430_400)

    private struct CanonicalText: Equatable, Sendable {
        let track: String
        let artist: String
        let release: String
    }

    var mode: ListenSubmissionMode = .listen
    var track = ""
    var artist = ""
    var release = ""
    var playbackStartedAt = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
    var artistMBIDs: [UUID] = []
    var recordingMBID: UUID?
    var releaseMBID: UUID?
    var releaseGroupMBID: UUID?
    var durationMilliseconds: Int?
    private var canonicalText: CanonicalText? = nil

    init(recording: Recording? = nil, mode: ListenSubmissionMode = .listen) {
        self.mode = mode
        guard let recording else { return }
        track = recording.title
        artist = recording.artistName
        release = recording.releaseTitle ?? ""
        artistMBIDs = recording.artistMBIDs
        recordingMBID = recording.identity.mbid
        releaseMBID = recording.releaseMBID
        releaseGroupMBID = recording.releaseGroupMBID
        durationMilliseconds = recording.durationMilliseconds
        canonicalText = normalizedText
    }

    mutating func clampTextAndInvalidateIdentity() {
        track = String(track.prefix(Self.maximumFieldLength))
        artist = String(artist.prefix(Self.maximumFieldLength))
        release = String(release.prefix(Self.maximumFieldLength))
        guard canonicalText == normalizedText else {
            canonicalText = nil
            artistMBIDs = []
            recordingMBID = nil
            releaseMBID = nil
            releaseGroupMBID = nil
            durationMilliseconds = nil
            return
        }
    }

    func payload(appVersion: String, now: Date = .now) throws -> ListenSubmissionPayload {
        let safeTrack = String(track.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumFieldLength))
        let safeArtist = String(artist.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumFieldLength))
        let safeRelease = String(release.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumFieldLength))
        guard !safeTrack.isEmpty else { throw ListenSubmissionValidationError.trackRequired }
        guard !safeArtist.isEmpty else { throw ListenSubmissionValidationError.artistRequired }
        let timestamp: Date?
        if mode == .listen {
            // The picker exposes minute precision, so the submitted value and
            // its replay identity use that same visible precision.
            let wholeMinute = Date(timeIntervalSince1970: floor(playbackStartedAt.timeIntervalSince1970 / 60) * 60)
            // ListenBrainz's current LISTEN_MINIMUM_DATE is 2002-10-01 UTC.
            guard wholeMinute >= Self.minimumDate else { throw ListenSubmissionValidationError.timestampTooEarly }
            guard wholeMinute <= now else { throw ListenSubmissionValidationError.timestampInFuture }
            timestamp = wholeMinute
        } else {
            timestamp = nil
        }
        let preservesCanonicalIdentity = canonicalText == normalizedText
        let safeDuration = durationMilliseconds.flatMap {
            (1...Self.maximumDurationMilliseconds).contains($0) ? $0 : nil
        }
        return .init(mode: mode, artist: safeArtist, track: safeTrack, release: safeRelease.isEmpty ? nil : safeRelease,
                     listenedAt: timestamp, artistMBIDs: preservesCanonicalIdentity ? artistMBIDs : [],
                     recordingMBID: preservesCanonicalIdentity ? recordingMBID : nil,
                     releaseMBID: preservesCanonicalIdentity ? releaseMBID : nil,
                     releaseGroupMBID: preservesCanonicalIdentity ? releaseGroupMBID : nil,
                     durationMilliseconds: preservesCanonicalIdentity ? safeDuration : nil, appVersion: appVersion)
    }

    private var normalizedText: CanonicalText {
        .init(
            track: String(track.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumFieldLength)),
            artist: String(artist.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumFieldLength)),
            release: String(release.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumFieldLength))
        )
    }
}

enum ListenSubmissionValidationError: LocalizedError, Equatable, Sendable {
    case trackRequired, artistRequired, timestampTooEarly, timestampInFuture, replayUnavailable
    var errorDescription: String? {
        switch self {
        case .trackRequired: String(localized: "Enter a track title.")
        case .artistRequired: String(localized: "Enter an artist.")
        case .timestampTooEarly: String(localized: "Choose a valid playback start time.")
        case .timestampInFuture: String(localized: "Choose a playback start time that is not in the future.")
        case .replayUnavailable: String(localized: "This listen can’t be sent again from this screen.")
        }
    }
}

enum ListenSubmissionError: LocalizedError, Equatable, Sendable {
    case rejected, authentication, forbidden, rateLimited(Int), indeterminate
    var errorDescription: String? {
        switch self {
        case .rejected:
            String(localized: "ListenBrainz couldn’t accept this listen. Check the details and try again.")
        case .authentication:
            String(localized: "Your ListenBrainz sign-in needs attention. Sign in again before sending a listen.")
        case .forbidden:
            String(localized: "Your ListenBrainz sign-in can’t send listens. Sign in again and try once more.")
        case let .rateLimited(seconds):
            String(localized: "ListenBrainz is busy. Try again in about \(seconds) seconds.")
        case .indeterminate:
            String(localized: "This request may have reached ListenBrainz. Check History or your profile before sending it again.")
        }
    }
}
