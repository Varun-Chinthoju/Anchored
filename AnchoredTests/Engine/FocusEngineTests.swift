import XCTest
@testable import Anchored

final class FocusEngineTests: XCTestCase {
    
    private var mockActivityMonitor: MockActivityMonitor!
    private var distractionListManager: DistractionListManager!
    private var profileManager: ProfileManager!
    private var testPreferences: PreferencesManager!
    private var sessionStore: SessionStore!
    private var mockDelegate: MockFocusEngineDelegate!
    private var engine: FocusEngine!
    private var tempStoreURL: URL!
    
    override func setUp() {
        super.setUp()
        
        // Setup isolated UserDefaults
        let testDefaults = UserDefaults(suiteName: "com.varun.Anchored.tests")!
        testDefaults.removePersistentDomain(forName: "com.varun.Anchored.tests")
        distractionListManager = DistractionListManager(defaults: testDefaults)
        profileManager = ProfileManager(defaults: testDefaults)
        testPreferences = PreferencesManager(defaults: testDefaults)
        
        // Setup isolated SessionStore
        let tempDirectory = FileManager.default.temporaryDirectory
        tempStoreURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        sessionStore = SessionStore(fileURL: tempStoreURL)
        
        // Setup mock ActivityMonitor and Delegate
        mockActivityMonitor = MockActivityMonitor()
        mockDelegate = MockFocusEngineDelegate()
        // Initialize FocusEngine (default threshold = 10 minutes)
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences
        )
        engine.delegate = mockDelegate
        
