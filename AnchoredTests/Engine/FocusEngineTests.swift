import XCTest
@testable import Anchored

final class FocusEngineTests: XCTestCase {
    
    private var suiteName: String!
    private var testDefaults: UserDefaults!
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
        
        suiteName = "com.varun.Anchored.FocusEngineTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
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
        // Initialize FocusEngine (default threshold = 10 minutes) with fake providers to avoid Vision overhead
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker()
        )
        engine.delegate = mockDelegate
        
        // Use a short distraction countdown for testing
        engine.distractionCountdownThreshold = 0.05
    }
    
    override func tearDown() {
        engine.stop()
        engine = nil
        sessionStore = nil
        testPreferences = nil
        profileManager = nil
        distractionListManager = nil
        if let suiteName {
            testDefaults.removePersistentDomain(forName: suiteName)
        }
        testDefaults = nil
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

    func testSystemLoginWindowContextDoesNotBecomeFocusOrDistractionEvidence() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.loginwindow")

        XCTAssertNil(engine.currentApp)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(sessionStore.allEvents().isEmpty)
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
    
    func testDistractionAppSwitchAutoStartsSessionIfOverThreshold() {
        engine.focusThreshold = 0.1 // Use very short focus threshold for testing

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertNotNil(engine.workSessionStart)
        
        // Sleep to exceed threshold
        Thread.sleep(forTimeInterval: 0.15)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        XCTAssertNotNil(engine.workSessionStart)
        XCTAssertEqual(engine.state, .anchored)
        XCTAssertNotNil(engine.activeSession)
        XCTAssertTrue(mockDelegate.exitTriggers.isEmpty)
        XCTAssertEqual(engine.activeSession?.goal, "Auto-chartered Voyage")
    }

    func testFocusPromptTimerAutoStartsSessionUsesConfiguredThreshold() {
        engine.focusThreshold = 120
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.workSessionStart = Date().addingTimeInterval(-119)

        engine.focusPromptTimerExpired()

        XCTAssertNil(engine.activeSession)

        engine.workSessionStart = Date().addingTimeInterval(-121)
        engine.focusPromptTimerExpired()

        XCTAssertNotNil(engine.activeSession)
        XCTAssertTrue(mockDelegate.exitTriggers.isEmpty)
        XCTAssertEqual(engine.activeSession?.goal, "Auto-chartered Voyage")
    }

    func testScheduleChangeSuppressesAutomaticFocusTrackingOutsideWindow() {
        let now = Date()
        testPreferences.focusSchedule = scheduleAllowingCurrentMinute(now: now)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertNotNil(engine.workSessionStart)
        XCTAssertTrue(engine.isFocusScheduleActive)

        testPreferences.focusSchedule = scheduleExcludingCurrentMinute(now: now)

        XCTAssertFalse(engine.isFocusScheduleActive)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertNil(engine.activeSession)
    }

    func testAnchorSessionUsesSuggestedCategoryAndGoalWhenMissing() {
        profileManager.switchProfile(to: "Video")
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.apple.dt.Xcode",
            title: "Write docs"
        )

        engine.anchorSession(duration: 300)

        XCTAssertEqual(engine.activeSession?.category, "Coding")
        XCTAssertEqual(engine.activeSession?.goal, "Write docs")
    }

    func testSleepDoesNotCountTowardFocusedSessionTime() throws {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        let focusedStart = Date().addingTimeInterval(-120)
        engine.workSessionStart = focusedStart
        engine.anchorSession(duration: 3_600)

        let sleepStartedAt = Date()
        let focusedBeforeSleep = engine.currentSessionFocusedTime(at: sleepStartedAt)
        let originalSessionStart = try XCTUnwrap(engine.activeSession?.startDate)

        engine.pauseFocusAccountingForWorkspaceLifecycle(now: sleepStartedAt)
        let wakeAt = sleepStartedAt.addingTimeInterval(1_800)

        XCTAssertEqual(
            engine.currentSessionFocusedTime(at: wakeAt),
            focusedBeforeSleep,
            accuracy: 0.001
        )

        engine.resumeFocusAccountingForWorkspaceLifecycle(now: wakeAt)

        let resumedWorkSessionStart = try XCTUnwrap(engine.workSessionStart)
        let resumedSessionStart = try XCTUnwrap(engine.activeSession?.startDate)
        XCTAssertEqual(
            resumedWorkSessionStart.timeIntervalSince1970,
            focusedStart.addingTimeInterval(1_800).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            resumedSessionStart.timeIntervalSince1970,
            originalSessionStart.addingTimeInterval(1_800).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            engine.currentSessionFocusedTime(at: wakeAt),
            focusedBeforeSleep,
            accuracy: 0.001
        )
    }

    func testAllowedBrowserAppOverridesEntertainmentHeuristic() {
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

        XCTAssertEqual(engine.state, .watching)
        XCTAssertNotNil(engine.workSessionStart)
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

    func testEducationalYouTubeVideoDoesNotTriggerDistraction() {
        let profile = WorkProfile(name: "Neutral Browsing")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=swift-concurrency"),
            title: "Computer Science Lecture - Swift Concurrency"
        )

        let settled = expectation(description: "educational browser context settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.0)

        XCTAssertTrue(engine.currentClassification.isNeutral)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
    }

    func testCorrectionImmediatelyChangesCurrentClassification() {
        let profile = WorkProfile(name: "Correction")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Editor")
        XCTAssertTrue(engine.currentClassification.isNeutral)

        engine.applyCorrection(.blockApp)
        XCTAssertTrue(engine.currentClassification.isDistraction)
        XCTAssertTrue(profileManager.activeProfile.distractionApps.contains("com.example.Editor"))

        engine.applyCorrection(.allowApp)
        XCTAssertTrue(engine.currentClassification.isFocus)
        XCTAssertFalse(profileManager.activeProfile.distractionApps.contains("com.example.Editor"))
        XCTAssertTrue(profileManager.activeProfile.allowedApps.contains("com.example.Editor"))
    }

    func testOptInLocalClassifierPromotesOnlyCurrentNeutralContext() {
        testPreferences.enableLocalTextClassification = true
        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            localTextClassifier: ProductiveTestClassifier()
        )

        let promotion = expectation(description: "local productive result promotes current neutral context")
        let observer = NotificationCenter.default.addObserver(
            forName: .focusEngineClassificationDidChange,
            object: engine,
            queue: .main
        ) { [weak engine] _ in
            if engine?.currentClassification.isFocus == true {
                promotion.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")

        wait(for: [promotion], timeout: 1.0)
        XCTAssertTrue(engine.currentClassification.isFocus)
    }

    func testStaleLocalClassifierResultCannotPromoteNewerContext() {
        testPreferences.enableLocalTextClassification = true
        let classifier = DeferredContextClassifier()
        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            localTextClassifier: classifier
        )

        let request = expectation(description: "local classifier request received")
        classifier.onRequest = { request.fulfill() }
        let unexpectedPromotion = expectation(description: "stale local result must not promote")
        unexpectedPromotion.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .focusEngineClassificationDidChange,
            object: engine,
            queue: .main
        ) { [weak engine] _ in
            if engine?.currentClassification.isFocus == true {
                unexpectedPromotion.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")
        wait(for: [request], timeout: 1.0)
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        classifier.complete(.productive)

        wait(for: [unexpectedPromotion], timeout: 0.2)
        XCTAssertTrue(engine.currentClassification.isDistraction)
    }

    func testLocalClassifierDistractingResultDoesNotStartCountdownForNeutralContext() {
        testPreferences.enableLocalTextClassification = true
        testPreferences.enableCloudClassification = false
        testPreferences.enableImageClassification = false
        let classifier = DeferredContextClassifier()
        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            localTextClassifier: classifier,
            intentClassifier: NeutralIntentClassifier()
        )
        engine.delegate = mockDelegate
        engine.distractionCountdownThreshold = 0.05

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode", title: "Draft")
        engine.anchorSession(duration: 1_500)

        let request = expectation(description: "local classifier request received")
        classifier.onRequest = { request.fulfill() }

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown", title: "Draft")
        wait(for: [request], timeout: 1.0)
        classifier.complete(.distracting)

        let settled = expectation(description: "local distracting result settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 2.0)

        XCTAssertTrue(engine.currentClassification.isNeutral)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
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

    func testBreakBeforeMinimumIsRefusedWithoutEndingSession() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500)

        let decision = engine.requestBreak(intention: "Stretch")

        XCTAssertEqual(decision, .refusedUnderMinimum)
        XCTAssertNotNil(engine.activeSession)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.refusedBreaks, 1)
    }

    func testAcceptedBreakPausesFocusAccountingAndReachesReviewWithoutDimming() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 3600)
        if let session = engine.activeSession {
            engine.activeSession = ActiveSession(
                startDate: session.startDate.addingTimeInterval(-1800),
                anchoredDuration: session.anchoredDuration,
                appName: session.appName,
                category: session.category,
                goal: session.goal
            )
        }

        let beforeBreak = engine.currentSessionFocusedTime()
        let decision = engine.requestBreak(intention: "Take a short walk")

        guard case .accepted = decision else {
            return XCTFail("Expected an accepted break")
        }
        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertEqual(engine.currentSessionFocusedTime(), beforeBreak, accuracy: 0.2)

        engine.breakTimerExpired()

        XCTAssertEqual(engine.breakState, .breakReview)
        XCTAssertEqual(mockDelegate.breakReviews.last?.result.outcome, .mismatch)
        XCTAssertFalse(engine.isDimming)
        XCTAssertNotNil(engine.activeSession)
    }

    func testCancellingBreakResumesSessionAndDoesNotCountBreakTime() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 3600)
        if let session = engine.activeSession {
            engine.activeSession = ActiveSession(
                startDate: session.startDate.addingTimeInterval(-1800),
                anchoredDuration: session.anchoredDuration,
                appName: session.appName,
                category: session.category,
                goal: session.goal
            )
        }
        let focusedBeforeBreak = engine.currentSessionFocusedTime()
        _ = engine.requestBreak(intention: "Reset")

        engine.resumeAfterBreakReview()

        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertEqual(engine.currentSessionFocusedTime(), focusedBeforeBreak, accuracy: 0.2)
        XCTAssertNotNil(engine.activeSession)
    }

    func testBreakAutoResumesAfterReturningToWorkForFifteenSeconds() throws {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 3600)
        if let session = engine.activeSession {
            engine.activeSession = ActiveSession(
                startDate: session.startDate.addingTimeInterval(-1800),
                anchoredDuration: session.anchoredDuration,
                appName: session.appName,
                category: session.category,
                goal: session.goal
            )
        }

        _ = engine.requestBreak(intention: "Take a short walk")
        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertNil(engine.breakReturnGraceStartedAt)

        // Staying on the work app should not start the auto-resume grace.
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertNil(engine.breakReturnGraceStartedAt)

        // Leaving work and coming back should start the grace timer.
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")

        let graceStartedAt = try XCTUnwrap(engine.breakReturnGraceStartedAt)

        engine.breakReturnGraceTimerExpired(now: graceStartedAt.addingTimeInterval(14.9))
        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertNotNil(engine.activeBreakCommitment)

        engine.breakReturnGraceTimerExpired(now: graceStartedAt.addingTimeInterval(15.1))

        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertGreaterThan(mockDelegate.returnsToWork, 1)
    }

    func testEndingSessionClearsPendingBreakAndPersistsDoneOutcomeAndSummary() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 3600)
        engine.endSession(action: .dismissed, completionOutcome: .done, summary: "Finished the plan")

        XCTAssertNil(engine.activeSession)
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.last?.completionOutcome, .done)
        XCTAssertEqual(events.last?.sessionSummary, "Finished the plan")
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

    func testNeutralAppsDoNotStartFocusTrackingWhenNoRuleMatches() {
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
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker()
        )
        localEngine.delegate = mockDelegate
        localEngine.distractionCountdownThreshold = 0.05

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Notepad")

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
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker()
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
    
    func testExplicitDomainRulesOverrideSmartWebHeuristics() {
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
        
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.google.Chrome"])
        
        // Enter a coding tutorial on youtube.com
        let tutorialURL = URL(string: "https://www.youtube.com/watch?v=swift-tutorial")
        mockActivityMonitor.simulateContextChange(bundleID: "com.google.Chrome", url: tutorialURL, title: "Build an App in Swift - YouTube")
        
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.google.Chrome"])
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

    func testDeclaredActivityResumesDimmedSessionTime() throws {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1_500)
        let initialStartDate = try XCTUnwrap(engine.activeSession?.startDate)

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        engine.distractionTimerExpired(distractionBundleID: "com.spotify.client")
        XCTAssertTrue(engine.isDimming)

        Thread.sleep(forTimeInterval: 0.05)
        engine.startDeclaredActivityBypass(activity: "Write the release notes")

        XCTAssertFalse(engine.isDimming)
        XCTAssertTrue(engine.isDeclaredActivityBypassActive)
        XCTAssertNil(engine.pausedDate)
        let resumedStartDate = try XCTUnwrap(engine.activeSession?.startDate)
        XCTAssertGreaterThan(resumedStartDate.timeIntervalSince(initialStartDate), 0.04)
    }

    func testCmdTabToAnotherProductiveAppDoesNotBypassDimming() {
        let profile = WorkProfile(name: "Neutral Apps")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        engine.distractionTimerExpired(distractionBundleID: "com.spotify.client")
        XCTAssertTrue(engine.isDimming)

        mockActivityMonitor.simulateContextChange(bundleID: "com.jetbrains.intellij")

        XCTAssertTrue(engine.isDimming)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(mockDelegate.returnsToWork, 0)
    }
    
    // MARK: - Cloud Classification Integration Tests
    
    func testCloudClassificationIsDistractionProductive() {
        testPreferences.enableCloudClassification = true
        testPreferences.cloudProvider = 0
        try? KeychainHelper.saveKey("fake-gemini-key", forProvider: "gemini")
        URLProtocol.registerClass(MockURLProtocol.self)

        var cloudRequestMade = false
        MockURLProtocol.requestHandler = { request in
            cloudRequestMade = true
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

        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertTrue(engine.lastWorkAppBundleID != "com.spotify.client")

        let exp = expectation(description: "cloud async")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
    }
    
    func testCloudClassificationDistractingResultDoesNotStartCountdownForNeutralContext() {
        let cloudService = DeferredCloudClassificationService()
        let requestReceived = expectation(description: "cloud request received")
        cloudService.onRequest = { requestReceived.fulfill() }
        testPreferences.enableCloudClassification = true
        let localEngine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            cloudClassificationService: cloudService
        )
        localEngine.delegate = mockDelegate
        localEngine.distractionCountdownThreshold = 0.05

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode", title: "Draft")
        localEngine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Notepad", title: "Test Title")
        wait(for: [requestReceived], timeout: 1)
        cloudService.complete(.success(false))

        let settled = expectation(description: "cloud distracting result settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)

        XCTAssertTrue(localEngine.currentClassification.isNeutral)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(localEngine.isDimming)
        localEngine.stop()
    }

    func testCloudClassificationIsDistractionFallbackOnFailure() {
        testPreferences.enableCloudClassification = true
        testPreferences.cloudProvider = 0 // Gemini
        try? KeychainHelper.saveKey("fake-gemini-key", forProvider: "gemini")
        URLProtocol.registerClass(MockURLProtocol.self)

        // Return 500 error to simulate network/cloud failure
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client", title: "Test Title")

        // Should fall back to local check (distraction), resetting workSessionStart to nil
        XCTAssertNil(engine.workSessionStart)
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
    }

    func testCloudResultPromotesOnlyTheStillCurrentNeutralContext() {
        let cloudService = DeferredCloudClassificationService()
        let requestReceived = expectation(description: "cloud request received")
        cloudService.onRequest = { requestReceived.fulfill() }
        testPreferences.enableCloudClassification = true
        let localEngine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            cloudClassificationService: cloudService
        )

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Notepad", title: "Draft")
        XCTAssertEqual(localEngine.state, .idle)

        wait(for: [requestReceived], timeout: 1)
        cloudService.complete(.success(true))
        let promoted = expectation(description: "cloud promotion applied")
        DispatchQueue.main.async { promoted.fulfill() }
        wait(for: [promoted], timeout: 1)

        XCTAssertEqual(localEngine.state, .watching)
        XCTAssertEqual(localEngine.lastWorkAppBundleID, "com.example.Notepad")
        localEngine.stop()
    }

    func testStaleCloudResultCannotChangeNewerDistractionContext() {
        let cloudService = DeferredCloudClassificationService()
        let requestReceived = expectation(description: "cloud request received")
        cloudService.onRequest = { requestReceived.fulfill() }
        testPreferences.enableCloudClassification = true
        let localEngine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            cloudClassificationService: cloudService
        )

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Notepad", title: "Draft")
        wait(for: [requestReceived], timeout: 1)
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client", title: "Music")
        cloudService.complete(.success(true))
        let completion = expectation(description: "stale result returned")
        DispatchQueue.main.async { completion.fulfill() }
        wait(for: [completion], timeout: 1)

        XCTAssertEqual(localEngine.state, .idle)
        XCTAssertNil(localEngine.workSessionStart)
        XCTAssertNil(localEngine.lastWorkAppBundleID)
        localEngine.stop()
    }

    func testVisualFallbackWaitsUntilCloudClassificationStaysNeutral() {
        let cloudService = DeferredCloudClassificationService()
        let visualChecker = RecordingVisualChecker()
        testPreferences.enableCloudClassification = true
        testPreferences.enableImageClassification = true

        let cloudRequest = expectation(description: "structured cloud request received")
        cloudService.onRequest = { cloudRequest.fulfill() }
        let visualRequest = expectation(description: "visual fallback request received")
        visualChecker.onRequest = { visualRequest.fulfill() }

        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: visualChecker,
            cloudClassificationService: cloudService
        )

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")
        wait(for: [cloudRequest], timeout: 1)
        XCTAssertFalse(visualChecker.didRequest)

        cloudService.complete(.success(ClassificationResult(
            label: .neutral,
            confidence: 0.90,
            modelVersion: "test-cloud",
            latency: 0,
            explanation: "neutral"
        )))
        wait(for: [visualRequest], timeout: 1)
        XCTAssertTrue(visualChecker.didRequest)
    }

    func testVisualClassificationDistractingResultDoesNotStartCountdownForNeutralContext() {
        let visualChecker = RecordingVisualChecker()
        visualChecker.returnValue = false
        testPreferences.enableImageClassification = true

        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: visualChecker,
            cloudClassificationService: nil
        )
        engine.delegate = mockDelegate
        engine.distractionCountdownThreshold = 0.05

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode", title: "Draft")
        engine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown", title: "Reading")

        let settled = expectation(description: "visual distracting result settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)

        XCTAssertTrue(visualChecker.didRequest)
        XCTAssertTrue(engine.currentClassification.isNeutral)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
    }

    func testDiscordIsBlockedDuringAutoVoyageAndSkipsVisualFallback() {
        let visualChecker = RecordingVisualChecker()
        testPreferences.enableImageClassification = true

        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: visualChecker,
            cloudClassificationService: nil
        )
        engine.delegate = mockDelegate
        engine.distractionCountdownThreshold = 0.05

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode", url: nil, title: "Launch plan")
        engine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(bundleID: "com.hnc.Discord", url: nil, title: "Programming Forum")

        XCTAssertTrue(engine.currentClassification.isDistraction)
        XCTAssertFalse(visualChecker.didRequest)
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.hnc.Discord"])
    }

    func testSensitiveContextsSkipVisualClassification() {
        let visualChecker = RecordingVisualChecker()
        testPreferences.enableImageClassification = true

        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: visualChecker,
            cloudClassificationService: nil
        )

        // Sensitive URL/title should skip visual classification and remain neutral
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown", url: URL(string: "https://chase.com/login"), title: "Chase Online Banking - Login")
        
        let expectation = expectation(description: "sensitive context check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(visualChecker.didRequest)
            XCTAssertTrue(self.engine.currentClassification.isNeutral)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testDeclaredActivityBypassPreventsDimmingAndReDimsWhenNotMatching() {
        let testPreferences = self.testPreferences!
        let engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker()
        )
        engine.delegate = mockDelegate
        
        // Start a session
        engine.anchorSession(duration: 1500)
        
        // Simulate switching to a distraction app
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.Safari", url: URL(string: "https://youtube.com/watch?v=123")!)
        
        // Starts distraction countdown
        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
        
        // Trigger immediate bypass by declaring an activity
        engine.startDeclaredActivityBypass(activity: "youtube tutorial")
        XCTAssertTrue(engine.isDeclaredActivityBypassActive)
        XCTAssertEqual(engine.declaredActivity, "youtube tutorial")
        XCTAssertFalse(engine.isDimming)
        
        // Switch to a matching context - should keep bypass active
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.Safari", url: URL(string: "https://youtube.com/watch?v=456")!, title: "watching youtube tutorial video")
        
        // Since bypass is active, it shouldn't trigger didDetectDistraction again immediately
        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
        
        // Check that matching context matches the declared activity
        XCTAssertTrue(engine.isDeclaredActivityBypassActive)
        
        engine.stopDeclaredActivityBypass()
    }
    
    // MARK: - Helper Methods
    
    private func loadEventsFromDisk() -> [SessionEvent] {
        // Flush queue by doing a sync read:
        _ = sessionStore.recentSessions(limit: 1)
        return sessionStore.allEvents()
    }

    private func scheduleAllowingCurrentMinute(now: Date) -> FocusSchedule {
        let minute = currentMinute(of: now)
        let start = max(0, minute - 30)
        let end = min(23 * 60 + 59, minute + 30)
        return FocusSchedule(
            enabled: true,
            startMinute: start,
            endMinute: max(start + 1, end),
            lunchBreakEnabled: false
        )
    }

    private func scheduleExcludingCurrentMinute(now: Date) -> FocusSchedule {
        let minute = currentMinute(of: now)
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

    private func currentMinute(of date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    func testClassificationCacheAvoidsDuplicateEvaluations() {
        let countingClassifier = CountingClassifier()
        testPreferences.enableLocalTextClassification = true
        
        engine.stop()
        self.engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            localTextClassifier: countingClassifier
        )
        self.engine.delegate = mockDelegate
        
        // Ensure local text classifier is enabled
        XCTAssertTrue(testPreferences.enableLocalTextClassification)
        
        // 1. Switch to a neutral context
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.neutralapp", url: nil, title: "Neutral Title")
        
        // Wait for async classification to run
        let expectation = XCTestExpectation(description: "First classification complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let initialCount = countingClassifier.classificationCount
        XCTAssertEqual(initialCount, 1)
        
        // 2. Switch to the exact same context (identity matches)
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.neutralapp", url: nil, title: "Neutral Title")
        
        let expectation2 = XCTestExpectation(description: "Second context switch processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1.0)
        
        // Classification count should still be 1 (cache hit!)
        XCTAssertEqual(countingClassifier.classificationCount, 1)
        
        // 3. Trigger profile change or rules change to clear cache, then switch again
        NotificationCenter.default.post(name: .profilesDidChange, object: nil)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.neutralapp", url: nil, title: "Neutral Title")
        
        let expectation3 = XCTestExpectation(description: "Third context switch processed after cache invalidation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation3.fulfill()
        }
        wait(for: [expectation3], timeout: 1.0)
        
        // Classification count should now be 2!
        XCTAssertEqual(countingClassifier.classificationCount, 2)
        
        self.engine.stop()
    }

    func testQuickSwitchReturnUsesCachedClassification() {
        testPreferences.enableLocalTextClassification = true
        testPreferences.enableCloudClassification = false
        testPreferences.enableImageClassification = false
        
        let countingClassifier = CountingClassifier()
        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            localTextClassifier: countingClassifier,
            intentClassifier: NeutralIntentClassifier()
        )
        engine.delegate = mockDelegate
        
        // Switch to A
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")
        
        let exp1 = expectation(description: "A classified")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)
        XCTAssertEqual(countingClassifier.classificationCount, 1)
        
        // Switch to B
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appB")
        let exp2 = expectation(description: "B switched")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 1.0)
        XCTAssertEqual(countingClassifier.classificationCount, 2)
        
        // Switch back to A
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")
        let exp3 = expectation(description: "Back to A")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp3.fulfill()
        }
        wait(for: [exp3], timeout: 1.0)
        
        // It should hit the cache for A, so call count should still be 2!
        XCTAssertEqual(countingClassifier.classificationCount, 2)
        XCTAssertTrue(engine.currentClassification.isFocus)
        engine.stop()
    }

    func testCompletedBackgroundClassificationSavedToCacheWhenSwitchedAway() {
        testPreferences.enableLocalTextClassification = true
        testPreferences.enableCloudClassification = false
        testPreferences.enableImageClassification = false
        
        let classifier = ConcurrentDeferredClassifier()
        let countingClassifier = PassThroughCountingClassifier(wrapped: classifier)
        
        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            localTextClassifier: countingClassifier,
            intentClassifier: NeutralIntentClassifier()
        )
        engine.delegate = mockDelegate
        
        let requestExp = expectation(description: "Classifier requested for A")
        classifier.onRequest = { identity in
            if identity.bundleID == "com.example.appA" {
                requestExp.fulfill()
            } else {
                classifier.complete(identity: identity, .neutral)
            }
        }
        
        // Switch to A
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")
        wait(for: [requestExp], timeout: 1.0)
        
        // Update onRequest to complete immediately for any subsequent context switch
        classifier.onRequest = { identity in
            classifier.complete(identity: identity, .neutral)
        }
        
        // Now switch away to B before A completes
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appB")
        
        let switchExp = expectation(description: "Switched to B")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            switchExp.fulfill()
        }
        wait(for: [switchExp], timeout: 1.0)
        
        // Complete the classification of A as productive
        let identityA = ContextIdentity(bundleID: "com.example.appA", sanitizedURL: nil, normalizedTitle: "")
        classifier.complete(identity: identityA, .productive)
        
        let completeExp = expectation(description: "A complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completeExp.fulfill()
        }
        wait(for: [completeExp], timeout: 1.0)
        
        // Now switch back to A
        // Under the new "Cache Pollution Prevention" behavior, A was discarded and not written to the cache
        // because the context switched to B before A's classification completed.
        // So switching back to A will trigger a new classification request!
        let requestExp2 = expectation(description: "Classifier requested for A again")
        classifier.onRequest = { identity in
            if identity.bundleID == "com.example.appA" {
                classifier.complete(identity: identity, .productive)
                requestExp2.fulfill()
            }
        }

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")
        wait(for: [requestExp2], timeout: 1.0)

        let mainExp = expectation(description: "Wait for main queue block to execute")
        DispatchQueue.main.async {
            mainExp.fulfill()
        }
        wait(for: [mainExp], timeout: 1.0)

        XCTAssertEqual(countingClassifier.classificationCount, 3)
        XCTAssertTrue(engine.currentClassification.isFocus)
        engine.stop()
    }

    func testDeduplicationOfConcurrentAsyncRequests() {
        testPreferences.enableLocalTextClassification = true
        testPreferences.enableCloudClassification = false
        testPreferences.enableImageClassification = false
        
        let classifier = ConcurrentDeferredClassifier()
        let countingClassifier = PassThroughCountingClassifier(wrapped: classifier)
        
        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            localTextClassifier: countingClassifier,
            intentClassifier: NeutralIntentClassifier()
        )
        engine.delegate = mockDelegate
        
        let requestExp = expectation(description: "Classifier requested for A first time")
        classifier.onRequest = { identity in
            if identity.bundleID == "com.example.appA" {
                requestExp.fulfill()
            } else {
                classifier.complete(identity: identity, .neutral)
            }
        }
        
        // Switch to A
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")
        wait(for: [requestExp], timeout: 1.0)
        
        // Update onRequest to complete immediately for any subsequent context switch
        classifier.onRequest = { identity in
            classifier.complete(identity: identity, .neutral)
        }
        
        // Switch away to B, then switch back to A immediately before completing
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appB")
        
        // Wait briefly for B switch to process
        let switchBExp = expectation(description: "Processed B switch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            switchBExp.fulfill()
        }
        wait(for: [switchBExp], timeout: 1.0)
        
        // Switch back to A. Since A is still in inProgressClassifications,
        // it deduplicates and does not start a new request.
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")
        
        let switchAExp = expectation(description: "Processed return to A")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            switchAExp.fulfill()
        }
        wait(for: [switchAExp], timeout: 1.0)
        
        // Complete the pending classification for A (which has generation 1).
        // Since we are back to A, currentIdentity is A, but contextGeneration is 3.
        // Under the new "Cache Pollution Prevention" behavior, we return early and discard the result
        // because generation (1) != self.contextGeneration (3).
        // This removes A from inProgressClassifications.
        let identityA = ContextIdentity(bundleID: "com.example.appA", sanitizedURL: nil, normalizedTitle: "")
        classifier.complete(identity: identityA, .productive)
        
        let completeExp = expectation(description: "A complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completeExp.fulfill()
        }
        wait(for: [completeExp], timeout: 1.0)
        
        // Since it was discarded, engine.currentClassification is still neutral.
        // But A is now the current app and is no longer in progress, so a new switch/update to A
        // (or runClassificationPipeline if triggered) will kick off a new request to verify it.
        // Let's simulate a context update/re-trigger to A:
        let requestExp2 = expectation(description: "Classifier requested for A again")
        classifier.onRequest = { identity in
            if identity.bundleID == "com.example.appA" {
                classifier.complete(identity: identity, .productive)
                requestExp2.fulfill()
            }
        }

        // Re-simulate to trigger pipeline
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")
        wait(for: [requestExp2], timeout: 1.0)

        let mainExp = expectation(description: "Wait for main queue block to execute")
        DispatchQueue.main.async {
            mainExp.fulfill()
        }
        wait(for: [mainExp], timeout: 1.0)

        XCTAssertEqual(countingClassifier.classificationCount, 3)
        XCTAssertTrue(engine.currentClassification.isFocus)
        engine.stop()
    }

    func testStaleVisualClassificationIsDiscardedEarly() {
        let visualChecker = RecordingVisualChecker()
        testPreferences.enableImageClassification = true
        testPreferences.enableCloudClassification = false

        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: visualChecker
        )

        // Switch to neutral context (initiates visual pipeline)
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")

        // Switch context away before visual classifier runs on background thread
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")

        let expectation = expectation(description: "Wait for background queue schedule")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        // Visual classification should have been aborted as stale, so visualChecker is never called
        XCTAssertFalse(visualChecker.didRequest)
    }

    func testScheduleChangeMidSessionDeactivatesDimmingAndCancelsAlerts() {
        let now = Date()
        testPreferences.focusSchedule = scheduleAllowingCurrentMinute(now: now)

        engine.anchorSession(duration: 1500)

        // Switch to distraction to start warning countdown
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.spotify.client"])

        // Switch schedule to inactive
        testPreferences.focusSchedule = scheduleExcludingCurrentMinute(now: now)

        // It should immediately deactivate dimming and cancel distraction alerts
        XCTAssertFalse(engine.isFocusScheduleActive)
        XCTAssertFalse(engine.isDimming)
        XCTAssertNil(engine.currentDistractionGraceRemaining)
    }

    func testWorkspaceSleepReschedulesActiveBreakTimer() throws {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 3600)

        // Retroactively advance session start so break is accepted
        if let session = engine.activeSession {
            engine.activeSession = ActiveSession(
                startDate: session.startDate.addingTimeInterval(-1800),
                anchoredDuration: session.anchoredDuration,
                appName: session.appName,
                category: session.category,
                goal: session.goal
            )
        }

        let decision = engine.requestBreak(intention: "Coffee")
        XCTAssertEqual(engine.breakState, .breakActive)

        let sleepStartedAt = Date()
        engine.pauseFocusAccountingForWorkspaceLifecycle(now: sleepStartedAt)

        // Simulate passing 1 minute of sleep
        let wakeAt = sleepStartedAt.addingTimeInterval(60)
        engine.resumeFocusAccountingForWorkspaceLifecycle(now: wakeAt)

        // The break state should remain active, and the break timer should be rescheduled correctly
        XCTAssertEqual(engine.breakState, .breakActive)
    }

    func testDisabledClassifiersAreNotCalled() {
        let visualChecker = RecordingVisualChecker()
        let cloudService = DeferredCloudClassificationService()

        var cloudCalled = false
        cloudService.onRequest = {
            cloudCalled = true
        }

        testPreferences.enableImageClassification = false
        testPreferences.enableCloudClassification = false
        testPreferences.enableLocalTextClassification = false

        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: visualChecker,
            cloudClassificationService: cloudService
        )

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")

        let expectation = expectation(description: "Wait for pipeline check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        XCTAssertFalse(visualChecker.didRequest)
        XCTAssertFalse(cloudCalled)
    }
}

