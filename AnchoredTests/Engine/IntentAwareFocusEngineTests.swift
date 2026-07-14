import XCTest
@testable import Anchored

final class IntentAwareFocusEngineTests: XCTestCase {
    private var mockActivityMonitor: MockActivityMonitor!
    private var distractionListManager: DistractionListManager!
    private var profileManager: ProfileManager!
    private var testPreferences: PreferencesManager!
    private var sessionStore: SessionStore!
    private var mockDelegate: MockFocusEngineDelegate!
    private var intentClassifier: RecordingIntentClassifier!
    private var outcomeStore: RecordingClassificationOutcomeStore!
    private var engine: FocusEngine!
    private var tempStoreURL: URL!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()

        defaultsSuiteName = "IntentAwareFocusEngineTests-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuiteName)!
        testDefaults.removePersistentDomain(forName: defaultsSuiteName)

        distractionListManager = DistractionListManager(defaults: testDefaults)
        profileManager = ProfileManager(defaults: testDefaults)
        testPreferences = PreferencesManager(defaults: testDefaults)
        testPreferences.enableLocalTextClassification = false
        testPreferences.enableCloudClassification = false
        testPreferences.enableImageClassification = false

        let tempDirectory = FileManager.default.temporaryDirectory
        tempStoreURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        sessionStore = SessionStore(fileURL: tempStoreURL)

