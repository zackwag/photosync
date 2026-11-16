import Foundation
import Security
import SkylightClient

/// Wraps a Skylight token and device fingerprint for Keychain storage.
public struct SkylightCredentials: Codable, Sendable {
    public var token: Token
    public var fingerprint: String

    public init(token: Token, fingerprint: String) {
        self.token = token
        self.fingerprint = fingerprint
    }
}

/// Keychain helpers for Skylight credentials.
public enum CredentialStore {
    private static let service = "photosync"
    private static let account = "skylight"

    /// Loads credentials from the Keychain.
    public static func load() throws -> SkylightCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialError.notFound
        }
        return try JSONDecoder().decode(SkylightCredentials.self, from: data)
    }

    /// Saves credentials to the Keychain (adds or updates).
    public static func save(_ creds: SkylightCredentials) throws {
        let data = try JSONEncoder().encode(creds)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialError.saveFailed(updateStatus)
        }
    }

    /// Deletes credentials from the Keychain.
    public static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.deleteFailed(status)
        }
    }
}

public enum CredentialError: Error, LocalizedError {
    case notFound
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "no Skylight credentials found — run `photosync login` first"
        case .saveFailed(let status):
            "failed to save credentials to Keychain (OSStatus \(status))"
        case .deleteFailed(let status):
            "failed to delete credentials from Keychain (OSStatus \(status))"
        }
    }
}
