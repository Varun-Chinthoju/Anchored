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
        XCTAssertNil(manager.runtimeFocusThresholdOverride)
        XCTAssertEqual(manager.effectiveFocusThreshold, PreferencesManager.defaultFocusThreshold)
        XCTAssertFalse(manager.launchAtLogin)
        XCTAssertTrue(manager.enableSmartNudges)
        XCTAssertTrue(manager.focusPromptExperimentEnabled)
        XCTAssertEqual(manager.selectedThemeID, ThemeCatalog.defaultThemeID)
        XCTAssertEqual(manager.selectedThemePalette, ThemePalette.baldr)
        
        // Cloud classification defaults
        XCTAssertFalse(manager.enableCloudClassification)
        XCTAssertEqual(manager.cloudProvider, 0)
        XCTAssertEqual(manager.cloudModel, "gemini-2.5-flash")
        XCTAssertEqual(manager.cloudEndpoint, "https://generativelanguage.googleapis.com/v1beta/models/")
    }
    
    func testInitializationWithStoredSettings() {
        // Given stored values in UserDefaults and enabled login item status
        testDefaults.set(15, forKey: PreferencesManager.Keys.countdownDuration)
        testDefaults.set(300.0, forKey: PreferencesManager.Keys.focusThreshold)
        testDefaults.set(false, forKey: PreferencesManager.Keys.enableSmartNudges)
        testDefaults.set(false, forKey: PreferencesManager.Keys.focusPromptExperimentEnabled)
        testDefaults.set(true, forKey: PreferencesManager.Keys.enableCloudClassification)
        testDefaults.set(1, forKey: PreferencesManager.Keys.cloudProvider)
        testDefaults.set("gpt-4-custom", forKey: PreferencesManager.Keys.cloudModel)
        testDefaults.set("https://custom.openai.com/v1", forKey: PreferencesManager.Keys.cloudEndpoint)
        mockService.status = .enabled
        
        // When initializing PreferencesManager
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // Then it should load the stored values and status
        XCTAssertEqual(manager.countdownDuration, 15)
        XCTAssertEqual(manager.focusThreshold, 300.0)
        XCTAssertNil(manager.runtimeFocusThresholdOverride)
        XCTAssertEqual(manager.effectiveFocusThreshold, 300.0)
        XCTAssertTrue(manager.launchAtLogin)
        XCTAssertFalse(manager.enableSmartNudges)
        XCTAssertFalse(manager.focusPromptExperimentEnabled)
        
        // Cloud classification loaded values
        XCTAssertTrue(manager.enableCloudClassification)
        XCTAssertEqual(manager.cloudProvider, 1)
        XCTAssertEqual(manager.cloudModel, "gpt-4-custom")
        XCTAssertEqual(manager.cloudEndpoint, "https://custom.openai.com/v1")
    }

    func testRuntimeFocusThresholdOverrideWinsForEngineUse() {
        testDefaults.set(300.0, forKey: PreferencesManager.Keys.focusThreshold)
        testDefaults.set(5.0, forKey: PreferencesManager.Keys.focusThresholdOverride)

        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        XCTAssertEqual(manager.focusThreshold, 300.0)
        XCTAssertEqual(manager.runtimeFocusThresholdOverride, 5.0)
        XCTAssertEqual(manager.effectiveFocusThreshold, 5.0)
    }
    
    func testCountdownDurationClamping() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // When setting a value within range
        manager.countdownDuration = 12
        XCTAssertEqual(manager.countdownDuration, 12)
        XCTAssertEqual(testDefaults.integer(forKey: PreferencesManager.Keys.countdownDuration), 12)
        
        // When setting a value below range
        manager.countdownDuration = -5
        XCTAssertEqual(manager.countdownDuration, 0) // clamped to 0
        XCTAssertEqual(testDefaults.integer(forKey: PreferencesManager.Keys.countdownDuration), 0)
        
        // When setting a value above range
        manager.countdownDuration = 4000
        XCTAssertEqual(manager.countdownDuration, 3600) // clamped to 3600
        XCTAssertEqual(testDefaults.integer(forKey: PreferencesManager.Keys.countdownDuration), 3600)
    }
    
    func testFocusThresholdPersistence() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // When changing focusThreshold
        manager.focusThreshold = 120.0
        
        // Then it should update the property and persist to defaults
        XCTAssertEqual(manager.focusThreshold, 120.0)
        XCTAssertEqual(testDefaults.double(forKey: PreferencesManager.Keys.focusThreshold), 120.0)
    }

    func testThemeSelectionPersistence() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.selectedThemeID = "thor"

        XCTAssertEqual(manager.selectedThemeID, "thor")
        XCTAssertEqual(testDefaults.string(forKey: PreferencesManager.Keys.selectedThemeID), "thor")
        XCTAssertEqual(manager.selectedThemePalette.accent.hex, ThemeCatalog.theme(for: "thor").primary.stops.first?.hex)

        let reloaded = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        XCTAssertEqual(reloaded.selectedThemeID, "thor")
        XCTAssertEqual(reloaded.selectedTheme.name, "Thor")
        XCTAssertEqual(reloaded.selectedThemePalette.parchment.hex, ThemePalette.baldr.parchment.hex)
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
    
    func testCloudPreferencesMutation() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // Mutate enableCloudClassification
        manager.enableCloudClassification = true
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.enableCloudClassification))
        
        // Mutate cloudProvider
        manager.cloudProvider = 1
        XCTAssertEqual(testDefaults.integer(forKey: PreferencesManager.Keys.cloudProvider), 1)
        
        // Mutate cloudModel
        manager.cloudModel = "gpt-4-custom"
        XCTAssertEqual(testDefaults.string(forKey: PreferencesManager.Keys.cloudModel), "gpt-4-custom")
        
        // Mutate cloudEndpoint
        manager.cloudEndpoint = "https://custom.openai.com/v1"
        XCTAssertEqual(testDefaults.string(forKey: PreferencesManager.Keys.cloudEndpoint), "https://custom.openai.com/v1")
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