        // Use a short distraction countdown for testing
        engine.distractionCountdownThreshold = 0.05
    }
    
    override func tearDown() {
        engine.stop()
        engine = nil
        sessionStore = nil
        let directoryURL = tempStoreURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func testInitialState() {
        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.currentApp)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertNil(engine.activeSession)
        XCTAssertFalse(engine.isDimming)
    }
    
    // MARK: - Non-Distraction Transitions
    
    func testNonDistractionAppSwitchSetsWorkSessionStart() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        
        XCTAssertEqual(engine.currentApp, "com.apple.dt.Xcode")
        XCTAssertEqual(engine.state, .watching)
        XCTAssertNotNil(engine.workSessionStart)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.apple.dt.Xcode")
    }
    
    func testSwitchingBetweenNonDistractionAppsDoesNotResetWorkSessionStart() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        let firstStart = engine.workSessionStart
        
        // Wait slightly to verify start date doesn't advance
        Thread.sleep(forTimeInterval: 0.01)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.Terminal")
        
        XCTAssertEqual(engine.currentApp, "com.apple.Terminal")
        XCTAssertEqual(engine.state, .watching)
        XCTAssertEqual(engine.workSessionStart, firstStart)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.apple.Terminal")
    }
    
    // MARK: - Distraction Transitions (No Session)
    
    func testDistractionAppSwitchResetsWorkSessionStartIfUnderThreshold() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertNotNil(engine.workSessionStart)
        
        // Switch to distraction (default distractions list includes Spotify)
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        XCTAssertNil(engine.workSessionStart)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(mockDelegate.exitTriggers.isEmpty)
    }
    
    func testDistractionAppSwitchTriggersExitCapsuleIfOverThreshold() {
        engine.focusThreshold = 0.1 // Use very short focus threshold for testing
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertNotNil(engine.workSessionStart)
        
        // Sleep to exceed threshold
        Thread.sleep(forTimeInterval: 0.15)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        XCTAssertNil(engine.workSessionStart)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(mockDelegate.exitTriggers.count, 1)
        XCTAssertEqual(mockDelegate.exitTriggers.first?.appName, "Xcode")
        XCTAssertGreaterThan(mockDelegate.exitTriggers.first?.duration ?? 0, 0.1)
    }

    func testFocusPromptUsesConfiguredThreshold() {
        engine.focusThreshold = 120
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.workSessionStart = Date().addingTimeInterval(-119)

        engine.focusPromptTimerExpired()

        XCTAssertTrue(mockDelegate.exitTriggers.isEmpty)

        engine.workSessionStart = Date().addingTimeInterval(-121)
        engine.focusPromptTimerExpired()

        XCTAssertEqual(mockDelegate.exitTriggers.count, 1)
        XCTAssertEqual(mockDelegate.exitTriggers.first?.appName, "Xcode")
    }

    func testBrowserEntertainmentDoesNotStartFocusTracking() {
        let profile = WorkProfile(
            name: "Browser",
            allowedApps: ["com.google.Chrome"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=123"),
            title: "Gaming highlights - YouTube"
        )

        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.workSessionStart)
    }

    func testBrowserWorkContextStartsFocusTracking() {
        let profile = WorkProfile(
            name: "Browser",
            allowedApps: ["com.google.Chrome"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://developer.apple.com/documentation/swift"),
            title: "Swift documentation"
        )

        XCTAssertEqual(engine.state, .watching)
        XCTAssertNotNil(engine.workSessionStart)
    }
    
    // MARK: - Capsule Actions
    
    func testAnchorSessionCreatesActiveSessionRetroactively() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        let start = engine.workSessionStart!
        
        engine.anchorSession(duration: 1500.0) // 25 minutes
        
        XCTAssertEqual(engine.state, .anchored)
        XCTAssertNotNil(engine.activeSession)
        XCTAssertEqual(engine.activeSession?.startDate, start)
        XCTAssertEqual(engine.activeSession?.anchoredDuration, 1500.0)
        XCTAssertEqual(engine.activeSession?.appName, "Xcode")
        
        // Verify database log
        let recent = sessionStore.recentSessions(limit: 5)
        // Wait, recent sessions filters by .sessionEnd. But let's check events directly if we can,
        // or let's read the JSON file to verify session start is logged.
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .sessionStart)
        XCTAssertEqual(events.first?.action, .anchored)
        XCTAssertEqual(events.first?.sessionDurationSeconds, 1500)
    }
    
    func testDismissTriggerResetsWorkSessionStart() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertNotNil(engine.workSessionStart)
        
        engine.dismissTrigger()
        
        XCTAssertNil(engine.workSessionStart)
        XCTAssertEqual(engine.state, .idle)
    }
    
    // MARK: - Distraction Transitions (With Active Session)
    
    func testDistractionAppSwitchDuringActiveSessionTriggersCountdownAndLog() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.spotify.client"])
        
        // Verify distraction detected event logged
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.count, 2) // sessionStart + distractionDetected
        XCTAssertEqual(events.last?.type, .distractionDetected)
        XCTAssertEqual(events.last?.distractionAppBundleID, "com.spotify.client")
    }
    
    func testReturnToWorkBeforeDistractionTimerExpiresCancelsTimer() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        // Switch back immediately (well before 0.05s)
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        
        // Wait to verify timer doesn't fire and transition to dimming
        Thread.sleep(forTimeInterval: 0.1)
        
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
        
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.count, 2) // sessionStart + distractionDetected (no escalationTriggered)
    }
    
    func testDistractionTimerExpirationTriggersEscalationAndLog() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        // Wait for distraction countdown timer (0.05s threshold) to fire
        let expectation = XCTestExpectation(description: "Wait for distraction countdown timer")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
        
        XCTAssertTrue(engine.isDimming)
        
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.count, 3) // sessionStart + distractionDetected + escalationTriggered
        XCTAssertEqual(events.last?.type, .escalationTriggered)
        XCTAssertEqual(events.last?.action, .escalated)
    }
    
    func testReturnToWorkAfterEscalationLiftsOverlay() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        // Manually fire distraction expiration to simulate countdown ending instantly
        engine.distractionTimerExpired(distractionBundleID: "com.spotify.client")
        
        XCTAssertTrue(engine.isDimming)
        
        // Switch back to work
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
    }
    
    // MARK: - Session Expiration & Termination
    
    func testSessionTimerExpirationAutoEndsSession() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        
        // Anchor for 0.05 seconds
        engine.anchorSession(duration: 0.05)
        XCTAssertEqual(engine.state, .anchored)
        
        // Wait for session timer to expire
        let expectation = XCTestExpectation(description: "Wait for session timer expiration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
        
        XCTAssertNil(engine.activeSession)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(mockDelegate.endedSessions, 1)
        
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.count, 2) // sessionStart + sessionEnd
        XCTAssertEqual(events.last?.type, .sessionEnd)
        XCTAssertEqual(events.last?.action, .timeout)
    }
    
    func testManualEndSessionTerminatesSessionWithDismissedAction() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        engine.endSession(action: .dismissed)
        
        XCTAssertNil(engine.activeSession)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(mockDelegate.endedSessions, 1)
        
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.count, 2) // sessionStart + sessionEnd
        XCTAssertEqual(events.last?.type, .sessionEnd)
        XCTAssertEqual(events.last?.action, .dismissed)
    }
    
    func testStartStopForwarding() {
        engine.start()
        XCTAssertTrue(mockActivityMonitor.isStarted)
        
        engine.stop()
        XCTAssertTrue(mockActivityMonitor.isStopped)
    }
    
    func testSelfAppExclusion() {
        // Start watching a work app
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertEqual(engine.currentApp, "com.apple.dt.Xcode")
        XCTAssertEqual(engine.state, .watching)
        
        // Switch to Anchored's own bundle ID
        mockActivityMonitor.simulateContextChange(bundleID: "com.varun.Anchored")
        
        // It should be completely ignored: currentApp, state, and lastWorkAppBundleID should remain unchanged
        XCTAssertEqual(engine.currentApp, "com.apple.dt.Xcode")
        XCTAssertEqual(engine.state, .watching)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.apple.dt.Xcode")
    }
    
    // MARK: - Mid-Session Profile Switching Tests
    
    func testProfileSwitchMidSessionToDistractionApp() {
        let profileA = WorkProfile(name: "ProfileA", distractionApps: [])
        let profileB = WorkProfile(name: "ProfileB", distractionApps: ["com.apple.Music"])
        profileManager.addProfile(profileA)
        profileManager.addProfile(profileB)
        
        profileManager.switchProfile(to: "ProfileA")
        
        // Start watching a work app and anchor
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        // Switch to com.apple.Music. In ProfileA, it is NOT a distraction.
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.Music")
        
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
        
        // Switch profile to ProfileB mid-session (where com.apple.Music IS a distraction)
        profileManager.switchProfile(to: "ProfileB")
        
        // It should immediately trigger distraction detected
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.apple.Music"])
    }
    
    func testProfileSwitchMidSessionToAllowedApp() {
        let profileA = WorkProfile(name: "ProfileA", distractionApps: ["com.apple.Music"])
        let profileB = WorkProfile(name: "ProfileB", distractionApps: [])
        profileManager.addProfile(profileA)
        profileManager.addProfile(profileB)
        
        profileManager.switchProfile(to: "ProfileA")
        
        // Start watching a work app and anchor
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        // Switch to com.apple.Music. In ProfileA, it IS a distraction.
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.Music")
        
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.apple.Music"])
        
        // Manually trigger distraction timer expiration to cause dimming
        engine.distractionTimerExpired(distractionBundleID: "com.apple.Music")
        XCTAssertTrue(engine.isDimming)
        
        // Switch profile to ProfileB mid-session (where com.apple.Music is allowed)
        profileManager.switchProfile(to: "ProfileB")
        
        // It should lift the dimming and trigger return to work
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
    }

    func testAllowedAppsOverrideDistractionAppsForAppLevelClassification() {
        let profile = WorkProfile(
            name: "AllowedAppProfile",
            distractionApps: ["com.spotify.client"],
            allowedApps: ["com.spotify.client"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")

        XCTAssertEqual(engine.state, .watching)
        XCTAssertNotNil(engine.workSessionStart)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.spotify.client")
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
    }

    func testAllowedAppsRestrictFocusToSelectedAppsWhenPresent() {
        let profile = WorkProfile(
            name: "AllowlistProfile",
            allowedApps: ["com.apple.dt.Xcode"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let localEngine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences
        )
        localEngine.delegate = mockDelegate
        localEngine.distractionCountdownThreshold = 0.05

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.Terminal")

        XCTAssertEqual(localEngine.state, .idle)
        XCTAssertNil(localEngine.workSessionStart)
        XCTAssertNil(localEngine.lastWorkAppBundleID)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
    }

    func testProfileAllowedAppsCanMarkAdditionalAppsAsFocus() {
        let profile = WorkProfile(
            name: "MixedProfile",
            allowedApps: ["com.apple.dt.Xcode", "com.apple.Terminal"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences
        )
        engine.delegate = mockDelegate
        engine.distractionCountdownThreshold = 0.05

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.Terminal")

        XCTAssertEqual(engine.state, .watching)
        XCTAssertNotNil(engine.workSessionStart)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.apple.Terminal")
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
    }
    
    func testIdleTimeDeductionFromSession() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        
        // Anchor for 25 minutes (1500 seconds)
        engine.anchorSession(duration: 1500.0)
        XCTAssertEqual(engine.state, .anchored)
        
        // Backdate the session start date to simulate 1000 seconds elapsed
        if let session = engine.activeSession {
            let backdatedSession = ActiveSession(
                startDate: Date().addingTimeInterval(-1000.0),
                anchoredDuration: session.anchoredDuration,
                appName: session.appName
            )
            engine.activeSession = backdatedSession
        }
        
        // Simulate 300 seconds of idle time
        engine.totalIdleTime = 300.0
        
        // Verify currentSessionFocusedTime
        let elapsed = engine.currentSessionFocusedTime()
        XCTAssertEqual(elapsed, 700.0, accuracy: 1.0)
        
        // End the session
        engine.endSession(action: .timeout)
        
        XCTAssertNil(engine.activeSession)
        
        // Verify logged event has the deducted duration (1000 - 300 = 700)
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.last?.type, .sessionEnd)
        XCTAssertEqual(events.last?.sessionDurationSeconds, 700)
    }
    
    func testURLDistractionDetection() {
        // Set up profile with distraction domain
        let profile = WorkProfile(
            name: "Test Profile",
            distractionApps: [],
            distractionDomains: ["youtube.com"],
            allowedDomains: ["github.com"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        // Switch to browser with distraction url
        let distractionURL = URL(string: "https://m.youtube.com/watch?v=hello")
        mockActivityMonitor.simulateContextChange(bundleID: "com.google.Chrome", url: distractionURL)
        
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.google.Chrome"])
        
        let events = loadEventsFromDisk()
        let distractionEvent = events.first(where: { $0.type == .distractionDetected })
        XCTAssertNotNil(distractionEvent)
        XCTAssertEqual(distractionEvent?.url, "https://m.youtube.com/watch")
        XCTAssertEqual(distractionEvent?.distraction_domain, "m.youtube.com")
    }
    
    func testURLAllowedLiftsDimming() {
        let profile = WorkProfile(
            name: "Test Profile",
            distractionApps: [],
            distractionDomains: ["youtube.com"],
            allowedDomains: ["github.com"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        // Enter distraction URL
        let distractionURL = URL(string: "https://www.youtube.com")
        mockActivityMonitor.simulateContextChange(bundleID: "com.google.Chrome", url: distractionURL)
        
        // Trigger dimming manually
        engine.distractionTimerExpired(distractionBundleID: "com.google.Chrome")
        XCTAssertTrue(engine.isDimming)
        
        // Switch to allowed URL
        let allowedURL = URL(string: "https://github.com/my/repo")
        mockActivityMonitor.simulateContextChange(bundleID: "com.google.Chrome", url: allowedURL)
        
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
    }

    func testDistractionDomainStillWinsInsideAllowedApp() {
        let profile = WorkProfile(
            name: "BrowserProfile",
            distractionApps: [],
            distractionDomains: ["youtube.com"],
            allowedApps: ["com.google.Chrome"],
            allowedDomains: ["github.com"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)

        let distractionURL = URL(string: "https://m.youtube.com/watch?v=hello")
        mockActivityMonitor.simulateContextChange(bundleID: "com.google.Chrome", url: distractionURL)

        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.google.Chrome"])

        let events = loadEventsFromDisk()
        let distractionEvent = events.first(where: { $0.type == .distractionDetected })
        XCTAssertNotNil(distractionEvent)
        XCTAssertEqual(distractionEvent?.url, "https://m.youtube.com/watch")
        XCTAssertEqual(distractionEvent?.distraction_domain, "m.youtube.com")
    }
    
    func testPermissionGateTriggered() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        
        // Log 9 sessions
        for _ in 1...9 {
            let sessionEvent = SessionEvent(
                type: .sessionEnd,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                sessionDurationSeconds: 1500,
                action: .timeout
            )
            sessionStore.log(sessionEvent)
        }
        
        // Flush queue by doing a sync read
        _ = sessionStore.allEvents()
        
        // Start and anchor session
        engine.anchorSession(duration: 1500.0)
        
        // End the 10th session
        engine.endSession()
        
        if !AXIsProcessTrusted() {
            XCTAssertEqual(mockDelegate.requestedPermissionGate, 1)
        } else {
            XCTAssertEqual(mockDelegate.requestedPermissionGate, 0)
        }
    }
    
    func testTitlePropagation() {
        let expectation = self.expectation(description: "FocusEngineContextDidChange notification fired")
        
        var receivedTitle: String?
        var receivedBundleID: String?
        
        let token = NotificationCenter.default.addObserver(
            forName: .focusEngineContextDidChange,
            object: engine,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo {
                receivedTitle = userInfo["title"] as? String
                receivedBundleID = userInfo["bundleID"] as? String
                expectation.fulfill()
            }
        }
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode", url: URL(string: "https://apple.com"), title: "Xcode Project")
        
        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(token)
        
        XCTAssertEqual(receivedBundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(receivedTitle, "Xcode Project")
        XCTAssertEqual(engine.currentTitle, "Xcode Project")
    }
    
    func testTitlePropagationWithVariousTitles() {
        let testCases: [(bundleID: String, url: URL?, title: String)] = [
            ("com.apple.dt.Xcode", URL(string: "file:///some/project"), ""),
            ("com.apple.Safari", URL(string: "https://github.com/Varun-Chinthoju/Anchored"), "GitHub - Varun-Chinthoju/Anchored: Focus app - Google Chrome"),
            ("com.google.Chrome", URL(string: "https://youtube.com/watch?v=123"), "YouTube - Funny Cat Videos"),
            ("com.apple.mail", nil, "Inbox (12) - varun@example.com - Mail ⚓"),
            ("com.apple.dt.Xcode", URL(string: "https://apple.com"), "Xcode Project")
        ]
        
        for (index, testCase) in testCases.enumerated() {
            let expectation = self.expectation(description: "FocusEngineContextDidChange notification fired for case \(index)")
            
            var receivedTitle: String?
            var receivedBundleID: String?
            var receivedURL: URL?
            
            let token = NotificationCenter.default.addObserver(
                forName: .focusEngineContextDidChange,
                object: engine,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo {
                    receivedTitle = userInfo["title"] as? String
                    receivedBundleID = userInfo["bundleID"] as? String
                    receivedURL = userInfo["url"] as? URL
                    expectation.fulfill()
                }
            }
            
            mockActivityMonitor.simulateContextChange(bundleID: testCase.bundleID, url: testCase.url, title: testCase.title)
            
            waitForExpectations(timeout: 1.0)
            NotificationCenter.default.removeObserver(token)
            
            XCTAssertEqual(receivedBundleID, testCase.bundleID)
            XCTAssertEqual(receivedTitle, testCase.title)
            if let expectedURL = testCase.url {
                XCTAssertEqual(receivedURL, expectedURL)
                XCTAssertEqual(engine.currentURL, expectedURL)
            } else {
                XCTAssertNil(receivedURL)
                XCTAssertNil(engine.currentURL)
            }
            XCTAssertEqual(engine.currentTitle, testCase.title)
            XCTAssertEqual(engine.currentApp, testCase.bundleID)
        }
    }
    
    func testContextPropagationAndMapping() {
        let expectation = self.expectation(description: "FocusEngineContextDidChange notification fired with AppContext")
        
        var receivedContext: AppContext?
        var receivedBundleID: String?
        var receivedTitle: String?
        var receivedIsFocus: Bool?
        
        let token = NotificationCenter.default.addObserver(
            forName: .focusEngineContextDidChange,
            object: engine,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo {
                receivedContext = userInfo["context"] as? AppContext
                receivedBundleID = userInfo["bundleID"] as? String
                receivedTitle = userInfo["title"] as? String
                receivedIsFocus = userInfo["isFocus"] as? Bool
                expectation.fulfill()
            }
        }
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.TestApp", url: URL(string: "https://example.com/page"), title: "Test Page")
        
        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(token)
        
        XCTAssertNotNil(receivedContext)
        XCTAssertEqual(receivedContext?.bundleIdentifier, "com.example.TestApp")
        XCTAssertEqual(receivedContext?.localizedName, "TestApp")
        XCTAssertEqual(receivedContext?.title, "Test Page")
        
        XCTAssertEqual(engine.currentContext, receivedContext)
        
        // Assert backward compatibility
        XCTAssertEqual(receivedBundleID, "com.example.TestApp")
        XCTAssertEqual(receivedTitle, "Test Page")
        XCTAssertNotNil(receivedIsFocus)
    }
    
    func testSmartWebClassifierPreventsDimmingForCodingForum() {
        let profile = WorkProfile(
            name: "Coding Forum Profile",
            distractionApps: [],
            distractionDomains: ["reddit.com", "youtube.com"],
            allowedDomains: []
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        // Enter a coding forum on reddit.com
        let forumURL = URL(string: "https://www.reddit.com/r/swift/comments/123")
        mockActivityMonitor.simulateContextChange(bundleID: "com.google.Chrome", url: forumURL, title: "Swift Programming Forum Thread")
        
        // The delegate should NOT receive distraction detection call because of the AI override!
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        
        // Enter a coding tutorial on youtube.com
        let tutorialURL = URL(string: "https://www.youtube.com/watch?v=swift-tutorial")
        mockActivityMonitor.simulateContextChange(bundleID: "com.google.Chrome", url: tutorialURL, title: "Build an App in Swift - YouTube")
        
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
    }
    
    func testSmartAppClassifierAllowsUnregisteredApp() {
        // Assert that Terminal is dynamically resolved as a productive/focus app even if it isn't in allowlist
        XCTAssertTrue(SmartAppClassifier.isProductiveApp(bundleID: "com.apple.Terminal"))
    }
    
    func testPauseAndResumeSessionTimeShifting() {
        let profile = WorkProfile(
            name: "TimeShiftProfile",
            distractionApps: ["com.spotify.client"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        engine.start()
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        let initialStartDate = engine.activeSession?.startDate ?? Date()
        
        // Enter distraction -> starts distraction countdown
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        // Trigger distraction countdown expiration -> dims screen and pauses session
        engine.distractionTimerExpired(distractionBundleID: "com.spotify.client")
        
        XCTAssertTrue(engine.isDimming)
        XCTAssertNotNil(engine.pausedDate)
        
        // Wait a small duration (e.g. 0.05 seconds) to simulate distraction time elapsed
        let expectation = XCTestExpectation(description: "Wait for distraction pause duration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Return to work -> resumes session and shifts activeSession.startDate forward
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        
        XCTAssertFalse(engine.isDimming)
        XCTAssertNil(engine.pausedDate)
        
        let resumedStartDate = engine.activeSession?.startDate ?? Date()
        XCTAssertGreaterThan(resumedStartDate.timeIntervalSince(initialStartDate), 0.04)
    }
    
    // MARK: - Cloud Classification Integration Tests
    
    func testCloudClassificationIsDistractionProductive() {
        testPreferences.enableCloudClassification = true
        testPreferences.cloudProvider = 0 // Gemini
        try? KeychainHelper.saveKey("fake-gemini-key", forProvider: "gemini")
        
        MockURLProtocol.requestHandler = { request in
            let expectedJSON = """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {
                        "text": "yes"
                      }
                    ]
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedJSON.data(using: .utf8))
        }
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client", title: "Test Title")
        
        // Productive is true, so it is NOT a distraction. Therefore, it is a WATCHING focus state, not distraction.
        XCTAssertEqual(engine.state, .watching)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.spotify.client")
    }
    
    func testCloudClassificationIsDistractionUnproductive() {
        testPreferences.enableCloudClassification = true
        testPreferences.cloudProvider = 0 // Gemini
        try? KeychainHelper.saveKey("fake-gemini-key", forProvider: "gemini")
        
        MockURLProtocol.requestHandler = { request in
            let expectedJSON = """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {
                        "text": "no"
                      }
                    ]
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedJSON.data(using: .utf8))
        }
        
        // Set up active session to detect distraction countdown pill
        engine.workSessionStart = Date()
        engine.anchorSession(duration: 1500)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client", title: "Test Title")
        
        // Productive is false, so it IS a distraction.
        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
        XCTAssertEqual(mockDelegate.detectedDistractions.first, "com.spotify.client")
    }
    
    func testCloudClassificationIsDistractionFallbackOnFailure() {
        testPreferences.enableCloudClassification = true
        testPreferences.cloudProvider = 0 // Gemini
        try? KeychainHelper.saveKey("fake-gemini-key", forProvider: "gemini")
        
        // Return 500 error to simulate network/cloud failure
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client", title: "Test Title")
        
        // Should fall back to local check (distraction), resetting workSessionStart to nil
        XCTAssertNil(engine.workSessionStart)
    }
    
    // MARK: - Helper Methods
    
    private func loadEventsFromDisk() -> [SessionEvent] {
        // Flush queue by doing a sync read:
        _ = sessionStore.recentSessions(limit: 1)
        return sessionStore.allEvents()
    }
}

// MARK: - Mock Classes

class MockActivityMonitor: ActivityMonitor {
    var onContextChange: ((ContextSnapshot) -> Void)?
    var isStarted = false
    var isStopped = false
    
    func start() {
        isStarted = true
    }
    
    func stop() {
        isStopped = true
    }
    
    func simulateContextChange(bundleID: String, url: URL? = nil, title: String = "") {
        let snapshot = ContextSnapshot(
            bundleIdentifier: bundleID,
            localizedName: bundleID,
            url: url,
            title: title,
            source: .application,
            observedAt: Date()
        )
        onContextChange?(snapshot)
    }
}

class MockFocusEngineDelegate: FocusEngineDelegate {
    var exitTriggers: [(duration: TimeInterval, appName: String)] = []
    var detectedDistractions: [String] = []
    var returnsToWork = 0
    var endedSessions = 0
    
    func didRequestExitTrigger(duration: TimeInterval, appName: String) {
        exitTriggers.append((duration: duration, appName: appName))
    }
    
    func didDetectDistraction(bundleID: String) {
        detectedDistractions.append(bundleID)
    }
    
    func didReturnToWork() {
        returnsToWork += 1
    }
    
    func sessionDidEnd() {
        endedSessions += 1
    }
    
    var requestedPermissionGate = 0
    func didRequestPermissionGate() {
        requestedPermissionGate += 1
    }
}
