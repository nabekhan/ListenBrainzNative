import Foundation

struct FollowingPinsPage: Hashable, Sendable {
    let username: String
    let pins: [PinnedRecording]
    let serverCount: Int
    let offset: Int
}

struct FollowingPinsPageKey: Hashable, Sendable {
    let username: String
    let count: Int
    let offset: Int
}

struct FollowingPinIdentity: Hashable, Sendable {
    let owner: String
    let rowID: Int

    init(_ pin: PinnedRecording) {
        owner = (pin.username ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        rowID = pin.rowID
    }
}

extension PinnedRecording {
    var followingPinIdentity: FollowingPinIdentity { FollowingPinIdentity(self) }
}

enum FollowingPinsPhase: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

enum FollowingPinsCaches {
    static let pages = EntityDetailCache<FollowingPinsPageKey, FollowingPinsPage>(
        timeToLive: 5 * 60,
        maximumEntryCount: 100
    )
}
