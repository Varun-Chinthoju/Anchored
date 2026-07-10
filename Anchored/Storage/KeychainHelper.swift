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
    
    /// Stubs/mocks for unit tests to bypass SecItem APIs
    public static var mockKeys: [String: String] = [:]
    
    public static func saveKey(_ key: String, forProvider provider: String) throws {
        mockKeys[provider.lowercased()] = key
        
        if NSClassFromString("XCTestCase") != nil {
            return
        }

        guard let data = key.data(using: .utf8) else {
            return
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
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
        
        if NSClassFromString("XCTestCase") != nil {
            return nil
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    public static func deleteKey(forProvider provider: String) throws {
        mockKeys.removeValue(forKey: provider.lowercased())
        
        if NSClassFromString("XCTestCase") != nil {
            return
        }

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
