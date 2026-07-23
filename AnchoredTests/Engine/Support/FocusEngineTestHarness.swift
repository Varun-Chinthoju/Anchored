import XCTest
@testable import Anchored

enum FocusEngineHarnessTimerKind {
    case sessionExpiry
    case distractionCountdown
    case breakDuration
    case breakReturnGrace
    case doomscroll
    case focusPrompt
}

final class FocusEngineTestHarness {
    let activityMonitor = MockActivityMonitor()
    let distractionListManager: DistractionListManager
    let profileManager: ProfileManager
    let preferences: PreferencesManager
    let overlayDelegate = MockFocusEngineDelegate()
    let ocrProvider = MockOCRProvider()
    let breakReviewChecker = RecordingBreakReviewChecker()
    let diagnosticsRecorder = TestDiagnosticsRecorder()
    let contextualLearningStore = RecordingContextualLearningStore()
    let cloudClassificationService = QueuedCloudClassificationService()
    let sessionTimerScheduler = TestOneShotTimerScheduler()
    let distractionTimerScheduler = TestOneShotTimerScheduler()
    let breakTimerScheduler = TestOneShotTimerScheduler()
    let breakReturnGraceTimerScheduler = TestOneShotTimerScheduler()
    let doomscrollTimerScheduler = TestOneShotTimerScheduler()
    let focusPromptTimerScheduler = TestOneShotTimerScheduler()

    private let suiteName: String
    private let testDefaults: UserDefaults
    private let tempStoreURL: URL
    private var cachedSessionStore: SessionStore?
    private var cachedEngine: FocusEngine?
    private var disposed = false

    init(
        focusThreshold: TimeInterval = 600.0,
        enableCloudClassification: Bool = false,
        cloudProvider: Int = PreferencesManager.defaultCloudProvider
    ) {
        suiteName = "com.varun.Anchored.FocusEngineTestHarness.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        KeychainHelper.clearCachedKeys()
        distractionListManager = DistractionListManager(defaults: testDefaults)
        profileManager = ProfileManager(defaults: testDefaults)
        preferences = PreferencesManager(defaults: testDefaults)
        preferences.enableDoomscrollLoopBreaker = false
        preferences.enableLocalTextClassification = false
        preferences.enableCloudClassification = enableCloudClassification
        preferences.cloudProvider = cloudProvider
        preferences.enableImageClassification = false
        preferences.interactionSummaryEnabled = false

        tempStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        cachedSessionStore = SessionStore(fileURL: tempStoreURL)

        let engine = FocusEngine(
            activityMonitor: activityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: focusThreshold,
            preferencesManager: preferences,
            ocrProvider: ocrProvider,
            visualChecker: MockVisualChecker(),
            cloudClassificationService: cloudClassificationService,
            contextualLearningStore: contextualLearningStore,
            breakReviewChecker: breakReviewChecker,
            sessionTimerScheduler: sessionTimerScheduler,
            breakTimerScheduler: breakTimerScheduler,
            distractionTimerScheduler: distractionTimerScheduler,
            breakReturnGraceTimerScheduler: breakReturnGraceTimerScheduler,
            doomscrollTimerScheduler: doomscrollTimerScheduler,
            focusPromptTimerScheduler: focusPromptTimerScheduler,
            userActivityProvider: MockUserActivityProvider(),
            diagnosticsRecorder: diagnosticsRecorder
        )
        engine.delegate = overlayDelegate
        engine.focusPromptsEnabled = false
        engine.distractionCountdownThreshold = 30.0
        cachedEngine = engine
    }

    deinit {
        dispose()
    }

    var engine: FocusEngine {
        guard let cachedEngine else {
            fatalError("FocusEngineTestHarness was disposed")
        }
        return cachedEngine
    }

    var sessionStore: SessionStore {
        guard let cachedSessionStore else {
            fatalError("FocusEngineTestHarness was disposed")
        }
        return cachedSessionStore
    }

    var pendingSessionTimer: TestOneShotTimerScheduler.PendingTimer? {
        sessionTimerScheduler.scheduledTimers.last
    }

    var pendingDistractionTimer: TestOneShotTimerScheduler.PendingTimer? {
        distractionTimerScheduler.scheduledTimers.last
    }

    var pendingBreakTimer: TestOneShotTimerScheduler.PendingTimer? {
        breakTimerScheduler.scheduledTimers.last
    }