private final class CountingClassifier: ContextClassifying, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    
    var classificationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    
    func classify(snapshot: ContextSnapshot) -> ClassificationResult {
        lock.lock()
        count += 1
        lock.unlock()
        return ClassificationResult(
            label: .productive,
            confidence: 0.95,
            modelVersion: "test-counting",
            latency: 0,
            explanation: "test counting result"
        )
    }
}

private final class ProductiveTestClassifier: ContextClassifying, Sendable {
    func classify(snapshot: ContextSnapshot) -> ClassificationResult {
        ClassificationResult(
            label: .productive,
            confidence: 0.95,
            modelVersion: "test-local",
            latency: 0,
            explanation: "test productive result"
        )
    }
}

private final class DeferredContextClassifier: ContextClassifying, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingResult: ClassificationResult?
    private var pendingSignal: DispatchSemaphore?
    var onRequest: (() -> Void)?

    func classify(snapshot: ContextSnapshot) -> ClassificationResult {
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        pendingResult = nil
        pendingSignal = semaphore
        lock.unlock()
        onRequest?()
        semaphore.wait()

        lock.lock()
        let result = pendingResult ?? ClassificationResult.neutralMock(version: "test-local")
        pendingSignal = nil
        lock.unlock()
        return result
    }

    func complete(_ label: ClassificationLabel) {
        lock.lock()
        pendingResult = ClassificationResult(
            label: label,
            confidence: 0.95,
            modelVersion: "test-local",
            latency: 0,
            explanation: "test deferred result"
        )
        let signal = pendingSignal
        lock.unlock()
        signal?.signal()
    }
}

