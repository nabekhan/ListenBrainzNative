import Foundation

enum UserDataExportStatus: Hashable, Sendable {
    case waiting
    case inProgress
    case completed
    case failed
    case unknown

    var isPending: Bool {
        self == .waiting || self == .inProgress
    }

    var canDownload: Bool { self == .completed }
}

struct UserDataExportRange: Codable, Hashable, Sendable {
    let startTime: Int?
    let endTime: Int?

    static let all = UserDataExportRange(startTime: nil, endTime: nil)

    init(startTime: Int?, endTime: Int?) {
        self.startTime = startTime
        self.endTime = endTime
    }

    var isAllTime: Bool { startTime == nil && endTime == nil }
}

struct UserDataExportJob: Identifiable, Hashable, Sendable {
    let id: Int
    let createdAt: Date
    let availableUntil: Date?
    let range: UserDataExportRange
    let status: UserDataExportStatus
}

struct UserDataExportArchive: Hashable, Sendable {
    let exportID: Int
    let range: UserDataExportRange
    let downloadedAt: Date
    let byteCount: Int64
    let fileURL: URL
}