        mockActivityMonitor = MockActivityMonitor()
        mockDelegate = MockFocusEngineDelegate()
        rebuildEngine { _ in
            IntentClassificationResult(
                relation: .uncertain,
                confidence: 0.0,
                source: .heuristic,
                modelVersion: "test",
                latency: 0.0,
                reason: .insufficientIntent,
                explanation: "default"
            )
        }
    }

    override func tearDown() {
        engine.stop()
        engine = nil
        sessionStore = nil
        mockDelegate = nil
        intentClassifier = nil
        outcomeStore = nil
        mockActivityMonitor = nil

        if let defaultsSuiteName {
            UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaultsSuiteName = nil

        let directoryURL = tempStoreURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        super.tearDown()
    }

    func testRelatedContextDoesNotStartGrace() {
        rebuildEngine { input in
            self.makeResult(relation: .related, confidence: 0.95, reason: .goalMatched)
        }
        prepareActiveSession(goal: "Write docs")

        let recordExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Editor",
            title: "Project Draft"
        )

        wait(for: [recordExpectation], timeout: 2)

        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(engine.currentIntentResult?.relation, .related)
    }

    func testHighConfidenceEntertainmentStartsGraceDuringActiveSession() {
        rebuildEngine { _ in
            self.makeResult(relation: .entertainment, confidence: 0.94, reason: .entertainmentMatched)
        }
        prepareActiveSession(goal: "Write docs")

        let recordExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://youtube.com/watch?v=123"),
            title: "Focus break"
        )

        wait(for: [recordExpectation], timeout: 2)

        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
        XCTAssertFalse(engine.isDimming)
        XCTAssertGreaterThan(engine.currentDistractionGraceRemaining ?? 0, 0)
    }

    func testHighConfidenceUnrelatedStartsGrace() {
        rebuildEngine { _ in
            self.makeResult(relation: .unrelated, confidence: 0.93, reason: .goalMismatched)
        }
        prepareActiveSession(goal: "Write docs")

        let recordExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "News"
        )

        wait(for: [recordExpectation], timeout: 2)

        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
        XCTAssertFalse(engine.isDimming)
        XCTAssertGreaterThan(engine.currentDistractionGraceRemaining ?? 0, 0)
    }

    func testScreenDoesNotDimBeforeThirtySeconds() {
        rebuildEngine { _ in
            self.makeResult(relation: .unrelated, confidence: 0.93, reason: .goalMismatched)
        }
        prepareActiveSession(goal: "Write docs")

        let recordExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "News"
        )

        wait(for: [recordExpectation], timeout: 2)

        XCTAssertFalse(engine.isDimming)
        XCTAssertLessThanOrEqual(engine.currentDistractionGraceRemaining ?? 0, 30)
        XCTAssertGreaterThan(engine.currentDistractionGraceRemaining ?? 0, 0)
    }

    func testRemainingInUnrelatedContextTriggersDimAfterThirtySeconds() {
        rebuildEngine { _ in
            self.makeResult(relation: .unrelated, confidence: 0.93, reason: .goalMismatched)
        }
        prepareActiveSession(goal: "Write docs")

        let recordExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "News",
            observedAt: Date().addingTimeInterval(-31)
        )

        wait(for: [recordExpectation], timeout: 2)

        XCTAssertTrue(engine.isDimming)
        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
    }

    func testReturningToRelatedWorkCancelsGrace() {
        rebuildEngine { input in
            if input.snapshot.bundleIdentifier == "com.example.Editor" {
                return self.makeResult(relation: .related, confidence: 0.95, reason: .goalMatched)
            }
            return self.makeResult(relation: .unrelated, confidence: 0.93, reason: .goalMismatched)
        }
        prepareActiveSession(goal: "Write docs")

        let firstExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "News"
        )

        wait(for: [firstExpectation], timeout: 2)
        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
        XCTAssertFalse(engine.isDimming)

        let secondExpectation = expectation(description: "related context recorded")
        var recordCount = 0
        outcomeStore.onRecord = { _ in
            recordCount += 1
            if recordCount == 2 {
                secondExpectation.fulfill()
            }
        }

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Editor",
            title: "Project Draft"
        )

        wait(for: [secondExpectation], timeout: 2)

        XCTAssertTrue(mockDelegate.returnsToWork > 0)
        XCTAssertFalse(engine.isDimming)
        XCTAssertEqual(engine.currentIntentResult?.relation, .related)
    }

    func testSwitchingBetweenUnrelatedContextsDoesNotResetGraceTimer() {
        rebuildEngine { _ in
            self.makeResult(relation: .unrelated, confidence: 0.93, reason: .goalMismatched)
        }
        prepareActiveSession(goal: "Write docs")

        let firstExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "News"
        )

        wait(for: [firstExpectation], timeout: 2)
        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)

        let secondExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Player",
            url: URL(string: "https://news.example.com/clip"),
            title: "Clip"
        )

        wait(for: [secondExpectation], timeout: 2)

        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
        XCTAssertFalse(engine.isDimming)
    }

    func testUncertainOrLowConfidenceResultsDoNotEnforce() {
        rebuildEngine { _ in
            self.makeResult(relation: .uncertain, confidence: 0.42, reason: .insufficientIntent)
        }
        prepareActiveSession(goal: "Write docs")

        let recordExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Unknown",
            title: "Untitled"
        )

        wait(for: [recordExpectation], timeout: 2)

        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
        XCTAssertTrue(engine.currentClassification.isNeutral)

        rebuildEngine { _ in
            self.makeResult(relation: .unrelated, confidence: 0.50, reason: .lowConfidence)
        }
        prepareActiveSession(goal: "Write docs")

        let lowConfidenceExpectation = expectOutcomeRecords(2)
        outcomeStore.onRecord = { _ in lowConfidenceExpectation.fulfill() }

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Unknown",
            title: "Untitled"
        )

        wait(for: [lowConfidenceExpectation], timeout: 2)

        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
    }

    func testExplicitAllowRuleOverridesAIDistractionResult() {
        let profile = WorkProfile(
            name: "Allowed",
            allowedApps: ["com.example.Editor"],
            allowedDomains: ["example.com"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        rebuildEngine { _ in
            self.makeResult(relation: .unrelated, confidence: 0.98, reason: .goalMismatched)
        }
        prepareActiveSession(goal: "Write docs")

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Editor",
            url: URL(string: "https://example.com/path"),
            title: "Editor"
        )

        XCTAssertEqual(intentClassifier.callCount, 0)
        XCTAssertTrue(engine.currentClassification.source.isExplicitRule)
        XCTAssertTrue(engine.currentClassification.isFocus)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
    }

    func testExplicitBlockRuleRetainsPrecedence() {
        let profile = WorkProfile(
            name: "Blocked",
            distractionApps: ["com.example.Editor"],
            distractionDomains: ["example.com"]
        )
        profileManager.addProfile(profile)
        profileManager.switchProfile(to: profile.name)

        rebuildEngine { _ in
            self.makeResult(relation: .related, confidence: 0.98, reason: .goalMatched)
        }
        prepareActiveSession(goal: "Write docs")

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Editor",
            url: URL(string: "https://example.com/path"),
            title: "Editor"
        )

        XCTAssertEqual(intentClassifier.callCount, 0)
        XCTAssertEqual(engine.currentClassification.source, .explicitDomainRule)
        XCTAssertTrue(engine.currentClassification.isDistraction)
        XCTAssertEqual(mockDelegate.detectedDistractions.count, 1)
    }

    func testStaleAsynchronousResultCannotAffectNewerContext() {
        let stagedClassifier = StagedIntentClassifier(
            firstResult: self.makeResult(relation: .unrelated, confidence: 0.95, reason: .goalMismatched),
            secondResult: self.makeResult(relation: .related, confidence: 0.96, reason: .goalMatched)
        )
        engine?.stop()
        outcomeStore = RecordingClassificationOutcomeStore()
        outcomeStore.isEnabled = true
        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            intentClassifier: stagedClassifier,
            classificationOutcomeStore: outcomeStore
        )
        engine.delegate = mockDelegate
        engine.distractionCountdownThreshold = 30
        prepareActiveSession(goal: "Write docs")

        let firstCallStarted = expectation(description: "first classification started")
        let secondCallStarted = expectation(description: "second classification started")
        stagedClassifier.onFirstCall = {
            firstCallStarted.fulfill()
        }
        stagedClassifier.onSecondCall = {
            secondCallStarted.fulfill()
        }

        let resultExpectation = expectation(description: "new context result record")
        var recordCount = 0
        outcomeStore.onRecord = { _ in
            recordCount += 1
            if recordCount == 3 {
                resultExpectation.fulfill()
            }
        }

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "Old"
        )
        wait(for: [firstCallStarted], timeout: 2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Editor",
            title: "Project Draft"
        )

        wait(for: [secondCallStarted], timeout: 2)
        stagedClassifier.releaseSecondCall()
        stagedClassifier.releaseFirstCall()
        wait(for: [resultExpectation], timeout: 2)

        XCTAssertEqual(engine.currentApp, "com.example.Editor")
        XCTAssertEqual(engine.currentClassification.reason, .intentRelated)
        XCTAssertEqual(engine.currentIntentResult?.relation, .related)
        XCTAssertFalse(engine.isDimming)
    }

    func testNoActiveSessionMeansNoImmediateAIBlock() {
        rebuildEngine { _ in
            self.makeResult(relation: .unrelated, confidence: 0.95, reason: .goalMismatched)
        }

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "News"
        )

        XCTAssertEqual(intentClassifier.callCount, 0)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
    }

    func testBreakAndDeclaredActivityBypassesStillWork() {
        rebuildEngine { _ in
            self.makeResult(relation: .unrelated, confidence: 0.95, reason: .goalMismatched)
        }
        prepareActiveSession(goal: "Write docs")

        engine.requestBreak(intention: "Take a break", bypassMinimum: true)
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "News"
        )

        XCTAssertEqual(intentClassifier.callCount, 0)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)

        engine.resumeAfterBreakReview()
        engine.startDeclaredActivityBypass(activity: "Research")
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Browser",
            url: URL(string: "https://example.com/news"),
            title: "Research notes"
        )

        XCTAssertEqual(intentClassifier.callCount, 0)
        XCTAssertTrue(mockDelegate.detectedDistractions.isEmpty)
        XCTAssertFalse(engine.isDimming)
    }

    func testClassifierWorkAndDatabaseWritesDoNotRunOnMainThread() {
        rebuildEngine { _ in
            self.makeResult(relation: .related, confidence: 0.95, reason: .goalMatched)
        }
        prepareActiveSession(goal: "Write docs")

        let recordExpectation = expectOutcomeRecords(2)

        mockActivityMonitor.simulateContextChange(
            bundleID: "com.example.Editor",
            title: "Project Draft"
        )

        wait(for: [recordExpectation], timeout: 2)

        XCTAssertTrue(intentClassifier.threadFlags.allSatisfy { !$0 })
        XCTAssertTrue(outcomeStore.recordThreadFlags.allSatisfy { !$0 })
    }

    private func rebuildEngine(
        resultProvider: @escaping (IntentClassificationInput) -> IntentClassificationResult
    ) {
        engine?.stop()
        intentClassifier = RecordingIntentClassifier(resultProvider: resultProvider)
        outcomeStore = RecordingClassificationOutcomeStore()
        outcomeStore.isEnabled = true

        engine = FocusEngine(
            activityMonitor: mockActivityMonitor,
            distractionListManager: distractionListManager,
            sessionStore: sessionStore,
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: testPreferences,
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker(),
            intentClassifier: intentClassifier,
            classificationOutcomeStore: outcomeStore
        )
        engine.delegate = mockDelegate
        engine.distractionCountdownThreshold = 30
    }

    private func prepareActiveSession(goal: String) {
        mockActivityMonitor.simulateContextChange(
            bundleID: "com.apple.dt.Xcode",
            title: "Project"
        )
        engine.anchorSession(duration: 3_600, category: "Work", goal: goal)
    }

    private func expectOutcomeRecords(_ count: Int) -> XCTestExpectation {
        let expectation = expectation(description: "classification outcome records \(count)")
        var observedCount = 0
        outcomeStore.onRecord = { _ in
            observedCount += 1
            if observedCount == count {
                expectation.fulfill()
            }
        }
        return expectation
    }

    private func makeResult(
        relation: IntentRelation,
        confidence: Double,
        reason: IntentClassificationReason
    ) -> IntentClassificationResult {
        IntentClassificationResult(
            relation: relation,
            confidence: confidence,
            source: .heuristic,
            modelVersion: "test-intent-v1",
            latency: 0.0,
            reason: reason,
            explanation: "test"
        )
    }
}

