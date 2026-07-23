import XCTest
import Combine
import ServiceManagement
import Darwin
@testable import Anchored

final class PreferencesManagerTests: XCTestCase {
    private let runtimeFocusThresholdOverrideEnvironmentVariable = "ANCHORED_ENABLE_RUNTIME_FOCUS_THRESHOLD_OVERRIDE"
    
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
        XCTAssertEqual(PreferencesManager.defaultCountdownDuration, 30)
        XCTAssertEqual(manager.countdownDuration, PreferencesManager.defaultCountdownDuration)
        XCTAssertEqual(manager.focusThreshold, PreferencesManager.defaultFocusThreshold)
        XCTAssertEqual(manager.automaticSessionDuration, PreferencesManager.defaultAutomaticSessionDuration)
        XCTAssertNil(manager.runtimeFocusThresholdOverride)
        XCTAssertEqual(manager.effectiveFocusThreshold, PreferencesManager.defaultFocusThreshold)
        XCTAssertFalse(manager.launchAtLogin)
        XCTAssertFalse(manager.commitmentLockEnabled)
        XCTAssertTrue(manager.enableSmartNudges)
        XCTAssertTrue(manager.showCountdownPill)
        XCTAssertTrue(manager.focusPromptExperimentEnabled)
        XCTAssertEqual(manager.selectedThemeID, ThemeCatalog.defaultThemeID)
        XCTAssertEqual(manager.selectedThemePalette, ThemePalette.baldr)
        XCTAssertFalse(manager.classificationFeedbackEnabled)
        XCTAssertFalse(manager.interactionSummaryEnabled)
        XCTAssertFalse(manager.enableLocalTextClassification)
        XCTAssertEqual(manager.localTextModel, PreferencesManager.defaultLocalTextModel)
        XCTAssertFalse(manager.sessionSummaryPromptEnabled)
        XCTAssertTrue(manager.weeklyReviewNotificationsEnabled)
        XCTAssertFalse(manager.focusScheduleEnabled)
        XCTAssertEqual(manager.focusScheduleStartMinute, 9 * 60)
        XCTAssertEqual(manager.focusScheduleEndMinute, 17 * 60)
        XCTAssertFalse(manager.focusScheduleLunchBreakEnabled)
        XCTAssertEqual(manager.focusScheduleLunchStartMinute, 12 * 60)
        XCTAssertEqual(manager.focusScheduleLunchEndMinute, 13 * 60)
        
        // Cloud classification defaults
        XCTAssertFalse(manager.enableCloudClassification)
        XCTAssertFalse(manager.enableImageClassification)
        XCTAssertEqual(manager.cloudProvider, 0)
        XCTAssertEqual(manager.cloudModel, "gemini-2.5-flash")
        XCTAssertEqual(manager.cloudEndpoint, "https://generativelanguage.googleapis.com/v1beta/models/")
        XCTAssertTrue(manager.enableDoomscrollLoopBreaker)
        XCTAssertEqual(manager.doomscrollThreshold, PreferencesManager.defaultDoomscrollThreshold)
        
