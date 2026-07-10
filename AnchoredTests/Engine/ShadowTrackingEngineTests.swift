import XCTest
import AppKit
@testable import Anchored

class ShadowTrackingEngineTests: XCTestCase {
    var engine: FocusEngine!
    var mockMonitor: MockActivityMonitor!
    var distractionListManager: DistractionListManager!
    var preferencesManager: PreferencesManager!
    var profileManager: ProfileManager!
    var shadowEngine: ShadowTrackingEngine!
    private var originalDistractions: [String] = []
    
    override func setUp() {
        super.setUp()
        let suiteName = "com.varun.Anchored.ShadowTrackingEngineTests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)
        
        mockMonitor = MockActivityMonitor()
        distractionListManager = DistractionListManager(defaults: testDefaults!)
        preferencesManager = PreferencesManager(defaults: testDefaults!)
        profileManager = ProfileManager(defaults: testDefaults!)
        let profile = WorkProfile(name: "Test Focus", allowedApps: ["com.apple.dt.Xcode"])
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        
        originalDistractions = DistractionListManager.shared.allDistractions
        DistractionListManager.shared.add("com.spotify.client")
        DistractionListManager.shared.remove("com.apple.dt.Xcode")
        
        let testDBURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_shadow_\(UUID().uuidString).json")
        engine = FocusEngine(
            activityMonitor: mockMonitor,
            distractionListManager: distractionListManager,
            sessionStore: SessionStore(fileURL: testDBURL),
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: preferencesManager
        )
        
        shadowEngine = ShadowTrackingEngine(focusEngine: engine, preferencesManager: preferencesManager)
        // Set short threshold for testing
        shadowEngine.nudgeThreshold = 3.0
    }
    
    override func tearDown() {
        shadowEngine = nil
        engine.stop()
        engine = nil
        mockMonitor = nil
        distractionListManager = nil
        preferencesManager = nil
        profileManager = nil
        
        // Restore DistractionListManager.shared
        let currentDistractions = DistractionListManager.shared.allDistractions
        for app in currentDistractions {
            DistractionListManager.shared.remove(app)
        }
        for app in originalDistractions {
            DistractionListManager.shared.add(app)
        }
        
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
    
    func testShadowTrackingResetsOnDistractionOrNeutral() {
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
}
