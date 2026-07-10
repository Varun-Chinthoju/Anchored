import XCTest
@testable import Anchored

final class KeychainHelperTests: XCTestCase {
    
    private let testProvider = "test-provider-\(UUID().uuidString)"
    
    override func setUp() {
        super.setUp()
        KeychainHelper.useMockOnly = true
        KeychainHelper.mockKeys = [:]
    }

    override func tearDownWithError() throws {
        try? KeychainHelper.deleteKey(forProvider: testProvider)
        KeychainHelper.useMockOnly = false
        KeychainHelper.mockKeys = [:]
        try super.tearDownWithError()
    }
    
    func testKeychainSaveLoadDelete() throws {
        // 1. Ensure no key initially
        let initialKey = KeychainHelper.loadKey(forProvider: testProvider)
        XCTAssertNil(initialKey)
        
        // 2. Save a key
        let testKey = "super-secret-api-key-123"
        try KeychainHelper.saveKey(testKey, forProvider: testProvider)
        
        // 3. Load it and verify
        let loadedKey = KeychainHelper.loadKey(forProvider: testProvider)
        XCTAssertEqual(loadedKey, testKey)
        
        // 4. Update the key
        let updatedKey = "new-secret-api-key-456"
        try KeychainHelper.saveKey(updatedKey, forProvider: testProvider)
        
        // 5. Load and verify updated value
        let loadedUpdatedKey = KeychainHelper.loadKey(forProvider: testProvider)
        XCTAssertEqual(loadedUpdatedKey, updatedKey)
        
        // 6. Delete the key
        try KeychainHelper.deleteKey(forProvider: testProvider)
        
        // 7. Verify it's gone
        let finalKey = KeychainHelper.loadKey(forProvider: testProvider)
        XCTAssertNil(finalKey)
    }
}