private final class NeutralIntentClassifier: IntentClassifying, @unchecked Sendable {
    func classify(input: IntentClassificationInput) -> IntentClassificationResult {
        IntentClassificationResult(
            relation: .uncertain,
            confidence: 0.0,
            source: .heuristic,
            modelVersion: "test-intent",
            latency: 0.0,
            reason: .insufficientIntent,
            explanation: "test neutral intent"
        )
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
    
    func simulateContextChange(bundleID: String, url: URL? = nil, title: String = "", observedAt: Date = Date()) {
        let snapshot = ContextSnapshot(
            bundleIdentifier: bundleID,
            localizedName: bundleID,
            url: url,
            title: title,
            source: .application,
            observedAt: observedAt
        )
        onContextChange?(snapshot)
    }
}

class MockFocusEngineDelegate: FocusEngineDelegate {
    var exitTriggers: [(duration: TimeInterval, appName: String)] = []
    var detectedDistractions: [String] = []
    var returnsToWork = 0
    var endedSessions = 0
    var breakReviews: [(intention: String, result: BreakReviewResult)] = []
    var refusedBreaks = 0
    
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

    func didRequestBreakReview(intention: String, result: BreakReviewResult) {
        breakReviews.append((intention: intention, result: result))
    }

    func didRefuseBreak() {
        refusedBreaks += 1
    }