    var pendingBreakReturnGraceTimer: TestOneShotTimerScheduler.PendingTimer? {
        breakReturnGraceTimerScheduler.scheduledTimers.last
    }

    var pendingDoomscrollTimer: TestOneShotTimerScheduler.PendingTimer? {
        doomscrollTimerScheduler.scheduledTimers.last
    }

    var pendingFocusPromptTimer: TestOneShotTimerScheduler.PendingTimer? {
        focusPromptTimerScheduler.scheduledTimers.last
    }

    func enter(
        bundleID: String,
        url: URL? = nil,
        title: String = "",
        observedAt: Date = Date()
    ) {
        activityMonitor.simulateContextChange(
            bundleID: bundleID,
            url: url,
            title: title,
            observedAt: observedAt
        )
    }

    func enterProductiveContext(
        bundleID: String = "com.apple.dt.Xcode",
        title: String = "Project Draft"
    ) {
        enter(bundleID: bundleID, title: title)
    }

    func enterDistractionContext(
        bundleID: String = "com.spotify.client",
        title: String = "Music"
    ) {
        enter(bundleID: bundleID, title: title)
    }

    func enterNeutralContext(
        bundleID: String = "com.example.Unknown",
        title: String = "Neutral"
    ) {
        enter(bundleID: bundleID, title: title)
    }

    func anchorSession(duration: TimeInterval, category: String? = nil, goal: String? = nil) {
        engine.anchorSession(duration: duration, category: category, goal: goal)
    }

    @discardableResult
    func fire(_ kind: FocusEngineHarnessTimerKind, ignoringCancellation: Bool = false) -> Bool {
        guard let timer = pendingTimer(for: kind) else { return false }
        if ignoringCancellation {
            timer.fireIgnoringCancellation()
        } else {
            timer.fire()
        }
        return true
    }

    func pendingTimer(for kind: FocusEngineHarnessTimerKind) -> TestOneShotTimerScheduler.PendingTimer? {
        switch kind {
        case .sessionExpiry:
            return pendingSessionTimer
        case .distractionCountdown:
            return pendingDistractionTimer
        case .breakDuration:
            return pendingBreakTimer
        case .breakReturnGrace:
            return pendingBreakReturnGraceTimer
        case .doomscroll:
            return pendingDoomscrollTimer
        case .focusPrompt:
            return pendingFocusPromptTimer
        }
    }

    func assertNoEnforcement(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(engine.isDimming, file: file, line: line)
        XCTAssertEqual(overlayDelegate.immediateDims, 0, file: file, line: line)
    }

    func assertFullyTornDown(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(cachedEngine?.activeSession, file: file, line: line)
        XCTAssertNil(cachedEngine?.breakState, file: file, line: line)
        XCTAssertNil(cachedEngine?.activeBreakCommitment, file: file, line: line)
        XCTAssertNil(cachedEngine?.workSessionStart, file: file, line: line)
        XCTAssertFalse(cachedEngine?.isDimming ?? true, file: file, line: line)
        XCTAssertEqual(cachedEngine?.state, .idle, file: file, line: line)
        XCTAssertTrue(sessionTimerScheduler.pendingTimers.isEmpty, file: file, line: line)
        XCTAssertTrue(distractionTimerScheduler.pendingTimers.isEmpty, file: file, line: line)
        XCTAssertTrue(breakTimerScheduler.pendingTimers.isEmpty, file: file, line: line)
        XCTAssertTrue(breakReturnGraceTimerScheduler.pendingTimers.isEmpty, file: file, line: line)
        XCTAssertTrue(doomscrollTimerScheduler.pendingTimers.isEmpty, file: file, line: line)
        XCTAssertTrue(focusPromptTimerScheduler.pendingTimers.isEmpty, file: file, line: line)
        XCTAssertTrue(cloudClassificationService.pendingRequests.isEmpty, file: file, line: line)
        XCTAssertEqual(overlayDelegate.activeSurfaceCount, 0, file: file, line: line)
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true

        if cachedEngine?.activeSession != nil {
            cachedEngine?.endSession(action: .dismissed)
        }
        cachedEngine?.stop()
        assertFullyTornDown()
        cachedEngine = nil
        cachedSessionStore = nil
        KeychainHelper.clearCachedKeys()
        testDefaults.removePersistentDomain(forName: suiteName)
        // Leave the temp SQLite files in place. The store writes asynchronously, and
        // deleting the live files during teardown produces noisy vnode-unlinked warnings.
    }
}
