import XCTest
import Combine
import ServiceManagement
@testable import Anchored

final class PreferencesManagerTests: XCTestCase {
    
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var mockService: MockLoginItemService!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        suiteName = "com.varun.Anchored.PreferencesManagerTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        mockService = MockLoginItemService()
        cancellables = []
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        mockService = nil
        cancellables = nil
        super.tearDown()
    }
    
    func testDefaultsAndInitialization() {
        // Given a clean UserDefaults and a mock service that returns notRegistered
        mockService.status = .notRegistered
        
        // When initializing PreferencesManager
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // Then it should have default values
        XCTAssertEqual(manager.countdownDuration, PreferencesManager.defaultCountdownDuration)
        XCTAssertEqual(manager.focusThreshold, PreferencesManager.defaultFocusThreshold)
        XCTAssertFalse(manager.launchAtLogin)
        XCTAssertTrue(manager.enableSmartNudges)
    }
    
    func testInitializationWithStoredSettings() {
        // Given stored values in UserDefaults and enabled login item status
        testDefaults.set(15, forKey: PreferencesManager.Keys.countdownDuration)
        testDefaults.set(300.0, forKey: PreferencesManager.Keys.focusThreshold)
        testDefaults.set(false, forKey: PreferencesManager.Keys.enableSmartNudges)
        mockService.status = .enabled
        
        // When initializing PreferencesManager
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // Then it should load the stored values and status
        XCTAssertEqual(manager.countdownDuration, 15)
        XCTAssertEqual(manager.focusThreshold, 300.0)
        XCTAssertTrue(manager.launchAtLogin)
        XCTAssertFalse(manager.enableSmartNudges)
    }
    
    func testCountdownDurationClamping() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // When setting a value within range
        manager.countdownDuration = 12
        XCTAssertEqual(manager.countdownDuration, 12)
        XCTAssertEqual(testDefaults.integer(forKey: PreferencesManager.Keys.countdownDuration), 12)
        
        // When setting a value below range
        manager.countdownDuration = 2
        XCTAssertEqual(manager.countdownDuration, 5) // clamped to 5
        XCTAssertEqual(testDefaults.integer(forKey: PreferencesManager.Keys.countdownDuration), 5)
        
        // When setting a value above range
        manager.countdownDuration = 25
        XCTAssertEqual(manager.countdownDuration, 20) // clamped to 20
        XCTAssertEqual(testDefaults.integer(forKey: PreferencesManager.Keys.countdownDuration), 20)
    }
    
    func testFocusThresholdPersistence() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // When changing focusThreshold
        manager.focusThreshold = 120.0
        
        // Then it should update the property and persist to defaults
        XCTAssertEqual(manager.focusThreshold, 120.0)
        XCTAssertEqual(testDefaults.double(forKey: PreferencesManager.Keys.focusThreshold), 120.0)
    }
    
    func testToggleLaunchAtLoginSuccessful() {
        // Given an unregistered state
        mockService.status = .notRegistered
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        XCTAssertFalse(manager.launchAtLogin)
        
        // When toggling to true
        manager.launchAtLogin = true
        
        // Then it should call register on the service
        XCTAssertEqual(mockService.registerCalledCount, 1)
        XCTAssertEqual(mockService.unregisterCalledCount, 0)
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.launchAtLogin))
        
        // When toggling to false
        manager.launchAtLogin = false
        
        // Then it should call unregister on the service
        XCTAssertEqual(mockService.registerCalledCount, 1)
        XCTAssertEqual(mockService.unregisterCalledCount, 1)
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.launchAtLogin))
    }
    
    func testToggleLaunchAtLoginRegisterFailure() {
        // Given an unregistered state, and register throws error
        mockService.status = .notRegistered
        mockService.registerErrorToThrow = NSError(domain: "test", code: 1, userInfo: nil)
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        let expectation = XCTestExpectation(description: "launchAtLogin reverts to false on failure")
        
        // Listen to changes on launchAtLogin
        manager.$launchAtLogin
            .dropFirst() // ignore initial value
            .sink { enabled in
                if !enabled {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When toggling to true
        manager.launchAtLogin = true
        
        // Then it calls register and then reverts launchAtLogin back to false asynchronously
        XCTAssertEqual(mockService.registerCalledCount, 1)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(manager.launchAtLogin)
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.launchAtLogin))
    }
    
    func testToggleLaunchAtLoginUnregisterFailure() {
        // Given a registered state, and unregister throws error
        mockService.status = .enabled
        mockService.unregisterErrorToThrow = NSError(domain: "test", code: 2, userInfo: nil)
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        XCTAssertTrue(manager.launchAtLogin)
        
        let expectation = XCTestExpectation(description: "launchAtLogin reverts to true on failure")
        
        // Listen to changes on launchAtLogin
        manager.$launchAtLogin
            .dropFirst() // ignore initial value (which is true)
            .sink { enabled in
                if enabled {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When toggling to false
        manager.launchAtLogin = false
        
        // Then it calls unregister and then reverts launchAtLogin back to true asynchronously
        XCTAssertEqual(mockService.unregisterCalledCount, 1)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(manager.launchAtLogin)
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.launchAtLogin))
    }
}

// MARK: - Mock Login Item Service
private class MockLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    
    var registerCalledCount = 0
    var unregisterCalledCount = 0
    
    var registerErrorToThrow: Error?
    var unregisterErrorToThrow: Error?
    
    func register() throws {
        registerCalledCount += 1
        if let error = registerErrorToThrow {
            throw error
        }
        status = .enabled
    }
    
    func unregister() throws {
        unregisterCalledCount += 1
        if let error = unregisterErrorToThrow {
            throw error
        }
        status = .notRegistered
    }
}
