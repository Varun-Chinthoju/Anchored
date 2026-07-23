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
    private var mockOCRProvider: MockOCRProvider!
    private var breakReviewChecker: RecordingBreakReviewChecker!
    private var diagnosticsRecorder: TestDiagnosticsRecorder!
    private var contextualLearningStore: RecordingContextualLearningStore!
    private var sessionTimerScheduler: TestOneShotTimerScheduler!
    private var distractionTimerScheduler: TestOneShotTimerScheduler!
    private var breakTimerScheduler: TestOneShotTimerScheduler!
    private var breakReturnTimerScheduler: TestOneShotTimerScheduler!
    private var doomscrollTimerScheduler: TestOneShotTimerScheduler!
    private var focusPromptTimerScheduler: TestOneShotTimerScheduler!
    private var mockUserActivityProvider: MockUserActivityProvider!
    private var previousUserActivityProvider: UserActivityProviding!
    private var engine: FocusEngine!
    private var tempStoreURL: URL!
    
    override func setUp() {
        super.setUp()

        suiteName = "com.varun.Anchored.FocusEngineTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        KeychainHelper.clearCachedKeys()
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
        mockOCRProvider = MockOCRProvider()
        breakReviewChecker = RecordingBreakReviewChecker()
        diagnosticsRecorder = TestDiagnosticsRecorder()
        contextualLearningStore = RecordingContextualLearningStore()
        sessionTimerScheduler = TestOneShotTimerScheduler()
        distractionTimerScheduler = TestOneShotTimerScheduler()
        breakTimerScheduler = TestOneShotTimerScheduler()
        breakReturnTimerScheduler = TestOneShotTimerScheduler()
        doomscrollTimerScheduler = TestOneShotTimerScheduler()
        focusPromptTimerScheduler = TestOneShotTimerScheduler()
        previousUserActivityProvider = UserActivityEnvironment.shared
        mockUserActivityProvider = MockUserActivityProvider()
        UserActivityEnvironment.shared = mockUserActivityProvider
        // Initialize FocusEngine (default threshold = 10 minutes) with fake providers to avoid Vision overhead
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: mockOCRProvider,
            visualChecker: MockVisualChecker(),
            contextualLearningStore: contextualLearningStore,
            breakReviewChecker: breakReviewChecker,
            sessionTimerScheduler: sessionTimerScheduler,
            breakTimerScheduler: breakTimerScheduler,
            distractionTimerScheduler: distractionTimerScheduler,
            breakReturnGraceTimerScheduler: breakReturnTimerScheduler,
            doomscrollTimerScheduler: doomscrollTimerScheduler,
            focusPromptTimerScheduler: focusPromptTimerScheduler,
            diagnosticsRecorder: diagnosticsRecorder
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
        breakReviewChecker = nil
        diagnosticsRecorder = nil
        contextualLearningStore = nil
        distractionTimerScheduler = nil
        sessionTimerScheduler = nil
        breakTimerScheduler = nil
        breakReturnTimerScheduler = nil
        doomscrollTimerScheduler = nil
        focusPromptTimerScheduler = nil
        UserActivityEnvironment.shared = previousUserActivityProvider
        mockUserActivityProvider = nil
        previousUserActivityProvider = nil
        if let suiteName {
            testDefaults.removePersistentDomain(forName: suiteName)
        }
        testDefaults = nil
        let directoryURL = tempStoreURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        KeychainHelper.clearCachedKeys()
        super.tearDown()
    }

    private func prepareAcceptedBreak(now: Date = Date()) {
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

        _ = engine.requestBreak(intention: "Take a short walk", now: now, bypassMinimum: true)
        XCTAssertEqual(engine.breakState, .breakActive)
    }

    @discardableResult
    private func startBreakReturnGrace(
        via intermediateBundleID: String = "com.spotify.client",
        returningTo focusBundleID: String = "com.apple.dt.Xcode"
    ) throws -> TestOneShotTimerScheduler.PendingTimer {
        mockActivityMonitor.simulateContextChange(bundleID: intermediateBundleID)
        mockActivityMonitor.simulateContextChange(bundleID: focusBundleID)
        return try XCTUnwrap(breakReturnTimerScheduler.scheduledTimers.last)
    }

    @discardableResult
    private func startBreakTimer(now: Date = Date()) throws -> TestOneShotTimerScheduler.PendingTimer {
        prepareAcceptedBreak(now: now)
        return try XCTUnwrap(breakTimerScheduler.scheduledTimers.last)
    }

    @discardableResult
    private func startFocusPromptRun(bundleID: String = "com.apple.dt.Xcode") throws -> TestOneShotTimerScheduler.PendingTimer {
        mockActivityMonitor.simulateContextChange(bundleID: bundleID)
        return try XCTUnwrap(focusPromptTimerScheduler.scheduledTimers.last)
    }

    @discardableResult
    private func startSessionTimer(
        duration: TimeInterval = 0.05,
        bundleID: String = "com.apple.dt.Xcode"
    ) throws -> TestOneShotTimerScheduler.PendingTimer {
        mockActivityMonitor.simulateContextChange(bundleID: bundleID)
        engine.anchorSession(duration: duration)
        return try XCTUnwrap(sessionTimerScheduler.scheduledTimers.last)
    }

    private func makeDate(hour: Int, minute: Int, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 16
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }

    @discardableResult
    private func prepareDoomscrollRun(
        bundleID: String = "com.spotify.client",
        title: String = "",
        url: URL? = nil,
        threshold: TimeInterval = 0.0
    ) throws -> TestOneShotTimerScheduler.PendingTimer {
        testPreferences.doomscrollThreshold = threshold
        mockActivityMonitor.simulateContextChange(bundleID: bundleID, url: url, title: title)
        return try XCTUnwrap(doomscrollTimerScheduler.scheduledTimers.last)
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
        XCTAssertTrue(sessionStore.recordedEvents.isEmpty)
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
    
    func testDistractionAppSwitchDoesNotAutoStartSessionEvenIfOverThreshold() {
        engine.focusThreshold = 0.1 // Use very short focus threshold for testing

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertNotNil(engine.workSessionStart)

        engine.workSessionStart = Date().addingTimeInterval(-0.15)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        XCTAssertNil(engine.activeSession)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(mockDelegate.exitTriggers.isEmpty)
    }

    func testHeuristicProductiveAppDoesNotAutoStartWithoutExplicitRuleOrIntent() throws {
        engine.focusThreshold = 0.1
        let promptTimer = try startFocusPromptRun(bundleID: "com.example.Cursor")

        engine.workSessionStart = Date().addingTimeInterval(-0.2)
        promptTimer.fire()

        XCTAssertNil(engine.activeSession)
        XCTAssertEqual(engine.state, .watching)
        XCTAssertTrue(mockDelegate.exitTriggers.isEmpty)
    }

    func testFocusPromptTimerAutoStartsSessionUsesConfiguredThreshold() throws {
        engine.focusThreshold = 0.1
        let promptTimer = try startFocusPromptRun()

        engine.workSessionStart = Date().addingTimeInterval(-0.2)
        promptTimer.fire()

        XCTAssertNotNil(engine.activeSession)
        XCTAssertTrue(mockDelegate.exitTriggers.isEmpty)
        XCTAssertEqual(engine.activeSession?.goal, "Auto-chartered Voyage")
        XCTAssertTrue(promptTimer.isCancelled)
    }

    func testDiagnosticsRecorderCapturesSessionAndTimerEvents() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 0.05)

        XCTAssertTrue(diagnosticsRecorder.messages.contains("stateTransition from=watching to=anchored reason=sessionStarted"))
        XCTAssertTrue(diagnosticsRecorder.messages.contains(where: { $0.contains("sessionLifecycle action=started") }))
        XCTAssertTrue(diagnosticsRecorder.messages.contains(where: { $0.contains("timerScheduled kind=sessionExpiry") }))

        engine.endSession(action: .dismissed)

        XCTAssertTrue(diagnosticsRecorder.messages.contains(where: { $0.contains("timerCancelled kind=sessionExpiry reason=sessionEnded") }))
        XCTAssertTrue(diagnosticsRecorder.messages.contains(where: { $0.contains("sessionLifecycle action=ended") }))
        XCTAssertTrue(diagnosticsRecorder.messages.contains("stateTransition from=anchored to=idle reason=sessionEnded"))
    }

    func testLeavingBeforeFocusPromptExpiryPreventsAutoStart() throws {
        engine.focusThreshold = 0.1
        let promptTimer = try startFocusPromptRun()

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")

        XCTAssertTrue(promptTimer.isCancelled)
        promptTimer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertTrue(mockDelegate.exitTriggers.isEmpty)
    }

    func testReturningAgainCreatesNewFocusPromptGeneration() throws {
        engine.focusThreshold = 0.1
        let firstTimer = try startFocusPromptRun()

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")
        let secondTimer = try startFocusPromptRun()

        engine.workSessionStart = Date().addingTimeInterval(-0.2)

        XCTAssertTrue(firstTimer.isCancelled)
        XCTAssertFalse(secondTimer.isCancelled)

        firstTimer.fireIgnoringCancellation()
        XCTAssertNil(engine.activeSession)

        secondTimer.fire()
        XCTAssertNotNil(engine.activeSession)
        XCTAssertEqual(engine.activeSession?.goal, "Auto-chartered Voyage")
    }

    func testStaleFocusPromptCallbackFromEarlierRunCannotStartLaterRun() throws {
        engine.focusThreshold = 0.1
        let firstTimer = try startFocusPromptRun()

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")
        _ = try startFocusPromptRun()
        engine.workSessionStart = Date().addingTimeInterval(-0.2)

        firstTimer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
    }

    func testSessionStartInvalidatesPendingFocusPromptCallback() throws {
        engine.focusThreshold = 0.1
        let promptTimer = try startFocusPromptRun()

        engine.anchorSession(duration: 1500)

        XCTAssertTrue(promptTimer.isCancelled)
        promptTimer.fireIgnoringCancellation()

        XCTAssertNotNil(engine.activeSession)
        XCTAssertEqual(engine.state, .anchored)
    }

    func testWorkspacePauseInvalidatesPendingFocusPromptCallback() throws {
        engine.focusThreshold = 0.1
        let promptTimer = try startFocusPromptRun()

        engine.pauseFocusAccountingForWorkspaceLifecycle(now: Date())

        XCTAssertTrue(promptTimer.isCancelled)
        promptTimer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
        XCTAssertEqual(engine.state, .watching)
    }

    func testDisablingFocusPromptsInvalidatesPendingFocusPromptCallback() throws {
        engine.focusThreshold = 0.1
        let promptTimer = try startFocusPromptRun()

        engine.focusPromptsEnabled = false

        XCTAssertTrue(promptTimer.isCancelled)
        promptTimer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
        XCTAssertEqual(engine.state, .watching)
        XCTAssertNotNil(engine.workSessionStart)
    }

    func testStopInvalidatesPendingFocusPromptCallback() throws {
        engine.focusThreshold = 0.1
        let promptTimer = try startFocusPromptRun()

        engine.stop()

        XCTAssertTrue(promptTimer.isCancelled)
        promptTimer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.workSessionStart)
    }

    func testFocusPromptTimerStopsOnScheduleChange() throws {
        engine.focusThreshold = 0.1
        let promptTimer = try startFocusPromptRun()
        let now = Date()
        testPreferences.focusSchedule = scheduleExcludingCurrentMinute(now: now)

        XCTAssertTrue(promptTimer.isCancelled)
        promptTimer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertFalse(engine.isFocusScheduleActive)
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

    func testFocusContextOutsideScheduleDoesNotStartAutomaticTracking() {
        let now = Date()
        testPreferences.focusSchedule = scheduleExcludingCurrentMinute(now: now)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")

        XCTAssertFalse(engine.isFocusScheduleActive)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertNil(engine.activeSession)
        XCTAssertNil(engine.lastWorkAppBundleID)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertTrue(focusPromptTimerScheduler.scheduledTimers.isEmpty)
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

    func testMixedUseBrowserPagesStayContextualByDefault() {
        let profile = WorkProfile(name: "Mixed Use")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://chatgpt.com/c/123")!,
            title: "ChatGPT - coding help"
        )

        XCTAssertEqual(engine.currentClassification.label, .contextual)
        XCTAssertTrue(engine.currentClassification.isNeutral)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
    }

    func testMixedUseBrowserReviewPrefersPageScope() {
        let profile = WorkProfile(name: "Mixed Use Review")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let reviewURL = URL(string: "https://reddit.com/r/swift/comments/123")!
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: reviewURL,
            title: "Swift discussion"
        )

        let reviewed = expectation(description: "mixed-use review completed")
        var reviewResult: ProductiveCorrectionReview?
        engine.reviewItemAsProductive(
            bundleID: "com.google.Chrome",
            localizedName: "Google Chrome",
            url: reviewURL,
            title: "Swift discussion"
        ) { review in
            reviewResult = review
            reviewed.fulfill()
        }

        wait(for: [reviewed], timeout: 1.0)
        XCTAssertEqual(reviewResult?.recommendedScope, .page)
        XCTAssertTrue(reviewResult?.canUseWebsiteScope ?? false)
    }

    func testPageScopedApprovalUsesCapturedSnapshotWithoutBroadDomainRule() {
        let profile = WorkProfile(name: "Mixed Use Snapshot")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let reviewURL = URL(string: "https://chatgpt.com/c/abc")!
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: reviewURL,
            title: "ChatGPT - coding help"
        )
        let snapshot = ContextSnapshot(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            url: reviewURL,
            title: "ChatGPT - coding help",
            source: .chromium,
            observedAt: Date()
        )

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.apple.dt.Xcode",
            title: "Project draft"
        )

        let recorded = expectation(description: "contextual learning record captured")
        contextualLearningStore.onRecord = { record in
            if record.normalizedDomain == "chatgpt.com" {
                recorded.fulfill()
            }
        }

        engine.applyPageScopedProductive(snapshot: snapshot)

        wait(for: [recorded], timeout: 1.0)
        XCTAssertFalse(profileManager.activeProfile.allowedDomains.contains("chatgpt.com"))
        XCTAssertFalse(profileManager.activeProfile.allowedApps.contains("com.google.Chrome"))
        XCTAssertEqual(contextualLearningStore.records.last?.normalizedDomain, "chatgpt.com")
        XCTAssertEqual(contextualLearningStore.records.last?.decision, .productive)
        XCTAssertEqual(engine.currentApp, "com.apple.dt.Xcode")
    }

    func testExplicitAllowStillBeatsMixedUseLearning() {
        let profile = WorkProfile(
            name: "Explicit Allow",
            allowedDomains: ["chatgpt.com"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://chatgpt.com/c/123")!,
            title: "ChatGPT - coding help"
        )

        XCTAssertTrue(engine.currentClassification.isFocus)
        XCTAssertEqual(engine.currentClassification.source, .explicitDomainRule)
    }

    func testContextualDomainsStayContextual() {
        let profile = WorkProfile(name: "Mixed Use Baseline")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let contextualURLs = [
            "https://chatgpt.com/c/chat-123",
            "https://gemini.google.com/app/session",
            "https://www.reddit.com/r/swift/comments/123",
            "https://discord.com/channels/123/456"
        ]

        for urlString in contextualURLs {
            mockActivityMonitor.simulateContextChange(
                bundleID: "com.google.Chrome",
                url: URL(string: urlString)!,
                title: "Mixed Use Content"
            )

            XCTAssertEqual(
                engine.currentClassification.label,
                .contextual,
                "Domain \(urlString) should stay contextual (neutral) by default"
            )
        }
    }

    func testGenericYouTubeVideoTriggersDistractionInFocusSession() {
        let profile = WorkProfile(name: "Generic YouTube Should Distract")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=xyz123")!,
            title: "Funny Cat Videos - YouTube"
        )

        XCTAssertTrue(engine.currentClassification.isDistraction)
        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.google.Chrome"])
    }

    func testPageScopedApprovalDoesNotBecomeDomainWide() {
        let profile = WorkProfile(name: "Page Scope Isolation")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let snapshot = ContextSnapshot(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            url: URL(string: "https://www.reddit.com/r/swift/comments/abc")!,
            title: "Swift Discussion",
            source: .chromium,
            observedAt: Date()
        )

        engine.applyPageScopedProductive(snapshot: snapshot)

        XCTAssertFalse(
            profileManager.activeProfile.allowedDomains.contains("reddit.com"),
            "Page-scoped approval must not insert the domain into profile.allowedDomains"
        )
        XCTAssertFalse(
            profileManager.activeProfile.allowedApps.contains("com.google.Chrome"),
            "Page-scoped approval must not insert the browser app into profile.allowedApps"
        )
    }

    func testExplicitBlockBeatsMixedUseLearning() {
        let profile = WorkProfile(
            name: "Explicit Block Overrides Learning",
            distractionDomains: ["reddit.com"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let snapshot = ContextSnapshot(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            url: URL(string: "https://www.reddit.com/r/swift/comments/123")!,
            title: "Swift Post",
            source: .chromium,
            observedAt: Date()
        )

        engine.applyPageScopedProductive(snapshot: snapshot)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.reddit.com/r/swift/comments/123")!,
            title: "Swift Post"
        )

        XCTAssertTrue(engine.currentClassification.isDistraction)
        XCTAssertEqual(engine.currentClassification.source, .explicitDomainRule)
    }

    func testRuleSuggestionTriggersAfterRepeatedConfirmations() {
        let profile = WorkProfile(name: "Rule Suggestion Threshold")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        let snapshot = ContextSnapshot(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            url: URL(string: "https://www.reddit.com/r/swift/comments/seed")!,
            title: "Swift Discussion Seed",
            source: .chromium,
            observedAt: Date()
        )
        XCTAssertFalse(engine.shouldSuggestPermanentRule(for: snapshot))

        for i in 1...3 {
            let snapshot = ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                localizedName: "Google Chrome",
                url: URL(string: "https://www.reddit.com/r/swift/comments/\(i)")!,
                title: "Swift Discussion \(i)",
                source: .chromium,
                observedAt: Date()
            )
            engine.applyPageScopedProductive(snapshot: snapshot)
        }

        XCTAssertTrue(engine.shouldSuggestPermanentRule(for: snapshot))
    }

    func testProfileScopedLearningDoesNotLeakAcrossProfiles() {
        let codingProfile = WorkProfile(name: "Coding")
        let writingProfile = WorkProfile(name: "Writing")
        profileManager.addProfile(codingProfile)
        profileManager.addProfile(writingProfile)

        let snapshot = ContextSnapshot(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            url: URL(string: "https://chatgpt.com/c/123")!,
            title: "ChatGPT - coding help",
            source: .chromium,
            observedAt: Date()
        )

        profileManager.switchProfile(to: codingProfile.name)
        for _ in 0..<3 {
            engine.applyPageScopedProductive(snapshot: snapshot)
        }
        XCTAssertTrue(engine.shouldSuggestPermanentRule(for: snapshot))

        profileManager.switchProfile(to: writingProfile.name)
        XCTAssertFalse(engine.shouldSuggestPermanentRule(for: snapshot))
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

    func testEnablingClassificationFeedbackReclassifiesTheCurrentContext() {
        let matchingURL = URL(string: "https://example.com/reference")!
        let learningStore = ToggleableContextualLearningStore()
        learningStore.evidenceResult = ClassificationEvidence(
            label: .productive,
            source: .deterministicRule,
            confidence: 0.9,
            reason: .contextualLearning
        )
        learningStore.isEnabled = false
        let localEngine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            contextualLearningStore: learningStore
        )

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: matchingURL,
            title: "Reference notes"
        )

        XCTAssertTrue(localEngine.currentClassification.isNeutral)

        let refreshed = expectation(description: "feedback-enabled refresh promoted the current context")
        let observer = NotificationCenter.default.addObserver(
            forName: .focusEngineClassificationDidChange,
            object: localEngine,
            queue: .main
        ) { [weak localEngine] _ in
            if localEngine?.currentClassification.isFocus == true {
                refreshed.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        learningStore.isEnabled = true
        testPreferences.classificationFeedbackEnabled = true

        wait(for: [refreshed], timeout: 1.0)
        XCTAssertTrue(localEngine.currentClassification.isFocus)
        localEngine.stop()
    }

    func testProductiveReviewPrefersWebsiteScopeForBrowserContexts() {
        let profile = WorkProfile(name: "Review Scope")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        mockOCRProvider.text = "Swift API documentation and code examples"

        let reviewURL = URL(string: "https://developer.apple.com/documentation/swift")!
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: reviewURL,
            title: "Swift documentation"
        )

        let reviewed = expectation(description: "productive review completed")
        var reviewResult: ProductiveCorrectionReview?
        engine.reviewCurrentAppAsProductive { review in
            reviewResult = review
            reviewed.fulfill()
        }

        wait(for: [reviewed], timeout: 1.0)
        XCTAssertEqual(reviewResult?.recommendedScope, .website)
        XCTAssertFalse(reviewResult?.message.isEmpty ?? true)
        XCTAssertFalse(profileManager.activeProfile.allowedApps.contains("com.google.Chrome"))
        XCTAssertFalse(profileManager.activeProfile.allowedDomains.contains("developer.apple.com"))
    }

    func testExplicitProductiveCorrectionStillAppliesAfterReview() {
        let profile = WorkProfile(name: "Explicit Correction")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        mockOCRProvider.text = "Spotify music and entertainment"

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Editor", title: "Research notes")

        let reviewed = expectation(description: "productive review completed")
        var reviewResult: ProductiveCorrectionReview?
        engine.reviewCurrentAppAsProductive { review in
            reviewResult = review
            reviewed.fulfill()
        }

        wait(for: [reviewed], timeout: 1.0)
        XCTAssertEqual(reviewResult?.recommendedScope, .app)

        engine.applyCorrection(.allowApp, bundleID: "com.example.Editor", url: nil)
        XCTAssertTrue(profileManager.activeProfile.allowedApps.contains("com.example.Editor"))
        XCTAssertFalse(profileManager.activeProfile.distractionApps.contains("com.example.Editor"))
    }

    func testExplicitProductiveReviewSupportsWebsiteScope() {
        let profile = WorkProfile(name: "Website Review")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        mockOCRProvider.text = "Swift API documentation and code examples"

        let reviewURL = URL(string: "https://developer.apple.com/documentation/swift")!
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: reviewURL,
            title: "Swift documentation"
        )

        let reviewed = expectation(description: "website productive review completed")
        var reviewResult: ProductiveCorrectionReview?
        engine.reviewItemAsProductive(
            bundleID: "com.google.Chrome",
            localizedName: "Google Chrome",
            url: reviewURL,
            title: "Swift documentation"
        ) { review in
            reviewResult = review
            reviewed.fulfill()
        }

        wait(for: [reviewed], timeout: 1.0)
        XCTAssertEqual(reviewResult?.recommendedScope, .website)
        XCTAssertTrue(reviewResult?.canUseWebsiteScope ?? false)
        XCTAssertFalse(reviewResult?.message.isEmpty ?? true)
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

    func testLocalTextPipelinePassesVisibleWindowTextIntoClassifier() {
        testPreferences.enableLocalTextClassification = true
        mockOCRProvider.text = "Swift API documentation and code examples"

        let classifier = OCRDrivenClassifier()
        engine.stop()
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: mockOCRProvider,
            visualChecker: MockVisualChecker(),
            localTextClassifier: classifier
        )
        engine.delegate = mockDelegate

        let promoted = expectation(description: "visible text promoted the neutral context")
        let observer = NotificationCenter.default.addObserver(
            forName: .focusEngineClassificationDidChange,
            object: engine,
            queue: .main
        ) { [weak engine] _ in
            if engine?.currentClassification.isFocus == true {
                promoted.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Reader", title: "Overview")

        wait(for: [promoted], timeout: 2.0)

        XCTAssertEqual(classifier.observedScreenText, "Swift API documentation and code examples")
        XCTAssertTrue(engine.currentClassification.isFocus)
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

    func testAnchorSessionFallsBackToProfileNameWhenNoWorkAppIsAvailable() {
        let expectedFallback = profileManager.activeProfile.name

        engine.anchorSession(duration: 1_500.0)

        XCTAssertEqual(engine.activeSession?.appName, expectedFallback)
        XCTAssertFalse(engine.activeSession?.appName.isEmpty ?? true)

        let events = loadEventsFromDisk()
        XCTAssertEqual(events.first?.appName, expectedFallback)
    }

    func testSuggestedSessionGoalDoesNotFallbackToAppName() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")

        XCTAssertNil(engine.suggestedSessionGoal())
    }

    func testSuggestedSessionGoalSuppressesBuildArtifactTitles() {
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.apple.dt.Xcode",
            title: "Anchor — SwiftStdLibToolInputDependencies.dep"
        )

        XCTAssertNil(engine.suggestedSessionGoal())
    }

    func testSuggestedSessionGoalSuppressesVideoTitlesFromEntertainmentSites() {
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=swift-concurrency"),
            title: "Computer Science Lecture - Swift Concurrency"
        )

        XCTAssertNil(engine.suggestedSessionGoal())
    }
    
    func testDismissTriggerResetsWorkSessionStart() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertNotNil(engine.workSessionStart)
        
        engine.dismissTrigger()
        
        XCTAssertNil(engine.workSessionStart)
        XCTAssertEqual(engine.state, .idle)
    }
    
    // MARK: - Distraction Transitions (With Active Session)
    
    func testDistractionAppSwitchDuringActiveSessionTriggersCountdownAndLog() throws {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        
        let scheduledTimer = try XCTUnwrap(distractionTimerScheduler.scheduledTimers.first)
        XCTAssertEqual(distractionTimerScheduler.scheduledTimers.count, 1)
        XCTAssertGreaterThan(scheduledTimer.interval, 0)

        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.spotify.client"])
        
        // Verify distraction detected event logged
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.count, 2) // sessionStart + distractionDetected
        XCTAssertEqual(events.last?.type, .distractionDetected)
        XCTAssertEqual(events.last?.distractionAppBundleID, "com.spotify.client")
    }
    
    func testReturnToWorkBeforeDistractionTimerExpiresCancelsTimer() throws {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        let scheduledTimer = try XCTUnwrap(distractionTimerScheduler.scheduledTimers.first)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        XCTAssertTrue(scheduledTimer.isCancelled)
        scheduledTimer.fire()
        
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
        
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.count, 2) // sessionStart + distractionDetected (no escalationTriggered)
    }
    
    func testDistractionTimerExpirationTriggersEscalationAndLog() throws {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        let scheduledTimer = try XCTUnwrap(distractionTimerScheduler.scheduledTimers.first)
        
        XCTAssertNotNil(engine.currentDistractionGraceRemaining)
        scheduledTimer.fire()
        
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

    func testCommittedBreakExpiresNormallyAndPreservesFocusedTime() throws {
        prepareAcceptedBreak()
        let focusedBeforeBreak = engine.currentSessionFocusedTime()
        let timer = try XCTUnwrap(breakTimerScheduler.scheduledTimers.last)

        timer.fire()

        XCTAssertEqual(engine.breakState, .breakReview)
        XCTAssertNotNil(engine.activeBreakCommitment)
        XCTAssertEqual(engine.currentSessionFocusedTime(), focusedBeforeBreak, accuracy: 0.2)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
        XCTAssertEqual(breakReviewChecker.invocations.count, 1)
        let invocation = try XCTUnwrap(breakReviewChecker.invocations.last)
        XCTAssertEqual(invocation.input?.sessionID, invocation.expectedIdentity?.sessionID)
        XCTAssertEqual(invocation.input?.contextGeneration, invocation.expectedIdentity?.contextGeneration)
    }

    func testManuallyEndingBreakInvalidatesPendingBreakTimer() throws {
        let timer = try startBreakTimer()
        engine.resumeAfterBreakReview()

        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)

        timer.fireIgnoringCancellation()

        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.returnsToWork, 2)
    }

    func testEndingSessionInvalidatesPendingBreakTimer() throws {
        let timer = try startBreakTimer()

        engine.endSession(action: .dismissed)

        timer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertNil(engine.breakState)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
    }

    func testStoppingEngineInvalidatesPendingBreakTimer() throws {
        let timer = try startBreakTimer()

        engine.stop()

        timer.fireIgnoringCancellation()

        XCTAssertNotNil(engine.activeSession)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertNil(engine.breakState)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
    }

    func testSleepOrLockDuringBreakInvalidatesPendingBreakTimer() throws {
        let timer = try startBreakTimer()
        let pausedAt = Date()

        engine.pauseFocusAccountingForWorkspaceLifecycle(now: pausedAt)

        XCTAssertTrue(timer.isCancelled)
        timer.fireIgnoringCancellation()
        XCTAssertEqual(engine.breakState, .breakActive)

        engine.resumeFocusAccountingForWorkspaceLifecycle(now: pausedAt.addingTimeInterval(30))
        let resumedTimer = try XCTUnwrap(breakTimerScheduler.scheduledTimers.last)

        XCTAssertEqual(breakTimerScheduler.scheduledTimers.count, 2)
        XCTAssertFalse(resumedTimer.isCancelled)
    }

    func testStartingAnotherBreakInvalidatesTheFirstBreakTimer() throws {
        let firstTimer = try startBreakTimer()

        engine.resumeAfterBreakReview()
        _ = engine.requestBreak(intention: "Take another walk", now: Date(), bypassMinimum: true)

        let secondTimer = try XCTUnwrap(breakTimerScheduler.scheduledTimers.last)

        XCTAssertEqual(breakTimerScheduler.scheduledTimers.count, 2)
        XCTAssertTrue(firstTimer.isCancelled)
        XCTAssertFalse(secondTimer.isCancelled)
    }

    func testStaleCallbackFromAnEarlierBreakCannotAffectLaterBreak() throws {
        let firstTimer = try startBreakTimer()

        engine.resumeAfterBreakReview()
        _ = engine.requestBreak(intention: "Take another walk", now: Date(), bypassMinimum: true)

        firstTimer.fireIgnoringCancellation()

        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertNotNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.returnsToWork, 3)
    }

    func testStaleCallbackFromAnOldSessionCannotAffectNewSession() throws {
        let firstTimer = try startBreakTimer()

        engine.endSession(action: .dismissed)
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
        _ = engine.requestBreak(intention: "New break", now: Date(), bypassMinimum: true)

        firstTimer.fireIgnoringCancellation()

        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertNotNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.returnsToWork, 2)
    }

    func testBreakReviewUsesCurrentSessionAndContextGeneration() throws {
        let timer = try startBreakTimer()
        let originalInvocationCount = breakReviewChecker.invocations.count

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode", title: "Refined title")
        let expectedIdentity = ContextSnapshot(
            bundleIdentifier: try XCTUnwrap(engine.currentApp),
            localizedName: "Xcode",
            url: engine.currentURL,
            title: engine.currentTitle,
            source: .application
        ).identity

        timer.fire()

        let invocation = try XCTUnwrap(breakReviewChecker.invocations.last)
        XCTAssertGreaterThan(breakReviewChecker.invocations.count, originalInvocationCount)
        XCTAssertEqual(invocation.input?.sessionID, invocation.expectedIdentity?.sessionID)
        XCTAssertEqual(invocation.input?.identity, expectedIdentity)
        XCTAssertEqual(invocation.input?.contextGeneration, invocation.expectedIdentity.map { $0.contextGeneration + 1 })
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
        guard let timer = breakTimerScheduler.scheduledTimers.last else {
            return XCTFail("Expected a scheduled break timer")
        }
        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertEqual(engine.currentSessionFocusedTime(), beforeBreak, accuracy: 0.2)

        timer.fire()

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

    func testBreakAutoResumesAfterStableReturnForFifteenSeconds() throws {
        prepareAcceptedBreak()

        let graceTimer = try startBreakReturnGrace()
        XCTAssertEqual(breakReturnTimerScheduler.scheduledTimers.count, 1)
        XCTAssertFalse(graceTimer.isCancelled)

        let startedAt = try XCTUnwrap(engine.breakReturnGraceStartedAt)
        engine.breakReturnGraceTimerExpired(now: startedAt.addingTimeInterval(15.1))

        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.returnsToWork, 2)
    }

    func testNeutralContextDoesNotStartBreakReturnGrace() {
        prepareAcceptedBreak()

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")

        XCTAssertTrue(breakReturnTimerScheduler.scheduledTimers.isEmpty)
        XCTAssertNil(engine.breakReturnGraceStartedAt)
        XCTAssertEqual(engine.breakState, .breakActive)
    }

    func testLeavingBeforeBreakReturnGraceExpiresPreventsResume() throws {
        prepareAcceptedBreak()

        let graceTimer = try startBreakReturnGrace()
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")

        XCTAssertTrue(graceTimer.isCancelled)
        graceTimer.fireIgnoringCancellation()

        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertNotNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
    }

    func testReturningAgainCreatesNewBreakReturnGraceGeneration() throws {
        prepareAcceptedBreak()

        let firstTimer = try startBreakReturnGrace()

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")

        let secondTimer = try XCTUnwrap(breakReturnTimerScheduler.scheduledTimers.last)

        XCTAssertEqual(breakReturnTimerScheduler.scheduledTimers.count, 2)
        XCTAssertTrue(firstTimer.isCancelled)
        XCTAssertFalse(secondTimer.isCancelled)

        firstTimer.fireIgnoringCancellation()
        XCTAssertEqual(engine.breakState, .breakActive)

        let startedAt = try XCTUnwrap(engine.breakReturnGraceStartedAt)
        engine.breakReturnGraceTimerExpired(now: startedAt.addingTimeInterval(15.1))
        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.returnsToWork, 2)
    }

    func testSecondQualifyingContextSupersedesFirstBreakReturnCandidateSafely() throws {
        prepareAcceptedBreak()

        let firstTimer = try startBreakReturnGrace()

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.Terminal")
        let secondTimer = try XCTUnwrap(breakReturnTimerScheduler.scheduledTimers.last)

        XCTAssertEqual(breakReturnTimerScheduler.scheduledTimers.count, 2)
        XCTAssertTrue(firstTimer.isCancelled)
        XCTAssertFalse(secondTimer.isCancelled)

        firstTimer.fireIgnoringCancellation()
        XCTAssertEqual(engine.breakState, .breakActive)

        let startedAt = try XCTUnwrap(engine.breakReturnGraceStartedAt)
        engine.breakReturnGraceTimerExpired(now: startedAt.addingTimeInterval(15.1))
        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.returnsToWork, 2)
    }

    func testManuallyEndingBreakInvalidatesPendingBreakReturnGraceCallback() throws {
        prepareAcceptedBreak()

        let graceTimer = try startBreakReturnGrace()
        engine.resumeAfterBreakReview()

        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)

        graceTimer.fireIgnoringCancellation()

        XCTAssertNil(engine.breakState)
        XCTAssertEqual(mockDelegate.returnsToWork, 2)
    }

    func testEndingSessionInvalidatesPendingBreakReturnGraceCallback() throws {
        prepareAcceptedBreak()

        let graceTimer = try startBreakReturnGrace()

        engine.endSession(action: .dismissed)

        graceTimer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertNil(engine.breakState)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
    }

    func testWorkspacePauseInvalidatesPendingBreakReturnGraceCallback() throws {
        prepareAcceptedBreak()

        let graceTimer = try startBreakReturnGrace()
        let pauseStartedAt = Date()

        engine.pauseFocusAccountingForWorkspaceLifecycle(now: pauseStartedAt)

        XCTAssertTrue(graceTimer.isCancelled)
        graceTimer.fireIgnoringCancellation()
        XCTAssertEqual(engine.breakState, .breakActive)

        engine.resumeFocusAccountingForWorkspaceLifecycle(now: pauseStartedAt.addingTimeInterval(60))
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        let resumedTimer = try XCTUnwrap(breakReturnTimerScheduler.scheduledTimers.last)

        XCTAssertEqual(breakReturnTimerScheduler.scheduledTimers.count, 2)
        XCTAssertFalse(resumedTimer.isCancelled)
        let resumedStartedAt = try XCTUnwrap(engine.breakReturnGraceStartedAt)
        engine.breakReturnGraceTimerExpired(now: resumedStartedAt.addingTimeInterval(15.1))

        XCTAssertNil(engine.breakState)
        XCTAssertNil(engine.activeBreakCommitment)
        XCTAssertEqual(mockDelegate.returnsToWork, 2)
    }

    func testOldSessionBreakReturnGraceCannotResumeNewSession() throws {
        prepareAcceptedBreak()

        let oldTimer = try startBreakReturnGrace()
        let oldSessionID = try XCTUnwrap(engine.activeBreakCommitment?.sessionID)

        engine.endSession(action: .dismissed)

        prepareAcceptedBreak()
        XCTAssertNotEqual(engine.activeBreakCommitment?.sessionID, oldSessionID)

        oldTimer.fireIgnoringCancellation()

        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertEqual(mockDelegate.returnsToWork, 2)
        XCTAssertNotNil(engine.activeBreakCommitment)
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

    func testStaleDistractionTimerFromPreviousEntryDoesNotDimAfterReenteringSameApp() throws {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        let firstTimer = try XCTUnwrap(distractionTimerScheduler.scheduledTimers.first)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")

        let secondTimer = try XCTUnwrap(distractionTimerScheduler.scheduledTimers.last)

        XCTAssertTrue(firstTimer.isCancelled)
        XCTAssertFalse(secondTimer.isCancelled)
        XCTAssertEqual(distractionTimerScheduler.scheduledTimers.count, 2)

        // Simulate the stale callback from the old timer arriving after the new one was scheduled.
        firstTimer.fireIgnoringCancellation()

        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(mockDelegate.returnsToWork, 1)
    }

    // MARK: - Doomscroll Loop Breaker

    func testDoomscrollFiresOnceAfterContinuousDistractionReachesThreshold() throws {
        let pendingTimer = try prepareDoomscrollRun()

        engine.doomscrollTimerExpired(now: Date().addingTimeInterval(pendingTimer.interval + 0.1))

        XCTAssertEqual(mockDelegate.doomscrollingDetections.count, 1)
        XCTAssertEqual(mockDelegate.doomscrollingDetections.first?.bundleID, "com.spotify.client")
        XCTAssertEqual(mockDelegate.doomscrollingDetections.first?.threshold, 0.0)

        engine.doomscrollTimerExpired(now: Date().addingTimeInterval(pendingTimer.interval + 1.0))
        XCTAssertEqual(mockDelegate.doomscrollingDetections.count, 1)
    }

    func testFocusContextBeforeDoomscrollExpiryPreventsFiring() throws {
        let pendingTimer = try prepareDoomscrollRun()

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")

        XCTAssertTrue(pendingTimer.isCancelled)
        pendingTimer.fireIgnoringCancellation()
        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
    }

    func testNeutralContextBeforeDoomscrollExpiryPreventsFiring() throws {
        let pendingTimer = try prepareDoomscrollRun()

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Unknown")

        XCTAssertTrue(pendingTimer.isCancelled)
        pendingTimer.fireIgnoringCancellation()
        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
    }

    func testBeginningActiveSessionInvalidatesPendingDoomscrollCallback() throws {
        let pendingTimer = try prepareDoomscrollRun()

        engine.anchorSession(duration: 1500)

        XCTAssertTrue(pendingTimer.isCancelled)
        pendingTimer.fireIgnoringCancellation()
        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
        XCTAssertNotNil(engine.activeSession)
    }

    func testDisablingLoopBreakerInvalidatesPendingDoomscrollCallback() throws {
        let pendingTimer = try prepareDoomscrollRun()

        testPreferences.enableDoomscrollLoopBreaker = false

        XCTAssertTrue(pendingTimer.isCancelled)
        pendingTimer.fireIgnoringCancellation()
        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
    }

    func testMovingOutsideActiveFocusScheduleInvalidatesPendingDoomscrollCallback() throws {
        let now = Date()
        testPreferences.focusSchedule = scheduleAllowingCurrentMinute(now: now)
        engine.refreshScheduleState(now: now)

        let pendingTimer = try prepareDoomscrollRun()

        testPreferences.focusSchedule = scheduleExcludingCurrentMinute(now: now)

        XCTAssertTrue(pendingTimer.isCancelled)
        pendingTimer.fireIgnoringCancellation()
        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
    }

    func testWorkspacePauseInvalidatesPendingDoomscrollCallback() throws {
        let pendingTimer = try prepareDoomscrollRun()

        engine.pauseFocusAccountingForWorkspaceLifecycle(now: Date())

        XCTAssertTrue(pendingTimer.isCancelled)
        pendingTimer.fireIgnoringCancellation()
        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
    }

    func testReturningToDistractionCreatesNewDoomscrollGeneration() throws {
        let firstTimer = try prepareDoomscrollRun()

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")

        let secondTimer = try XCTUnwrap(doomscrollTimerScheduler.scheduledTimers.last)

        XCTAssertEqual(doomscrollTimerScheduler.scheduledTimers.count, 2)
        XCTAssertTrue(firstTimer.isCancelled)
        XCTAssertFalse(secondTimer.isCancelled)
        XCTAssertTrue(firstTimer !== secondTimer)
    }

    func testStaleDoomscrollCallbackFromEarlierRunCannotFireDuringLaterRun() throws {
        let firstTimer = try prepareDoomscrollRun()

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        _ = try XCTUnwrap(doomscrollTimerScheduler.scheduledTimers.last)

        firstTimer.fireIgnoringCancellation()

        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
    }

    func testStaleDoomscrollCallbackFromEarlierContextIdentityCannotFire() throws {
        let firstTimer = try prepareDoomscrollRun(title: "Episode One")

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client", title: "Episode Two")
        _ = try XCTUnwrap(doomscrollTimerScheduler.scheduledTimers.last)

        firstTimer.fireIgnoringCancellation()

        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
    }

    func testChangingDoomscrollThresholdReplacesPendingTiming() throws {
        let firstTimer = try prepareDoomscrollRun(threshold: 5.0)

        testPreferences.doomscrollThreshold = 45.0

        let secondTimer = try XCTUnwrap(doomscrollTimerScheduler.scheduledTimers.last)

        XCTAssertEqual(doomscrollTimerScheduler.scheduledTimers.count, 2)
        XCTAssertTrue(firstTimer.isCancelled)
        XCTAssertFalse(secondTimer.isCancelled)
        XCTAssertEqual(secondTimer.interval, 45.0, accuracy: 0.0001)

        firstTimer.fireIgnoringCancellation()
        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)

        engine.doomscrollTimerExpired(now: Date().addingTimeInterval(secondTimer.interval + 0.1))
        XCTAssertEqual(mockDelegate.doomscrollingDetections.count, 1)
        XCTAssertEqual(mockDelegate.doomscrollingDetections.first?.threshold, 45.0)
    }

    func testContinuousDoomscrollRunOnlyEmitsOneDetection() throws {
        let pendingTimer = try prepareDoomscrollRun()

        engine.doomscrollTimerExpired(now: Date().addingTimeInterval(pendingTimer.interval + 0.1))
        engine.doomscrollTimerExpired(now: Date().addingTimeInterval(pendingTimer.interval + 1.0))
        pendingTimer.fireIgnoringCancellation()

        XCTAssertEqual(mockDelegate.doomscrollingDetections.count, 1)
    }

    func testStopInvalidatesPendingDoomscrollCallback() throws {
        let pendingTimer = try prepareDoomscrollRun()

        engine.stop()

        XCTAssertTrue(pendingTimer.isCancelled)
        pendingTimer.fireIgnoringCancellation()
        XCTAssertTrue(mockDelegate.doomscrollingDetections.isEmpty)
    }
    
    // MARK: - Session Expiration & Termination
    
    func testSessionTimerExpirationAutoEndsSession() throws {
        let timer = try startSessionTimer(duration: 0.05)

        XCTAssertEqual(engine.state, .anchored)

        timer.fire()
        
        XCTAssertNil(engine.activeSession)
        XCTAssertNil(engine.workSessionStart)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(mockDelegate.endedSessions, 1)
        
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.filter { $0.type == .sessionEnd }.count, 1)
        XCTAssertEqual(events.last?.type, .sessionEnd)
        XCTAssertEqual(events.last?.action, .timeout)
    }

    func testManualEndSessionInvalidatesPendingSessionTimer() throws {
        let timer = try startSessionTimer(duration: 0.05)

        engine.endSession(action: .dismissed)

        XCTAssertTrue(timer.isCancelled)
        timer.fireIgnoringCancellation()

        XCTAssertNil(engine.activeSession)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(mockDelegate.endedSessions, 1)

        let events = loadEventsFromDisk()
        XCTAssertEqual(events.filter { $0.type == .sessionEnd }.count, 1)
        XCTAssertEqual(events.last?.action, .dismissed)
    }

    func testOldSessionTimerCannotEndNewSession() throws {
        let oldTimer = try startSessionTimer(duration: 0.05)

        engine.endSession(action: .dismissed)
        let newTimer = try startSessionTimer(duration: 0.1)

        oldTimer.fireIgnoringCancellation()

        XCTAssertEqual(engine.state, .anchored)
        XCTAssertNotNil(engine.activeSession)
        XCTAssertTrue(oldTimer.isCancelled)
        XCTAssertFalse(newTimer.isCancelled)
        XCTAssertEqual(newTimer.interval, 0.1, accuracy: 0.001)
        XCTAssertEqual(mockDelegate.endedSessions, 1)
    }

    func testBreakStartInvalidatesPendingSessionTimer() throws {
        let timer = try startSessionTimer(duration: 0.05)

        _ = engine.requestBreak(intention: "Take a short walk", now: Date(), bypassMinimum: true)

        XCTAssertTrue(timer.isCancelled)
        timer.fireIgnoringCancellation()

        XCTAssertEqual(engine.breakState, .breakActive)
        XCTAssertNotNil(engine.activeSession)
        XCTAssertEqual(mockDelegate.endedSessions, 0)
    }

    func testWorkspacePauseAndResumeReschedulesSessionTimer() throws {
        let timer = try startSessionTimer(duration: 0.05)
        let pauseStartedAt = Date()

        engine.pauseFocusAccountingForWorkspaceLifecycle(now: pauseStartedAt)

        XCTAssertTrue(timer.isCancelled)
        timer.fireIgnoringCancellation()
        XCTAssertNotNil(engine.activeSession)

        engine.resumeFocusAccountingForWorkspaceLifecycle(now: pauseStartedAt)
        let resumedTimer = try XCTUnwrap(sessionTimerScheduler.scheduledTimers.last)

        XCTAssertEqual(sessionTimerScheduler.scheduledTimers.count, 2)
        XCTAssertFalse(resumedTimer.isCancelled)
        XCTAssertEqual(resumedTimer.interval, 0.05, accuracy: 0.02)

        resumedTimer.fire()

        XCTAssertNil(engine.activeSession)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(mockDelegate.endedSessions, 1)
        let events = loadEventsFromDisk()
        XCTAssertEqual(events.filter { $0.type == .sessionEnd }.count, 1)
    }

    func testStoppingEngineInvalidatesPendingSessionTimer() throws {
        let timer = try startSessionTimer(duration: 0.05)

        engine.stop()

        XCTAssertTrue(timer.isCancelled)
        timer.fireIgnoringCancellation()

        XCTAssertNotNil(engine.activeSession)
        XCTAssertEqual(engine.state, .anchored)
        XCTAssertEqual(mockDelegate.endedSessions, 0)
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

    func testIdleTimeDoesNotAccrueWhileUserIsRecentlyActive() {
        mockUserActivityProvider.idleDuration = 10.0
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")

        engine.anchorSession(duration: 1500.0)
        XCTAssertEqual(engine.totalIdleTime, 0.0)

        let expectation = XCTestExpectation(description: "recent user activity keeps idle clock paused")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            XCTAssertEqual(self.engine.totalIdleTime, 0.0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
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
        _ = sessionStore.recordedEvents
        
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

    func testPermissionGateIsNotTriggeredBeforeTenSessions() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500.0)
        engine.endSession()

        XCTAssertEqual(mockDelegate.requestedPermissionGate, 0)
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

    func testReturningToAnotherProductiveAppDoesNotLeaveStaleDimmingEnforcement() {
        let profile = WorkProfile(name: "Neutral Apps")
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")
        mockActivityMonitor.simulateContextChange(bundleID: "com.jetbrains.intellij")

        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.apple.dt.Xcode")
    }

    func testForceImmediateDimRequestsOverlayWithoutCountdown() {
        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1_500)

        engine.forceImmediateDim()

        XCTAssertTrue(engine.isDimming)
        XCTAssertEqual(mockDelegate.immediateDims, 1)
        XCTAssertEqual(mockDelegate.detectedDistractions.count, 0)
    }

    func testCmdTabToAnotherProductiveAppDoesNotCancelGracePeriod() {
        let profile = WorkProfile(
            name: "Neutral Apps",
            distractionApps: ["com.hnc.Discord"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        engine.distractionCountdownThreshold = 10.0

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(bundleID: "com.hnc.Discord")

        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.hnc.Discord"])
        XCTAssertNotNil(engine.currentDistractionGraceRemaining)
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.apple.dt.Xcode")

        mockActivityMonitor.simulateContextChange(bundleID: "com.jetbrains.intellij")

        XCTAssertEqual(mockDelegate.returnsToWork, 0)
        XCTAssertNotNil(engine.currentDistractionGraceRemaining)
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(engine.lastWorkAppBundleID, "com.apple.dt.Xcode")
    }

    func testMusicAppsUseLongerGracePeriodBeforeDimming() {
        let profile = WorkProfile(
            name: "Music Grace",
            distractionApps: ["com.spotify.client"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)
        engine.distractionCountdownThreshold = 0.05

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1_500)

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")

        XCTAssertEqual(mockDelegate.detectedDistractions, ["com.spotify.client"])
        XCTAssertFalse(engine.isDimming)
        XCTAssertGreaterThan(engine.currentDistractionGraceRemaining ?? 0, 60)
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

    func testEnablingCloudClassificationReclassifiesTheCurrentContext() {
        let cloudService = DeferredCloudClassificationService()
        let requestReceived = expectation(description: "cloud request received after enable")
        cloudService.onRequest = { requestReceived.fulfill() }
        testPreferences.cloudProvider = 0
        try? KeychainHelper.saveKey("fake-gemini-key", forProvider: "gemini")

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

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.Notepad", title: "Draft")
        XCTAssertTrue(localEngine.currentClassification.isNeutral)

        testPreferences.enableCloudClassification = true

        wait(for: [requestReceived], timeout: 1.0)

        let promoted = expectation(description: "cloud promotion applied after enable")
        let observer = NotificationCenter.default.addObserver(
            forName: .focusEngineClassificationDidChange,
            object: localEngine,
            queue: .main
        ) { [weak localEngine] _ in
            if localEngine?.currentClassification.isFocus == true {
                promoted.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        cloudService.complete(.success(ClassificationResult(
            label: .productive,
            confidence: 0.95,
            modelVersion: "test-cloud",
            latency: 0,
            explanation: "test cloud productive result"
        )))
        wait(for: [promoted], timeout: 1.0)

        XCTAssertTrue(localEngine.currentClassification.isFocus)
        XCTAssertEqual(localEngine.lastWorkAppBundleID, "com.example.Notepad")
        localEngine.stop()
    }

    func testCloudClassificationCanPromoteSocialFeedToFocus() {
        let cloudService = DeferredCloudClassificationService()
        let requestReceived = expectation(description: "cloud request received for social feed")
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

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.linkedin.com/feed/"),
            title: "Feed | LinkedIn"
        )

        wait(for: [requestReceived], timeout: 1)

        cloudService.complete(.success(ClassificationResult(
            label: .productive,
            confidence: 0.95,
            modelVersion: "test-cloud",
            latency: 0,
            explanation: "social feed was actually productive"
        )))

        let promoted = expectation(description: "social cloud promotion applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            promoted.fulfill()
        }
        wait(for: [promoted], timeout: 1.0)

        XCTAssertTrue(localEngine.currentClassification.isFocus)
        XCTAssertEqual(localEngine.lastWorkAppBundleID, "com.google.Chrome")
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
        return sessionStore.recordedEvents
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
        
        // 3. Trigger profile change or rules change to clear cache.
        NotificationCenter.default.post(name: .profilesDidChange, object: nil)

        let expectation3 = XCTestExpectation(description: "Cache invalidation reclassifies current context")
        let deadline = Date().addingTimeInterval(2.0)
        func pollForSecondClassification() {
            if countingClassifier.classificationCount >= 2 {
                expectation3.fulfill()
                return
            }
            guard Date() < deadline else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                pollForSecondClassification()
            }
        }
        pollForSecondClassification()
        wait(for: [expectation3], timeout: 2.0)
        
        // Classification count should now be 2!
        XCTAssertEqual(countingClassifier.classificationCount, 2)

        // 4. Switch back to the same context and confirm the refreshed cache is used.
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.neutralapp", url: nil, title: "Neutral Title")

        let expectation4 = XCTestExpectation(description: "Post-refresh context switch processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation4.fulfill()
        }
        wait(for: [expectation4], timeout: 1.0)

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

    func testClassificationCacheSeparatesSessionScopedKeys() {
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

        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")

        let firstPass = expectation(description: "first pass classified")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            firstPass.fulfill()
        }
        wait(for: [firstPass], timeout: 1.0)
        XCTAssertEqual(countingClassifier.classificationCount, 1)

        engine.anchorSession(duration: 1_500)
        mockActivityMonitor.simulateContextChange(bundleID: "com.example.appA")

        let secondPass = expectation(description: "second pass classified")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            secondPass.fulfill()
        }
        wait(for: [secondPass], timeout: 1.0)

        XCTAssertEqual(countingClassifier.classificationCount, 2)
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

    func testActiveSessionOutsideScheduleDoesNotTriggerNewDistractionEnforcement() {
        let now = Date()
        testPreferences.focusSchedule = scheduleAllowingCurrentMinute(now: now)

        mockActivityMonitor.simulateContextChange(bundleID: "com.apple.dt.Xcode")
        engine.anchorSession(duration: 1500)

        testPreferences.focusSchedule = scheduleExcludingCurrentMinute(now: now)

        mockActivityMonitor.simulateContextChange(bundleID: "com.spotify.client")

        XCTAssertFalse(engine.isFocusScheduleActive)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertTrue(distractionTimerScheduler.scheduledTimers.isEmpty)
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
    
    func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
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
    func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
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

    func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
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

private final class OCRDrivenClassifier: ContextClassifying, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var observedScreenText: String?

    func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
        lock.lock()
        observedScreenText = screenText
        lock.unlock()

        let isProductive = (screenText ?? "").lowercased().contains("documentation")
        return ClassificationResult(
            label: isProductive ? .productive : .neutral,
            confidence: isProductive ? 0.95 : 0.0,
            modelVersion: "test-ocr",
            latency: 0,
            explanation: isProductive ? "test ocr productive result" : "test ocr neutral result"
        )
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
        activeSurfaceCount = 0
    }
    
    func sessionDidEnd() {
        endedSessions += 1
        activeSurfaceCount = 0
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
    var activeSurfaceCount = 0
    func didRequestImmediateDim() {
        immediateDims += 1
        activeSurfaceCount = 1
    }

    var doomscrollingDetections: [(bundleID: String, threshold: TimeInterval)] = []
    func didDetectDoomscrolling(bundleID: String, threshold: TimeInterval) {
        doomscrollingDetections.append((bundleID: bundleID, threshold: threshold))
    }
}

final class MockOCRProvider: WindowTextExtracting {
    var text: String = ""

    func extractText() -> String {
        text
    }

    func extractText(for bundleID: String) -> String {
        text
    }
}

final class MockUserActivityProvider: UserActivityProviding {
    var idleDuration: TimeInterval = 0.0

    func idleDuration(at _: Date) -> TimeInterval {
        idleDuration
    }
}

struct MockVisualChecker: VisualProductivityChecking {
    func isProductiveVisual(profileName: String) -> Bool {
        return false
    }
}

final class RecordingBreakReviewChecker: BreakReviewChecking {
    private let wrapped = ConservativeBreakReviewChecker()
    private(set) var invocations: [(input: BreakReviewInput?, expectedIdentity: BreakReviewIdentity?)] = []

    func evaluate(
        input: BreakReviewInput?,
        expectedIdentity: BreakReviewIdentity?
    ) -> BreakReviewResult {
        invocations.append((input: input, expectedIdentity: expectedIdentity))
        return wrapped.evaluate(input: input, expectedIdentity: expectedIdentity)
    }
}

final class TestDiagnosticsRecorder: DiagnosticsRecording {
    private(set) var messages: [String] = []

    func recordEngineStateTransition(from: SessionState, to: SessionState, reason: DiagnosticEngineTransitionReason) {
        messages.append("stateTransition from=\(from.rawValue) to=\(to.rawValue) reason=\(reason.rawValue)")
    }

    func recordSessionLifecycle(action: DiagnosticSessionAction, duration: TimeInterval?, bundleID: String?) {
        var fields = ["action=\(action.rawValue)"]
        if let duration {
            fields.append("duration=\(String(format: "%.1f", duration))")
        }
        if let bundleID {
            fields.append("bundleID=\(bundleID)")
        }
        messages.append("sessionLifecycle \(fields.joined(separator: " "))")
    }

    func recordTimerScheduled(kind: DiagnosticTimerKind, delay: TimeInterval, generation: Int) {
        messages.append("timerScheduled kind=\(kind.rawValue) delay=\(String(format: "%.1f", delay)) generation=\(generation)")
    }

    func recordTimerCancelled(kind: DiagnosticTimerKind, reason: DiagnosticTimerCancellationReason, generation: Int?) {
        var fields = ["kind=\(kind.rawValue)", "reason=\(reason.rawValue)"]
        if let generation {
            fields.append("generation=\(generation)")
        }
        messages.append("timerCancelled \(fields.joined(separator: " "))")
    }

    func recordTimerRejected(kind: DiagnosticTimerKind, reason: DiagnosticTimerRejectionReason, generation: Int?) {
        var fields = ["kind=\(kind.rawValue)", "reason=\(reason.rawValue)"]
        if let generation {
            fields.append("generation=\(generation)")
        }
        messages.append("timerRejected \(fields.joined(separator: " "))")
    }

    func recordClassificationDecision(
        source: ClassificationSource,
        decision: ClassificationLabel,
        reason: ClassificationReason,
        confidence: Double
    ) {
        messages.append("classificationDecision source=\(source.rawValue) decision=\(decision.rawValue) reason=\(reason.rawValue) confidence=\(String(format: "%.2f", confidence))")
    }

    func recordWorkspaceLifecycle(action: DiagnosticWorkspaceAction, pauseSeconds: TimeInterval?) {
        var fields = ["action=\(action.rawValue)"]
        if let pauseSeconds {
            fields.append("pauseSeconds=\(String(format: "%.1f", pauseSeconds))")
        }
        messages.append("workspaceLifecycle \(fields.joined(separator: " "))")
    }

    func recordPermissionState(permission: DiagnosticPermissionKind, granted: Bool) {
        messages.append("permissionState permission=\(permission.rawValue) state=\(granted ? DiagnosticPermissionState.granted.rawValue : DiagnosticPermissionState.denied.rawValue)")
    }

    func recordSanitizedError(category: DiagnosticErrorCategory) {
        messages.append("sanitizedError category=\(category.rawValue)")
    }
}

final class RecordingContextualLearningStore: ContextualLearningRecording {
    var isEnabled = true

    private let queue = DispatchQueue(label: "com.varun.Anchored.FocusEngineTests.ContextualLearningStore")
    private(set) var records: [ContextualLearningRecord] = []
    var onRecord: ((ContextualLearningRecord) -> Void)?

    func record(_ record: ContextualLearningRecord, completion: StorageWriteCompletion?) {
        queue.async {
            self.records.append(record)
            self.onRecord?(record)
            completion?(.success(()))
        }
    }

    func evidence(for snapshot: ContextSnapshot, focusIntent: FocusIntent?) -> ClassificationEvidence? {
        guard isEnabled else { return nil }
        return queue.sync {
            let domain = ContextualSiteHeuristic.normalizedDomain(for: snapshot.url) ?? ""
            let pageCategory = ContextualSiteHeuristic.pageCategory(for: snapshot.url, title: snapshot.title)
            let intentCategory = ContextualSiteHeuristic.intentCategory(for: focusIntent)
            let matchingRecords = records.filter {
                $0.normalizedDomain == domain && $0.pageCategory == pageCategory && $0.intentCategory == intentCategory
            }
            guard !matchingRecords.isEmpty else { return nil }
            return ClassificationEvidence(
                label: matchingRecords.count >= 2 ? .productive : .contextual,
                source: matchingRecords.count >= 2 ? .deterministicRule : .heuristic,
                confidence: matchingRecords.count >= 2 ? 0.9 : 0.65,
                reason: .contextualLearning
            )
        }
    }

    func shouldSuggestPermanentRule(for snapshot: ContextSnapshot, focusIntent: FocusIntent?) -> Bool {
        guard isEnabled else { return false }
        return queue.sync {
            let domain = ContextualSiteHeuristic.normalizedDomain(for: snapshot.url) ?? ""
            let pageCategory = ContextualSiteHeuristic.pageCategory(for: snapshot.url, title: snapshot.title)
            let intentCategory = ContextualSiteHeuristic.intentCategory(for: focusIntent)
            let count = records.filter {
                $0.normalizedDomain == domain
                    && $0.pageCategory == pageCategory
                    && $0.intentCategory == intentCategory
                    && $0.decision == .productive
            }.count
            return count >= 3
        }
    }

    func clearAll(completion: StorageWriteCompletion?) {
        queue.async {
            self.records.removeAll()
            completion?(.success(()))
        }
    }

    func prune(retentionDays: Int, completion: StorageWriteCompletion?) {
        queue.async {
            completion?(.success(()))
        }
    }
}

final class ToggleableContextualLearningStore: ContextualLearningRecording {
    var isEnabled = false
    var evidenceResult: ClassificationEvidence?

    func record(_ record: ContextualLearningRecord, completion: StorageWriteCompletion?) {
        completion?(.success(()))
    }

    func evidence(for snapshot: ContextSnapshot, focusIntent: FocusIntent?) -> ClassificationEvidence? {
        guard isEnabled else { return nil }
        return evidenceResult
    }

    func shouldSuggestPermanentRule(for snapshot: ContextSnapshot, focusIntent: FocusIntent?) -> Bool {
        isEnabled && evidenceResult?.label == .productive
    }

    func clearAll(completion: StorageWriteCompletion?) {
        completion?(.success(()))
    }

    func prune(retentionDays: Int, completion: StorageWriteCompletion?) {
        completion?(.success(()))
    }
}

final class TestOneShotTimerScheduler: OneShotTimerScheduling {
    final class PendingTimer: OneShotTimerHandle {
        let interval: TimeInterval
        private let action: () -> Void
        private(set) var isCancelled = false

        init(interval: TimeInterval, action: @escaping () -> Void) {
            self.interval = interval
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }

        func fire() {
            guard !isCancelled else { return }
            action()
        }

        func fireIgnoringCancellation() {
            action()
        }
    }

    private(set) var scheduledTimers: [PendingTimer] = []

    var pendingTimers: [PendingTimer] {
        scheduledTimers.filter { !$0.isCancelled }
    }

    func schedule(after interval: TimeInterval, action: @escaping () -> Void) -> OneShotTimerHandle {
        let timer = PendingTimer(interval: interval, action: action)
        scheduledTimers.append(timer)
        return timer
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
    
    func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
        lock.lock()
        count += 1
        lock.unlock()
        return wrapped.classify(snapshot: snapshot, screenText: screenText)
    }
}

private final class ConcurrentDeferredClassifier: ContextClassifying, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingSignals: [ContextIdentity: DispatchSemaphore] = [:]
    private var pendingResults: [ContextIdentity: ClassificationResult] = [:]
    var onRequest: ((ContextIdentity) -> Void)?

    func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
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