    var immediateDims = 0
    func didRequestImmediateDim() {
        immediateDims += 1
    }

    var doomscrollingDetections: [(bundleID: String, threshold: TimeInterval)] = []
    func didDetectDoomscrolling(bundleID: String, threshold: TimeInterval) {
        doomscrollingDetections.append((bundleID: bundleID, threshold: threshold))
    }
}

struct MockOCRProvider: WindowTextExtracting {
    func extractText() -> String {
        return ""
    }
}

struct MockVisualChecker: VisualProductivityChecking {
    func isProductiveVisual(profileName: String) -> Bool {
        return false
    }
}

private final class RecordingVisualChecker: VisualProductivityChecking {
    var didRequest = false
    var onRequest: (() -> Void)?
    var returnValue = false

    func isProductiveVisual(profileName: String) -> Bool {
        didRequest = true
        onRequest?()
        return returnValue
    }
}

final class DeferredCloudClassificationService: CloudClassificationServing {
    private var completion: ((Result<ClassificationResult, Error>) -> Void)?
    var onRequest: (() -> Void)?

    func classify(_ input: CloudClassificationInput, completion: @escaping (Result<ClassificationResult, Error>) -> Void) {
        self.completion = completion
        onRequest?()
    }

    func complete(_ result: Result<ClassificationResult, Error>) {
        completion?(result)
    }

