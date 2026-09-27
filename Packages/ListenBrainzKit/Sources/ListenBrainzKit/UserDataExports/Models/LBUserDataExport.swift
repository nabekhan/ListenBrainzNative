// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A server-generated archive of the authenticated user's ListenBrainz data.
///
/// Use `status` for application logic. `progress` is descriptive server text
/// and may change without notice.
public struct LBUserDataExport: Decodable, Equatable, Identifiable, Sendable {
    public let exportID: Int
    public let type: String
    public let availableUntil: Date?
    public let created: Date
    public let progress: String
    public let status: LBUserDataExportStatus
    public let filename: String?
    /// Inclusive Unix timestamp bounds for listens included in this archive.
    public let startTime: Int?
    /// Inclusive Unix timestamp bounds for listens included in this archive.
    public let endTime: Int?

    public var id: Int { exportID }

    enum CodingKeys: String, CodingKey {
        // `JSONDecoder.ListenBrainz` converts `export_id` to `exportId`.
        case exportID = "exportId"
        case type
        case availableUntil
        case created
        case progress
        case status
        case filename
        case startTime
        case endTime
    }

    public init(
        exportID: Int,
        type: String,
        availableUntil: Date?,
        created: Date,
        progress: String,
        status: LBUserDataExportStatus,
        filename: String?,
        startTime: Int?,
        endTime: Int?
    ) {
        self.exportID = exportID
        self.type = type
        self.availableUntil = availableUntil
        self.created = created
        self.progress = progress
        self.status = status
        self.filename = filename
        self.startTime = startTime
        self.endTime = endTime
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportID = try container.decode(Int.self, forKey: .exportID)
        type = try container.decode(String.self, forKey: .type)
        progress = try container.decode(String.self, forKey: .progress)
        status = try container.decode(LBUserDataExportStatus.self, forKey: .status)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        startTime = try container.decodeIfPresent(Int.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Int.self, forKey: .endTime)

        let createdString = try container.decode(String.self, forKey: .created)
        guard let decodedCreated = Self.decodeISO8601(createdString) else {
            throw DecodingError.dataCorruptedError(forKey: .created, in: container, debugDescription: "Expected an ISO 8601 date")
        }
        created = decodedCreated

        if let availableString = try container.decodeIfPresent(String.self, forKey: .availableUntil) {
            guard let decodedAvailable = Self.decodeISO8601(availableString) else {
                throw DecodingError.dataCorruptedError(forKey: .availableUntil, in: container, debugDescription: "Expected an ISO 8601 date")
            }
            availableUntil = decodedAvailable
        } else {
            availableUntil = nil
        }
    }

    private static func decodeISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

/// The machine-readable lifecycle state of a user-data export.
public enum LBUserDataExportStatus: Equatable, Sendable {
    case waiting
    case inProgress
    case completed
    case failed
    /// Preserves a future server status rather than making a list request fail.
    case unknown(String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed: true
        case .waiting, .inProgress, .unknown: false
        }
    }

    /// Only a completed export can be downloaded. Unknown future states are
    /// deliberately treated as unavailable until the client understands them.
    public var canDownload: Bool {
        if case .completed = self { return true }
        return false
    }
}

extension LBUserDataExportStatus: Decodable {
    public init(from decoder: any Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "waiting": self = .waiting
        case "in_progress": self = .inProgress
        case "completed": self = .completed
        case "failed": self = .failed
        case let status: self = .unknown(status)
        }
    }
}

/// Inclusive Unix timestamp bounds for a listen-history export.
public struct LBUserDataExportRange: Equatable, Sendable {
    public let startTime: Int?
    public let endTime: Int?

    /// Creates a bounded or open-ended export range.
    ///
    /// At least one bound is required; use `createFull()` for the whole archive.
    public init(startTime: Int? = nil, endTime: Int? = nil) throws {
        guard startTime != nil || endTime != nil,
              startTime == nil || endTime == nil || startTime! <= endTime!
        else { throw LBError.invalidParam }
        self.startTime = startTime
        self.endTime = endTime
    }
}