private final class RecordingIntentClassifier: IntentClassifying, @unchecked Sendable {
    private let lock = NSLock()
    private let resultProvider: (IntentClassificationInput) -> IntentClassificationResult

    private(set) var callCount = 0
    private(set) var threadFlags: [Bool] = []
    private(set) var inputs: [IntentClassificationInput] = []

    init(resultProvider: @escaping (IntentClassificationInput) -> IntentClassificationResult) {
        self.resultProvider = resultProvider
    }

    func classify(input: IntentClassificationInput) -> IntentClassificationResult {
        lock.lock()
        callCount += 1
        threadFlags.append(Thread.isMainThread)
        inputs.append(input)
        lock.unlock()
        return resultProvider(input)
    }
}

private final class StagedIntentClassifier: IntentClassifying, @unchecked Sendable {
    private let lock = NSLock()
    private let firstResult: IntentClassificationResult
    private let secondResult: IntentClassificationResult
    private let firstPermit = DispatchSemaphore(value: 0)
    private let secondPermit = DispatchSemaphore(value: 0)

    private(set) var callCount = 0
    private(set) var threadFlags: [Bool] = []
    private(set) var inputs: [IntentClassificationInput] = []

    var onFirstCall: (() -> Void)?
    var onSecondCall: (() -> Void)?