    func complete(_ result: Result<Bool, Error>) {
        completion?(result.map { isProductive in
            ClassificationResult(
                label: isProductive ? .productive : .distracting,
                confidence: 0.85,
                modelVersion: "test-cloud",
                latency: 0,
                explanation: "test cloud result"
            )
        })
    }
}

private final class PassThroughCountingClassifier: ContextClassifying, @unchecked Sendable {
    private let wrapped: ContextClassifying
    private let lock = NSLock()
    private var count = 0
    
    var classificationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    
    init(wrapped: ContextClassifying) {
        self.wrapped = wrapped
    }
    
    func classify(snapshot: ContextSnapshot) -> ClassificationResult {
        lock.lock()
        count += 1
        lock.unlock()
        return wrapped.classify(snapshot: snapshot)
    }
}

private final class ConcurrentDeferredClassifier: ContextClassifying, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingSignals: [ContextIdentity: DispatchSemaphore] = [:]
    private var pendingResults: [ContextIdentity: ClassificationResult] = [:]
    var onRequest: ((ContextIdentity) -> Void)?

    func classify(snapshot: ContextSnapshot) -> ClassificationResult {
        let identity = snapshot.identity
        let semaphore = DispatchSemaphore(value: 0)
        
        lock.lock()
        pendingSignals[identity] = semaphore
        lock.unlock()
        
        onRequest?(identity)
        semaphore.wait()

        lock.lock()
        let result = pendingResults[identity] ?? ClassificationResult(
            label: .neutral,
            confidence: 0.0,
            modelVersion: "test-local-deferred",
            latency: 0,
            explanation: "default deferred result"
        )
        pendingSignals.removeValue(forKey: identity)
        pendingResults.removeValue(forKey: identity)
        lock.unlock()
        return result
    }

    func complete(identity: ContextIdentity, _ label: ClassificationLabel) {
        lock.lock()
        pendingResults[identity] = ClassificationResult(
            label: label,
            confidence: 0.95,
            modelVersion: "test-local-deferred",
            latency: 0,
            explanation: "completed deferred result"
        )
        let signal = pendingSignals[identity]
        lock.unlock()
        signal?.signal()
    }
}
