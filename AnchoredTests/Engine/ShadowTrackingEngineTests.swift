import XCTest
import AppKit
import Darwin
@testable import Anchored

class ShadowTrackingEngineTests: XCTestCase {
    private let runtimeFocusThresholdOverrideEnvironmentVariable = "ANCHORED_ENABLE_RUNTIME_FOCUS_THRESHOLD_OVERRIDE"
    var engine: FocusEngine!
    var mockMonitor: MockActivityMonitor!
    var distractionListManager: DistractionListManager!
    var preferencesManager: PreferencesManager!
    var profileManager: ProfileManager!
    var shadowEngine: ShadowTrackingEngine!
    var mockUserActivityProvider: MockUserActivityProvider!
    private var previousUserActivityProvider: UserActivityProviding!
    private var testDefaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        let suiteName = "com.varun.Anchored.ShadowTrackingEngineTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        
        mockMonitor = MockActivityMonitor()
        distractionListManager = DistractionListManager(defaults: testDefaults!)
        preferencesManager = PreferencesManager(defaults: testDefaults)
        profileManager = ProfileManager(defaults: testDefaults)
        previousUserActivityProvider = UserActivityEnvironment.shared
        mockUserActivityProvider = MockUserActivityProvider()
        UserActivityEnvironment.shared = mockUserActivityProvider
        let profile = WorkProfile(
            name: "Test Focus",
            distractionApps: ["com.spotify.client"],
            allowedApps: ["com.apple.dt.Xcode"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let testDBURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_shadow_\(UUID().uuidString).json")
        engine = FocusEngine(
            activityMonitor: mockMonitor,
            distractionListManager: distractionListManager,
            sessionStore: SessionStore(fileURL: testDBURL),
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: preferencesManager,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker()
        )
        
        shadowEngine = ShadowTrackingEngine(focusEngine: engine, preferencesManager: preferencesManager)
        // Set short threshold for testing
        shadowEngine.nudgeThreshold = 3.0
    }
    
    override func tearDown() {
        shadowEngine = nil
        engine.stop()
        engine = nil
        UserActivityEnvironment.shared = previousUserActivityProvider
        mockUserActivityProvider = nil
        previousUserActivityProvider = nil
        mockMonitor = nil
        distractionListManager = nil
        preferencesManager = nil
        profileManager = nil
        testDefaults = nil

        super.tearDown()
    }
    
    func testShadowTrackingAccumulatesTime() {
        // Given we are in focus context
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        
        // Wait a bit
        let expectation = XCTestExpectation(description: "accumulate time")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            XCTAssertGreaterThan(self.shadowEngine.getContinuousWorkTime(), 0.0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
    }
    
    func testShadowTrackingAccumulatesTimeWithTitleContext() {
        // Given we are in focus context with a title
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode", title: "Xcode Project Window")
        shadowEngine.forceUpdateTrackingState()
        
        // Wait a bit
        let expectation = XCTestExpectation(description: "accumulate time with title context")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            XCTAssertGreaterThan(self.shadowEngine.getContinuousWorkTime(), 0.0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
    }

    func testHeuristicProductiveContextDoesNotTriggerAutoAnchorWithoutExplicitRule() {
        mockMonitor.simulateContextChange(bundleID: "com.example.Cursor")
        shadowEngine.forceUpdateTrackingState()

        let expectation = XCTestExpectation(description: "heuristic productive context stays below auto-start gate")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            XCTAssertEqual(self.shadowEngine.getContinuousWorkTime(), 0.0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
    }

    func testShadowTrackingResetsOnDistraction() {
        // Start tracking
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        
        shadowEngine.setContinuousWorkTime(2.0)
        XCTAssertEqual(shadowEngine.getContinuousWorkTime(), 2.0)
        
        // Switch to distraction
        mockMonitor.simulateContextChange(bundleID: "com.spotify.client")
        shadowEngine.forceUpdateTrackingState()
        
        XCTAssertEqual(shadowEngine.getContinuousWorkTime(), 0.0)
    }

    func testShadowTrackingResetsWhenSessionEnds() {
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        shadowEngine.setContinuousWorkTime(2.0)

        engine.anchorSession(duration: 600.0)
        engine.endSession(action: .dismissed)

        XCTAssertEqual(shadowEngine.getContinuousWorkTime(), 0.0)

        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()

        let expectation = XCTestExpectation(description: "shadow tracking restarts fresh after session end")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            XCTAssertGreaterThan(self.shadowEngine.getContinuousWorkTime(), 0.0)
            XCTAssertLessThan(self.shadowEngine.getContinuousWorkTime(), 1.5)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
    }
    
    func testShadowTrackingPausesOnNeutral() {
        // Start tracking
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        
        shadowEngine.setContinuousWorkTime(2.0)
        XCTAssertEqual(shadowEngine.getContinuousWorkTime(), 2.0)
        
        // Switch to neutral context
        mockMonitor.simulateContextChange(bundleID: "com.apple.Finder")
        shadowEngine.forceUpdateTrackingState()
        
        // Continuous work time should be paused but preserved (not reset to 0)
        XCTAssertEqual(shadowEngine.getContinuousWorkTime(), 2.0)
        
        // Switch back to focus context
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        
        // Continuous work time should still be 2.0 and active
        XCTAssertEqual(shadowEngine.getContinuousWorkTime(), 2.0)
    }

    func testShadowTrackingDoesNotAccumulateWhenUserIsIdle() {
        mockUserActivityProvider.idleDuration = 20.0

        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()

        let expectation = XCTestExpectation(description: "idle user does not keep shadow tracking running")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            XCTAssertEqual(self.shadowEngine.getContinuousWorkTime(), 0.0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
    }
    
    func testShadowTrackingPausesOnSleep() {
        shadowEngine.nudgeThreshold = 10.0
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        
        shadowEngine.setContinuousWorkTime(2.0)
        
        // Post sleep notification
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        
        // Wait and verify time didn't increase
        let expectation = XCTestExpectation(description: "paused during sleep")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            XCTAssertEqual(self.shadowEngine.getContinuousWorkTime(), 2.0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
        
        // Wake up
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        
        // Wait and verify it resumes
        let resumeExpectation = XCTestExpectation(description: "resumes after wake")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            XCTAssertGreaterThan(self.shadowEngine.getContinuousWorkTime(), 2.0)
            resumeExpectation.fulfill()
        }
        wait(for: [resumeExpectation], timeout: 3.5)
    }

    func testShadowTrackingDoesNotAccumulateOutsideSchedule() {
        preferencesManager.focusSchedule = scheduleExcludingCurrentMinute(now: Date())

        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        shadowEngine.setContinuousWorkTime(2.0)

        let expectation = XCTestExpectation(description: "schedule-off tracking stays paused")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            XCTAssertEqual(self.shadowEngine.getContinuousWorkTime(), 2.0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
    }
    
    func testSmartNudgeFiresOnThreshold() {
        preferencesManager.enableSmartNudges = false
        mockMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        shadowEngine.forceUpdateTrackingState()
        
        var callbackFired = false
        let expectation = XCTestExpectation(description: "threshold crossed")
        shadowEngine.onThresholdCrossed = {
            callbackFired = true
            expectation.fulfill()
        }
        
        // Force work time to 2.0 (nudgeThreshold is 3.0)
        shadowEngine.setContinuousWorkTime(2.0)
        
        wait(for: [expectation], timeout: 3.5)
        XCTAssertTrue(callbackFired)
        XCTAssertGreaterThanOrEqual(shadowEngine.getContinuousWorkTime(), 0.0)
        // Verify it reset after nudge
        XCTAssertEqual(shadowEngine.getContinuousWorkTime(), 0.0)
    }

    func testRuntimeThresholdOverrideDoesNotChangeAutomaticSessionDurationPreference() {
        withRuntimeFocusThresholdOverrideEnabled {
            testDefaults.set(5.0, forKey: PreferencesManager.Keys.focusThresholdOverride)
            let overriddenPreferences = PreferencesManager(defaults: testDefaults)

            XCTAssertEqual(overriddenPreferences.effectiveFocusThreshold, 5.0)
            XCTAssertEqual(overriddenPreferences.automaticSessionDuration, PreferencesManager.defaultAutomaticSessionDuration)
        }
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

    private func scheduleExcludingCurrentMinute(now: Date) -> FocusSchedule {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start: Int
        let end: Int
        if minute <= 1320 {
            start = minute + 60
            end = min(23 * 60 + 59, start + 30)
        } else {
            end = max(1, minute - 60)
            start = max(0, end - 30)
        }

        return FocusSchedule(
            enabled: true,
            startMinute: start,
            endMinute: max(start + 1, end),
            lunchBreakEnabled: false
        )
    }
}
