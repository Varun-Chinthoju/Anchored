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

    internal static var mockKeys: [String: String] = [:]
    public static var useMockOnly = false
    private static var cachedKeys: [String: String] = [:]
    private static let cacheLock = NSLock()

    private static func normalizedProvider(_ provider: String) -> String {
        provider.lowercased()
    }

    private static func cachedKey(forProvider provider: String) -> String? {
        let normalized = normalizedProvider(provider)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedKeys[normalized]
    }

    private static func storeCachedKey(_ key: String?, forProvider provider: String) {
        let normalized = normalizedProvider(provider)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let key {
            cachedKeys[normalized] = key
        } else {
            cachedKeys.removeValue(forKey: normalized)
        }
    }

    public static func saveKey(_ key: String, forProvider provider: String) throws {
        let normalized = normalizedProvider(provider)
        if useMockOnly {
            mockKeys[normalized] = key
            storeCachedKey(key, forProvider: provider)
            return
        }
        mockKeys.removeValue(forKey: normalized)
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
            storeCachedKey(key, forProvider: provider)
        } else if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.unhandledError(status: addStatus)
            }
            storeCachedKey(key, forProvider: provider)
        } else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    public static func loadKey(forProvider provider: String) -> String? {
        if useMockOnly {
            return mockKeys[normalizedProvider(provider)]
        }

        if let cached = cachedKey(forProvider: provider) {
            return cached
        }

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
            let loaded = String(data: data, encoding: .utf8)
            if let loaded {
                storeCachedKey(loaded, forProvider: provider)
            }
            return loaded
        }
        return nil
    }

    public static func deleteKey(forProvider provider: String) throws {
        let normalized = normalizedProvider(provider)
        if useMockOnly {
            mockKeys.removeValue(forKey: normalized)
            storeCachedKey(nil, forProvider: provider)
            return
        }

        mockKeys.removeValue(forKey: normalized)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandledError(status: status)
        }
        storeCachedKey(nil, forProvider: provider)
    }

    internal static func clearMockKeys() {
        mockKeys.removeAll()
    }

    internal static func clearCachedKeys() {
        cacheLock.lock()
        cachedKeys.removeAll()
        cacheLock.unlock()
    }
}
