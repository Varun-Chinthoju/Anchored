import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case duplicateItem
    case itemNotFound
    case unhandledError(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "The item already exists in the Keychain."
        case .itemNotFound:
            return "The item was not found in the Keychain."
        case .unhandledError(let status):
            if let message = SecCopyErrorMessageString(status, nil) as? String {
                return "Keychain error: \(message) (code: \(status))"
            }
            return "Keychain error with OSStatus: \(status)"
        }
    }
}

public struct KeychainHelper {
    public static let service = "com.varun.Anchored.cloud-ai"

    /// In-memory overlay for tests / custom-keychain injection; production uses Security framework.
    public static var mockKeys: [String: String] = [:]
    /// When true, bypass Security framework entirely (for unit tests). Set via test setup, not via XCTest detection.
    public static var useMockOnly = false

    public static func saveKey(_ key: String, forProvider provider: String) throws {
        mockKeys[provider.lowercased()] = key
        if useMockOnly { return }
        guard let data = key.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainError.unhandledError(status: updateStatus)
            }
        } else if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.unhandledError(status: addStatus)
            }
        } else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    public static func loadKey(forProvider provider: String) -> String? {
        if let mock = mockKeys[provider.lowercased()] {
            return mock
        }
        if useMockOnly { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        if status == errSecSuccess, let data = ref as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    public static func deleteKey(forProvider provider: String) throws {
        mockKeys.removeValue(forKey: provider.lowercased())
        if useMockOnly { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandledError(status: status)
        }
    }
}
