import Foundation
import Security

/// The only persisted authenticated session representation. Keeping the
/// canonical username beside its token prevents a torn Keychain/UserDefaults
/// restore from activating credentials for the wrong profile.
struct StoredCredential: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let username: String
    let token: String

    init(username: String, token: String) {
        self.version = Self.currentVersion
        self.username = username
        self.token = token
    }
}

enum LoadedCredential: Equatable, Sendable {
    case account(StoredCredential)
    case legacyToken(String)
}

protocol CredentialStoring: Sendable {
    func load() async throws -> LoadedCredential?
    func save(_ credential: StoredCredential) async throws
    func delete() async throws
}

struct KeychainCredentialStore: CredentialStoring {
    private static let service = "dev.nabekhan.listenbrainznative"
    private static let account = "listenbrainz-token"

    func load() async throws -> LoadedCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }

        if let credential = try? JSONDecoder().decode(StoredCredential.self, from: data) {
            guard credential.version == StoredCredential.currentVersion,
                  !credential.username.isEmpty,
                  !credential.token.isEmpty
            else { throw CredentialStoreError.unrecognizedCredential }
            return .account(credential)
        }
        guard let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw CredentialStoreError.unrecognizedCredential
        }
        return .legacyToken(token)
    }

    func save(_ credential: StoredCredential) async throws {
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus)
        }
        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func delete() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

enum CredentialStoreError: LocalizedError {
    case unrecognizedCredential

    var errorDescription: String? { String(localized: "We couldn’t restore your saved sign-in. Sign in again.") }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? }
}
