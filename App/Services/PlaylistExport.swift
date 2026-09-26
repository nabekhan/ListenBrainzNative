import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Builds a fresh JSPF document from the already-loaded app model.
///
/// `PlaylistDetail` intentionally does not retain the raw server payload, so
/// this export preserves the normalized metadata and canonical identifiers the
/// app actually knows. It never hydrates missing fields or performs a request.
enum PlaylistJSPFEncoder {
    static let maximumTrackCount = 10_000
    private static let maximumEstimatedBytes = 24 * 1_024 * 1_024
    private static let maximumEncodedBytes = 32 * 1_024 * 1_024
    private static let recordingIdentifierBytes = "https://musicbrainz.org/recording/00000000-0000-0000-0000-000000000000".utf8.count
    private static let releaseIdentifierBytes = "https://musicbrainz.org/release/00000000-0000-0000-0000-000000000000".utf8.count
    private static let artistIdentifierBytes = "https://musicbrainz.org/artist/00000000-0000-0000-0000-000000000000".utf8.count

    static func data(for detail: PlaylistDetail) throws -> Data {
        try validate(detail)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]

        var data = try encoder.encode(Document(playlist: Playlist(detail)))
        guard data.count < maximumEncodedBytes else {
            throw PlaylistExportError.tooLarge
        }
        data.append(0x0A)
        return data
    }

    static func validate(_ detail: PlaylistDetail) throws {
        guard detail.tracks.count <= maximumTrackCount,
              estimatedBytes(for: detail) <= maximumEstimatedBytes
        else { throw PlaylistExportError.tooLarge }
    }

    private struct Document: Encodable {
        let playlist: Playlist
    }

    private struct Playlist: Encodable {
        let annotation: String?
        let creator: String
        let date: String?
        let identifier: String
        let title: String
        let extensionValue: PlaylistExtensions
        let tracks: [Track]

        enum CodingKeys: String, CodingKey {
            case annotation
            case creator
            case date
            case identifier
            case title
            case extensionValue = "extension"
            case tracks = "track"
        }

        init(_ detail: PlaylistDetail) {
            annotation = PlaylistJSPFEncoder.nonempty(detail.annotation)
            creator = detail.creator
            date = PlaylistJSPFEncoder.dateString(detail.createdAt)
            identifier = "https://listenbrainz.org/playlist/\(detail.mbid.uuidString.lowercased())"
            title = detail.title
            extensionValue = PlaylistExtensions(
                listenBrainz: PlaylistExtension(detail)
            )
            tracks = detail.tracks.map(Track.init)
        }
    }

    private struct PlaylistExtensions: Encodable {
        let listenBrainz: PlaylistExtension

        enum CodingKeys: String, CodingKey {
            case listenBrainz = "https://musicbrainz.org/doc/jspf#playlist"
        }
    }

    private struct PlaylistExtension: Encodable {
        let collaborators: [String]
        let copiedFrom: String?
        let copiedFromMBID: String?
        let createdFor: String?
        let creator: String
        let isPublic: Bool
        let lastModifiedAt: String?

        enum CodingKeys: String, CodingKey {
            case collaborators
            case copiedFrom = "copied_from"
            case copiedFromMBID = "copied_from_mbid"
            case createdFor = "created_for"
            case creator
            case isPublic = "public"
            case lastModifiedAt = "last_modified_at"
        }

        init(_ detail: PlaylistDetail) {
            collaborators = detail.collaborators.compactMap(PlaylistJSPFEncoder.nonempty)
            // The public JSPF extension documents `copied_from`; current
            // ListenBrainz payloads use `copied_from_mbid`. Portable exports
            // include both aliases only after strict canonicalization.
            copiedFrom = PlaylistJSPFEncoder.canonicalPlaylistURL(detail.copiedFrom)
            copiedFromMBID = copiedFrom
            createdFor = PlaylistJSPFEncoder.nonempty(detail.createdFor)
            creator = detail.creator
            isPublic = detail.isPublic
            lastModifiedAt = PlaylistJSPFEncoder.dateString(detail.lastModifiedAt)
        }
    }

    private struct Track: Encodable {
        let album: String?
        let creator: String?
        let duration: Int?
        let identifier: [String]?
        let title: String?
        let extensionValue: TrackExtensions?

        enum CodingKeys: String, CodingKey {
            case album
            case creator
            case duration
            case identifier
            case title
            case extensionValue = "extension"
        }

        init(_ track: PlaylistTrack) {
            let recording = track.recording
            album = PlaylistJSPFEncoder.nonempty(recording.releaseTitle)
            creator = PlaylistJSPFEncoder.nonempty(recording.artistName)
            duration = recording.durationMilliseconds.flatMap { $0 >= 0 ? $0 : nil }
            identifier = recording.identity.mbid.map {
                [PlaylistJSPFEncoder.musicBrainzURL(entity: "recording", mbid: $0)]
            }
            title = PlaylistJSPFEncoder.nonempty(recording.title)

            let trackExtension = TrackExtension(track)
            extensionValue = trackExtension.isEmpty
                ? nil
                : TrackExtensions(listenBrainz: trackExtension)
        }
    }

    private struct TrackExtensions: Encodable {
        let listenBrainz: TrackExtension

        enum CodingKeys: String, CodingKey {
            case listenBrainz = "https://musicbrainz.org/doc/jspf#track"
        }
    }

    private struct TrackExtension: Encodable {
        let addedAt: String?
        let addedBy: String?
        let artistIdentifiers: [String]
        let releaseIdentifier: String?

        enum CodingKeys: String, CodingKey {
            case addedAt = "added_at"
            case addedBy = "added_by"
            case artistIdentifiers = "artist_identifiers"
            case releaseIdentifier = "release_identifier"
        }

        init(_ track: PlaylistTrack) {
            addedAt = PlaylistJSPFEncoder.dateString(track.addedAt)
            addedBy = PlaylistJSPFEncoder.nonempty(track.addedBy)
            artistIdentifiers = track.recording.artistMBIDs.map {
                PlaylistJSPFEncoder.musicBrainzURL(entity: "artist", mbid: $0)
            }
            releaseIdentifier = track.recording.releaseMBID.map {
                PlaylistJSPFEncoder.musicBrainzURL(entity: "release", mbid: $0)
            }
        }

        var isEmpty: Bool {
            addedAt == nil
                && addedBy == nil
                && artistIdentifiers.isEmpty
                && releaseIdentifier == nil
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func estimatedBytes(for detail: PlaylistDetail) -> Int {
        // This intentionally overestimates. JSON control characters may expand
        // to six ASCII bytes (for example, `\u0000`), and this check must happen
        // before mapping the model into an encodable document.
        var total = 2_048 // JSPF structure, keys, punctuation, and fixed URLs.

        func add(_ bytes: Int) {
            guard total <= maximumEstimatedBytes else { return }
            let (next, overflow) = total.addingReportingOverflow(bytes)
            total = overflow ? Int.max : next
        }

        func addJSONValue(_ value: String?, occurrences: Int = 1) {
            guard let value else { return }
            let (escaped, escapedOverflow) = value.utf8.count.multipliedReportingOverflow(by: 6)
            let (totalBytes, occurrencesOverflow) = escaped.multipliedReportingOverflow(by: occurrences)
            add(escapedOverflow || occurrencesOverflow ? Int.max : totalBytes)
        }

        // `creator` is emitted at the JSPF and ListenBrainz-extension levels.
        addJSONValue(detail.title)
        addJSONValue(detail.creator, occurrences: 2)
        addJSONValue(detail.annotation)
        addJSONValue(detail.createdFor)
        addJSONValue(detail.copiedFrom, occurrences: 2)
        detail.collaborators.forEach { addJSONValue($0) }

        for track in detail.tracks where total <= maximumEstimatedBytes {
            let recording = track.recording
            add(512) // per-track JSPF structure and optional fixed fields.
            addJSONValue(recording.title)
            addJSONValue(recording.artistName)
            addJSONValue(recording.releaseTitle)
            addJSONValue(track.addedBy)

            if recording.identity.mbid != nil {
                add(recordingIdentifierBytes)
            }
            if recording.releaseMBID != nil {
                add(releaseIdentifierBytes)
            }
            let (artistBytes, artistOverflow) = artistIdentifierBytes
                .multipliedReportingOverflow(by: recording.artistMBIDs.count)
            add(artistOverflow ? Int.max : artistBytes)
        }
        return total
    }

    private static func dateString(_ value: Date?) -> String? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }

    private static func musicBrainzURL(entity: String, mbid: UUID) -> String {
        "https://musicbrainz.org/\(entity)/\(mbid.uuidString.lowercased())"
    }

    private static func canonicalPlaylistURL(_ value: String?) -> String? {
        guard let value = nonempty(value) else { return nil }
        if let mbid = UUID(uuidString: value) {
            return "https://listenbrainz.org/playlist/\(mbid.uuidString.lowercased())"
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "listenbrainz.org",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              url.query == nil,
              url.fragment == nil
        else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              components[0].lowercased() == "playlist",
              let mbid = UUID(uuidString: components[1])
        else { return nil }
        return "https://listenbrainz.org/playlist/\(mbid.uuidString.lowercased())"
    }
}

enum PlaylistExportError: LocalizedError, Equatable {
    case tooLarge

    var errorDescription: String? {
        String(localized: "This playlist is too large to export on this device.")
    }
}

enum PlaylistExportStaging {
    private static let directoryName = "Brainz-Shared-Playlists"
    private static let staleAge: TimeInterval = 24 * 60 * 60

    static func cleanupStaleFiles(
        in root: URL? = nil,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        let root = root ?? defaultRoot(fileManager: fileManager)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = now.addingTimeInterval(-staleAge)
        for url in contents {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey]
            ),
            values.isDirectory == true,
            let modifiedAt = values.contentModificationDate,
            modifiedAt < cutoff
            else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    static func stage(
        _ item: PlaylistJSPFShareItem,
        in root: URL? = nil,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = root ?? defaultRoot(fileManager: fileManager)
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        cleanupStaleFiles(in: root, now: now, fileManager: fileManager)

        let directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let url = directory.appending(path: item.fileName)
        try PlaylistJSPFEncoder.data(for: item.detail).write(
            to: url,
            options: [.atomic, .completeFileProtection]
        )
        return url
    }

    private static func defaultRoot(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appending(path: directoryName, directoryHint: .isDirectory)
    }
}

struct PlaylistJSPFShareItem: Transferable, Sendable {
    let detail: PlaylistDetail
    let fileName: String

    init(detail: PlaylistDetail) {
        self.detail = detail
        fileName = Self.safeFileName(detail.title)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            SentTransferredFile(try PlaylistExportStaging.stage(item))
        }
    }

    private static func safeFileName(_ value: String) -> String {
        let limit = 180
        let maximumInputScalars = 720
        var stem = ""
        stem.reserveCapacity(limit)
        var byteCount = 0
        var lastWasHyphen = false

        // Stop at the bounded output prefix. Mapping the whole title first would
        // temporarily duplicate arbitrarily large untrusted metadata.
        for scalar in value.unicodeScalars.prefix(maximumInputScalars) {
            let permitted = CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
            let replacement = permitted ? String(scalar) : "-"
            if replacement == "-", (stem.isEmpty || lastWasHyphen) {
                continue
            }

            let replacementBytes = replacement.utf8.count
            guard byteCount + replacementBytes <= limit else { break }
            stem.append(contentsOf: replacement)
            byteCount += replacementBytes
            lastWasHyphen = replacement == "-"
        }

        while stem.last == "-" || stem.last == "_" {
            stem.removeLast()
        }
        return "\(stem.isEmpty ? "ListenBrainz-playlist" : stem).jspf.json"
    }
}