        // Dim preferences defaults
        XCTAssertEqual(manager.dimOpacity, PreferencesManager.defaultDimOpacity)
        XCTAssertEqual(manager.dimTransitionDuration, PreferencesManager.defaultDimTransitionDuration)
    }

    func testSelectingOllamaUsesLocalDefaults() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.cloudProvider = 3

        XCTAssertEqual(manager.cloudModel, PreferencesManager.defaultCloudModelOllama)
        XCTAssertEqual(manager.cloudEndpoint, PreferencesManager.defaultCloudEndpointOllama)
        XCTAssertEqual(testDefaults.integer(forKey: PreferencesManager.Keys.cloudProvider), 3)
        XCTAssertEqual(testDefaults.string(forKey: PreferencesManager.Keys.cloudModel), PreferencesManager.defaultCloudModelOllama)
        XCTAssertEqual(testDefaults.string(forKey: PreferencesManager.Keys.cloudEndpoint), PreferencesManager.defaultCloudEndpointOllama)
    }
    
    func testInitializationWithStoredSettings() {
        // Given stored values in UserDefaults and enabled login item status
        testDefaults.set(15, forKey: PreferencesManager.Keys.countdownDuration)
        testDefaults.set(300.0, forKey: PreferencesManager.Keys.focusThreshold)
        testDefaults.set(2100.0, forKey: PreferencesManager.Keys.automaticSessionDuration)
        testDefaults.set(true, forKey: PreferencesManager.Keys.sessionSummaryPromptEnabled)
        testDefaults.set(false, forKey: PreferencesManager.Keys.weeklyReviewNotificationsEnabled)
        testDefaults.set(false, forKey: PreferencesManager.Keys.enableSmartNudges)
        testDefaults.set(false, forKey: PreferencesManager.Keys.showCountdownPill)
        testDefaults.set(false, forKey: PreferencesManager.Keys.focusPromptExperimentEnabled)
        testDefaults.set(true, forKey: PreferencesManager.Keys.enableCloudClassification)
        testDefaults.set(1, forKey: PreferencesManager.Keys.cloudProvider)
        testDefaults.set("gpt-4-custom", forKey: PreferencesManager.Keys.cloudModel)
        testDefaults.set("https://custom.openai.com/v1", forKey: PreferencesManager.Keys.cloudEndpoint)
        testDefaults.set("qwen2.5:1.5b", forKey: PreferencesManager.Keys.localTextModel)
        testDefaults.set(0.5, forKey: PreferencesManager.Keys.dimOpacity)
        testDefaults.set(10.0, forKey: PreferencesManager.Keys.dimTransitionDuration)
        mockService.status = .enabled
        
        // When initializing PreferencesManager
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // Then it should load the stored values and status
        XCTAssertEqual(manager.countdownDuration, 15)
        XCTAssertEqual(manager.focusThreshold, 300.0)
        XCTAssertEqual(manager.automaticSessionDuration, 2100.0)
        XCTAssertNil(manager.runtimeFocusThresholdOverride)
        XCTAssertEqual(manager.effectiveFocusThreshold, 300.0)
        XCTAssertTrue(manager.launchAtLogin)
        XCTAssertFalse(manager.enableSmartNudges)
        XCTAssertFalse(manager.showCountdownPill)
        XCTAssertFalse(manager.focusPromptExperimentEnabled)
        XCTAssertTrue(manager.sessionSummaryPromptEnabled)
        XCTAssertFalse(manager.weeklyReviewNotificationsEnabled)
        
        // Cloud classification loaded values
        XCTAssertTrue(manager.enableCloudClassification)
        XCTAssertEqual(manager.cloudProvider, 1)
        XCTAssertEqual(manager.cloudModel, "gpt-4-custom")
        XCTAssertEqual(manager.cloudEndpoint, "https://custom.openai.com/v1")
        XCTAssertEqual(manager.localTextModel, "qwen2.5:1.5b")
        
        // Dim preferences loaded values
        XCTAssertEqual(manager.dimOpacity, 0.5)
        XCTAssertEqual(manager.dimTransitionDuration, 10.0)
    }

    func testStoredRuntimeFocusThresholdOverrideIsIgnoredWithoutExplicitOptIn() {
        testDefaults.set(300.0, forKey: PreferencesManager.Keys.focusThreshold)
        testDefaults.set(5.0, forKey: PreferencesManager.Keys.focusThresholdOverride)

        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        XCTAssertNil(manager.runtimeFocusThresholdOverride)
        XCTAssertEqual(manager.effectiveFocusThreshold, 300.0)
    }

    func testFocusSchedulePreferencesPersist() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.focusScheduleEnabled = true
        manager.focusScheduleStartMinute = 8 * 60 + 30
        manager.focusScheduleEndMinute = 17 * 60 + 15
        manager.focusScheduleLunchBreakEnabled = true
        manager.focusScheduleLunchStartMinute = 12 * 60
        manager.focusScheduleLunchEndMinute = 13 * 60

        let reloaded = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        XCTAssertTrue(reloaded.focusScheduleEnabled)
        XCTAssertEqual(reloaded.focusScheduleStartMinute, 8 * 60 + 30)
        XCTAssertEqual(reloaded.focusScheduleEndMinute, 17 * 60 + 15)
        XCTAssertTrue(reloaded.focusScheduleLunchBreakEnabled)
        XCTAssertEqual(reloaded.focusScheduleLunchStartMinute, 12 * 60)
        XCTAssertEqual(reloaded.focusScheduleLunchEndMinute, 13 * 60)
    }

    func testClassificationPrivacyPreferencesPersist() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.classificationFeedbackEnabled = true
        manager.interactionSummaryEnabled = true

        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.classificationFeedbackEnabled))
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.interactionSummaryEnabled))
    }

    func testLocalTextClassificationPreferencePersists() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.enableLocalTextClassification = true

        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.enableLocalTextClassification))
    }

    func testEnablingLocalTextClassificationDisablesCloudClassification() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.enableCloudClassification = true
        manager.enableLocalTextClassification = true

        XCTAssertTrue(manager.enableLocalTextClassification)
        XCTAssertFalse(manager.enableCloudClassification)
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.enableLocalTextClassification))
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.enableCloudClassification))
    }

    func testEnablingCloudClassificationDisablesLocalTextClassification() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.enableLocalTextClassification = true
        manager.enableCloudClassification = true

        XCTAssertTrue(manager.enableCloudClassification)
        XCTAssertFalse(manager.enableLocalTextClassification)
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.enableCloudClassification))
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.enableLocalTextClassification))
    }

    func testConflictingStoredClassificationPreferencesPreferLocalTextClassification() {
        testDefaults.set(true, forKey: PreferencesManager.Keys.enableCloudClassification)
        testDefaults.set(true, forKey: PreferencesManager.Keys.enableLocalTextClassification)

        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        XCTAssertTrue(manager.enableLocalTextClassification)
        XCTAssertFalse(manager.enableCloudClassification)
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.enableLocalTextClassification))
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.enableCloudClassification))
    }

    func testLocalTextModelPreferencePersists() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.localTextModel = "qwen2.5:0.5b"

        XCTAssertEqual(testDefaults.string(forKey: PreferencesManager.Keys.localTextModel), "qwen2.5:0.5b")
    }

    func testCountdownPillPreferencePersists() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.showCountdownPill = false

        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.showCountdownPill))
        let reloaded = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        XCTAssertFalse(reloaded.showCountdownPill)
    }

    func testCommitmentLockForcesProtectedOffSwitchesBackOn() {
        testDefaults.set(false, forKey: PreferencesManager.Keys.launchAtLogin)
        testDefaults.set(false, forKey: PreferencesManager.Keys.showCountdownPill)
        testDefaults.set(false, forKey: PreferencesManager.Keys.enableDoomscrollLoopBreaker)
        testDefaults.set(true, forKey: PreferencesManager.Keys.commitmentLockEnabled)
        mockService.status = .notRegistered

        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        XCTAssertTrue(manager.commitmentLockEnabled)
        XCTAssertTrue(manager.launchAtLogin)
        XCTAssertFalse(manager.showCountdownPill)
        XCTAssertTrue(manager.enableDoomscrollLoopBreaker)
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.launchAtLogin))
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.showCountdownPill))
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.enableDoomscrollLoopBreaker))
    }

    func testCommitmentLockDoesNotForceCountdownPillBackOnAfterInitialization() {
        testDefaults.set(true, forKey: PreferencesManager.Keys.commitmentLockEnabled)
        testDefaults.set(false, forKey: PreferencesManager.Keys.showCountdownPill)

        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        XCTAssertTrue(manager.commitmentLockEnabled)
        XCTAssertFalse(manager.showCountdownPill)

        manager.showCountdownPill = false

        XCTAssertFalse(manager.showCountdownPill)
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.showCountdownPill))
    }

    func testCommitmentLockCanBeUnlockedAgain() {
        testDefaults.set(true, forKey: PreferencesManager.Keys.commitmentLockEnabled)
        mockService.status = .notRegistered

        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        XCTAssertTrue(manager.commitmentLockEnabled)

        manager.commitmentLockEnabled = false

        XCTAssertFalse(manager.commitmentLockEnabled)
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.commitmentLockEnabled))
    }

    func testRuntimeFocusThresholdOverrideWinsForEngineUse() {
        withRuntimeFocusThresholdOverrideEnabled {
            testDefaults.set(300.0, forKey: PreferencesManager.Keys.focusThreshold)
            testDefaults.set(5.0, forKey: PreferencesManager.Keys.focusThresholdOverride)

            let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

            XCTAssertEqual(manager.focusThreshold, 300.0)
            XCTAssertEqual(manager.runtimeFocusThresholdOverride, 5.0)
            XCTAssertEqual(manager.effectiveFocusThreshold, 5.0)
        }
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

    func testAutomaticSessionDurationPersistsIndependentlyFromFocusThreshold() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.focusThreshold = 900
        manager.automaticSessionDuration = 1500

        XCTAssertEqual(manager.focusThreshold, 900)
        XCTAssertEqual(manager.automaticSessionDuration, 1500)
        XCTAssertEqual(testDefaults.double(forKey: PreferencesManager.Keys.focusThreshold), 900)
        XCTAssertEqual(testDefaults.double(forKey: PreferencesManager.Keys.automaticSessionDuration), 1500)

        let reloaded = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        XCTAssertEqual(reloaded.focusThreshold, 900)
        XCTAssertEqual(reloaded.automaticSessionDuration, 1500)
    }

    func testSummaryAndWeeklyReviewPreferencesAreIndependent() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)

        manager.sessionSummaryPromptEnabled = true
        manager.weeklyReviewNotificationsEnabled = false

        XCTAssertTrue(manager.sessionSummaryPromptEnabled)
        XCTAssertFalse(manager.weeklyReviewNotificationsEnabled)
        XCTAssertTrue(testDefaults.bool(forKey: PreferencesManager.Keys.sessionSummaryPromptEnabled))
        XCTAssertFalse(testDefaults.bool(forKey: PreferencesManager.Keys.weeklyReviewNotificationsEnabled))
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

    private func withRuntimeFocusThresholdOverrideEnabled<T>(_ body: () throws -> T) rethrows -> T {
        let previousValue = getenv(runtimeFocusThresholdOverrideEnvironmentVariable).map { String(cString: $0) }

        setenv(runtimeFocusThresholdOverrideEnvironmentVariable, "1", 1)
        defer {
            if let previousValue {
                setenv(runtimeFocusThresholdOverrideEnvironmentVariable, previousValue, 1)
            } else {
                unsetenv(runtimeFocusThresholdOverrideEnvironmentVariable)
            }
        }

        return try body()
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
    
    func testDimPreferencesClamping() {
        let manager = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        // Test clamping of dimOpacity
        manager.dimOpacity = 0.05 // Under limit (min 0.1)
        XCTAssertEqual(manager.dimOpacity, 0.1)
        
        manager.dimOpacity = 0.99 // Over limit (max 0.95)
        XCTAssertEqual(manager.dimOpacity, 0.95)
        
        manager.dimOpacity = 0.5 // Valid
        XCTAssertEqual(manager.dimOpacity, 0.5)
        XCTAssertEqual(testDefaults.double(forKey: PreferencesManager.Keys.dimOpacity), 0.5)
        
        // Test clamping of dimTransitionDuration
        manager.dimTransitionDuration = -5.0 // Under limit (min 0.0)
        XCTAssertEqual(manager.dimTransitionDuration, 0.0)
        
        manager.dimTransitionDuration = 45.0 // Over limit (max 30.0)
        XCTAssertEqual(manager.dimTransitionDuration, 30.0)
        
        manager.dimTransitionDuration = 15.0 // Valid
        XCTAssertEqual(manager.dimTransitionDuration, 15.0)
        XCTAssertEqual(testDefaults.double(forKey: PreferencesManager.Keys.dimTransitionDuration), 15.0)
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
