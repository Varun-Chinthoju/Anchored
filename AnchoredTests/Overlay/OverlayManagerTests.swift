import XCTest
@testable import Anchored

final class OverlayManagerTests: XCTestCase {
    
    private var mockActivityMonitor: TestActivityMonitor!
    private var distractionListManager: DistractionListManager!
    private var sessionStore: SessionStore!
    private var focusEngine: FocusEngine!
    private var overlayManager: OverlayManager!
    private var tempStoreURL: URL!
    
    override func setUp() {
        super.setUp()
        
        let testDefaults = UserDefaults(suiteName: "com.varun.Anchored.overlaytests")!
        testDefaults.removePersistentDomain(forName: "com.varun.Anchored.overlaytests")
        distractionListManager = DistractionListManager(defaults: testDefaults)
        
        let tempDirectory = FileManager.default.temporaryDirectory
        tempStoreURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        sessionStore = SessionStore(fileURL: tempStoreURL)
        
        mockActivityMonitor = TestActivityMonitor()
        
        focusEngine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            focusThreshold: 600.0,
            preferencesManager: PreferencesManager(defaults: testDefaults)
        )
        
        overlayManager = OverlayManager(focusEngine: focusEngine)
        focusEngine.delegate = overlayManager
    }
    
    override func tearDown() {
        overlayManager.sessionDidEnd()
        focusEngine.stop()
        overlayManager = nil
        focusEngine = nil
        mockActivityMonitor = nil
        sessionStore = nil
        
        let dbURL = tempStoreURL.deletingPathExtension().appendingPathExtension("db")
        let walURL = tempStoreURL.deletingPathExtension().appendingPathExtension("db-wal")
        let shmURL = tempStoreURL.deletingPathExtension().appendingPathExtension("db-shm")
        
        try? FileManager.default.removeItem(at: tempStoreURL)
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)
        
        super.tearDown()
    }
    
    func testCountdownDurationClamping() {
        overlayManager.countdownDuration = 10
        XCTAssertEqual(overlayManager.countdownDuration, 10)
        
        overlayManager.countdownDuration = -5
        XCTAssertEqual(overlayManager.countdownDuration, 0, "Should clamp to minimum of 0 seconds")
        
        overlayManager.countdownDuration = 4000
        XCTAssertEqual(overlayManager.countdownDuration, 3600, "Should clamp to maximum of 3600 seconds")
    }
    
    func testDidRequestExitTriggerShowsPanel() {
        XCTAssertNil(overlayManager.exitTriggerPanel)
        
        overlayManager.didRequestExitTrigger(duration: 300, appName: "Xcode")
        
        XCTAssertNotNil(overlayManager.exitTriggerPanel)
    }
    
    func testOnlyOneExitTriggerPanelAtATime() {
        XCTAssertNil(overlayManager.exitTriggerPanel)
        
        overlayManager.didRequestExitTrigger(duration: 300, appName: "Xcode")
        let firstPanel = overlayManager.exitTriggerPanel
        XCTAssertNotNil(firstPanel)
        
        overlayManager.didRequestExitTrigger(duration: 600, appName: "Figma")
        let secondPanel = overlayManager.exitTriggerPanel
        XCTAssertNotNil(secondPanel)
        
        XCTAssertTrue(firstPanel !== secondPanel, "Should replace the existing panel instance")
    }
    
    func testDidDetectDistractionShowsCountdownPill() {
        XCTAssertNil(overlayManager.countdownPillPanel)
        
        overlayManager.didDetectDistraction(bundleID: "com.hnc.Discord")
        
        XCTAssertNotNil(overlayManager.countdownPillPanel)
    }
    
    func testOnlyOneCountdownPillPanelAtATime() {
        XCTAssertNil(overlayManager.countdownPillPanel)
        
        overlayManager.didDetectDistraction(bundleID: "com.hnc.Discord")
        let firstPill = overlayManager.countdownPillPanel
        XCTAssertNotNil(firstPill)
        
        overlayManager.didDetectDistraction(bundleID: "com.apple.MobileSMS")
        let secondPill = overlayManager.countdownPillPanel
        
        XCTAssertTrue(firstPill === secondPill, "Should not replace or create a new countdown pill if one is active")
    }
    
    func testDidReturnToWorkCancelsCountdownPill() {
        overlayManager.didDetectDistraction(bundleID: "com.hnc.Discord")
        XCTAssertNotNil(overlayManager.countdownPillPanel)
        
        overlayManager.didReturnToWork()
        
        XCTAssertNil(overlayManager.countdownPillPanel)
    }
    
    func testSessionDidEndHidesEverything() {
        overlayManager.didRequestExitTrigger(duration: 300, appName: "Xcode")
        overlayManager.didDetectDistraction(bundleID: "com.hnc.Discord")
        
        XCTAssertNotNil(overlayManager.exitTriggerPanel)
        XCTAssertNotNil(overlayManager.countdownPillPanel)
        
        overlayManager.sessionDidEnd()
        
        XCTAssertNil(overlayManager.exitTriggerPanel)
        XCTAssertNil(overlayManager.countdownPillPanel)
        XCTAssertTrue(overlayManager.dimWindows.isEmpty)
    }
    
    func testDimOverlayWindowCloseDoesNotCrash() {
        guard let screen = NSScreen.screens.first else { return }
        let window = DimOverlayWindow(screen: screen)
        window.close()
    }
}

// MARK: - TestActivityMonitor
private class TestActivityMonitor: ActivityMonitor {
    var onContextChange: ((ContextSnapshot) -> Void)?
    
    func start() {}
    func stop() {}
}
