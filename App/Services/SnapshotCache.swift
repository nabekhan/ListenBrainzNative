import Foundation

actor SnapshotCache {
    static let shared = SnapshotCache()

    private let fileManager: FileManager
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var activeLeases: [String: UUID] = [:]

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager
        let root = rootDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = root.appending(path: "ListenBrainzNative", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func beginSession(username: String) -> UUID {
        let lease = UUID()
        activeLeases[username] = lease
        return lease
    }

    func load(username: String, lease: UUID) -> ListeningSnapshot? {
        guard activeLeases[username] == lease else { return nil }
        guard let data = try? Data(contentsOf: fileURL(username: username)) else { return nil }
        return try? decoder.decode(ListeningSnapshot.self, from: data)
    }

    func save(_ snapshot: ListeningSnapshot, username: String, lease: UUID) {
        guard activeLeases[username] == lease else { return }
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL(username: username), options: .atomic)
    }

    func invalidate(username: String) throws {
        activeLeases.removeValue(forKey: username)
        let url = fileURL(username: username)
        guard fileManager.fileExists(atPath: url.path()) else { return }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(username: String) -> URL {
        let safe = Data(username.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appending(path: "\(safe).json")
    }
}