    init(firstResult: IntentClassificationResult, secondResult: IntentClassificationResult) {
        self.firstResult = firstResult
        self.secondResult = secondResult
    }

    func classify(input: IntentClassificationInput) -> IntentClassificationResult {
        lock.lock()
        callCount += 1
        threadFlags.append(Thread.isMainThread)
        inputs.append(input)
        let callIndex = callCount
        lock.unlock()

        if callIndex == 1 {
            onFirstCall?()
            firstPermit.wait()
            return firstResult
        } else {
            onSecondCall?()
            secondPermit.wait()
            return secondResult
        }
    }

    func releaseFirstCall() {
        firstPermit.signal()
    }

    func releaseSecondCall() {
        secondPermit.signal()
    }
}

private final class RecordingClassificationOutcomeStore: ClassificationOutcomeRecording {
    var isEnabled = true

    private let queue = DispatchQueue(label: "com.varun.Anchored.IntentAwareFocusEngineTests.OutcomeStore")
    private(set) var records: [ClassificationOutcome] = []
    private(set) var corrections: [(ClassificationOutcome.Identity, ClassificationCorrection)] = []
    private(set) var recordThreadFlags: [Bool] = []
    private(set) var correctionThreadFlags: [Bool] = []

    var onRecord: ((ClassificationOutcome) -> Void)?
    var onCorrection: ((ClassificationOutcome.Identity, ClassificationCorrection) -> Void)?

    func record(_ outcome: ClassificationOutcome, completion: StorageWriteCompletion?) {
        queue.async {
            self.recordThreadFlags.append(Thread.isMainThread)
            self.records.append(outcome)
            self.onRecord?(outcome)
            completion?(.success(()))
        }
    }

    func recordCorrection(
        identity: ClassificationOutcome.Identity,
        correction: ClassificationCorrection,
        correctedAt: Date,
        completion: StorageWriteCompletion?
    ) {
        queue.async {
            self.correctionThreadFlags.append(Thread.isMainThread)
            self.corrections.append((identity, correction))
            self.onCorrection?(identity, correction)
            completion?(.success(()))
        }
    }

    func clearAll(completion: StorageWriteCompletion?) {
        queue.async {
            self.records.removeAll()
            self.corrections.removeAll()
            completion?(.success(()))
        }
    }

    func prune(retentionDays: Int, completion: StorageWriteCompletion?) {
        queue.async {
            completion?(.success(()))
        }
    }

    func count(completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            completion(.success(self.records.count))
        }
    }

    func oldestObservationDate(completion: @escaping (Result<Date?, Error>) -> Void) {
        queue.async {
            completion(.success(self.records.first?.observedAt))
        }
    }
}
