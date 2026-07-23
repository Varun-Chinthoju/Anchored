import XCTest
@testable import Anchored

final class FocusEngineHarnessTests: XCTestCase {
    func testReturnToWorkInvalidatesPendingCountdown() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 1_800)
        harness.enterDistractionContext()

        let countdownTimer = try XCTUnwrap(harness.pendingDistractionTimer)
        XCTAssertFalse(countdownTimer.isCancelled)

        harness.enterProductiveContext()

        XCTAssertTrue(countdownTimer.isCancelled)
        XCTAssertEqual(harness.overlayDelegate.detectedDistractions.count, 1)
        XCTAssertEqual(harness.overlayDelegate.returnsToWork, 1)

        countdownTimer.fireIgnoringCancellation()

        harness.assertNoEnforcement()
        XCTAssertFalse(harness.engine.isDimming)
        XCTAssertEqual(harness.overlayDelegate.immediateDims, 0)
    }

    func testStopInvalidatesPendingSessionAndCountdownTimers() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 1_800)
        let sessionTimer = try XCTUnwrap(harness.pendingSessionTimer)

        harness.enterDistractionContext()
        let distractionTimer = try XCTUnwrap(harness.pendingDistractionTimer)

        harness.engine.stop()

        XCTAssertTrue(sessionTimer.isCancelled)
        XCTAssertTrue(distractionTimer.isCancelled)

        sessionTimer.fireIgnoringCancellation()
        distractionTimer.fireIgnoringCancellation()

        harness.assertNoEnforcement()
        XCTAssertEqual(harness.overlayDelegate.immediateDims, 0)
        XCTAssertEqual(
            harness.sessionStore.recordedEvents.filter { $0.type == .sessionEnd }.count,
            0
        )
    }

    func testOldSessionExpiryTimerCannotEndNewSession() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 60)
        let oldSessionTimer = try XCTUnwrap(harness.pendingSessionTimer)

        harness.engine.endSession(action: .dismissed)
        XCTAssertEqual(
            harness.sessionStore.recordedEvents.filter { $0.type == .sessionEnd }.count,
            1
        )

        harness.enterProductiveContext()
        harness.anchorSession(duration: 120)
        XCTAssertNotNil(harness.pendingSessionTimer)

        oldSessionTimer.fireIgnoringCancellation()

        XCTAssertNotNil(harness.engine.activeSession)
        XCTAssertEqual(harness.engine.state, .anchored)
        XCTAssertEqual(
            harness.sessionStore.recordedEvents.filter { $0.type == .sessionEnd }.count,
            1
        )
    }

    func testWorkspaceLifecyclePauseFreezesFocusedTime() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 3_600)

        let pauseStartedAt = Date()
        let focusedBeforePause = harness.engine.currentSessionFocusedTime(at: pauseStartedAt)

        harness.engine.pauseFocusAccountingForWorkspaceLifecycle(now: pauseStartedAt)

        let resumedAt = pauseStartedAt.addingTimeInterval(1_800)
        XCTAssertEqual(
            harness.engine.currentSessionFocusedTime(at: resumedAt),
            focusedBeforePause,
            accuracy: 0.001
        )

        harness.engine.resumeFocusAccountingForWorkspaceLifecycle(now: resumedAt)

        XCTAssertEqual(
            harness.engine.currentSessionFocusedTime(at: resumedAt),
            focusedBeforePause,
            accuracy: 0.001
        )
    }

    func testBreakReturnGraceStartsOnlyAfterLeavingAndReturning() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 1_800)
        _ = harness.engine.requestBreak(intention: "Take a walk", now: Date(), bypassMinimum: true)

        harness.enterProductiveContext()
        XCTAssertNil(harness.pendingBreakReturnGraceTimer)

        harness.enterNeutralContext()
        XCTAssertNil(harness.pendingBreakReturnGraceTimer)

        harness.enterProductiveContext()
        let graceTimer = try XCTUnwrap(harness.pendingBreakReturnGraceTimer)
        XCTAssertFalse(graceTimer.isCancelled)

        let startedAt = try XCTUnwrap(harness.engine.breakReturnGraceStartedAt)
        harness.engine.breakReturnGraceTimerExpired(
            now: startedAt.addingTimeInterval(harness.engine.breakReturnGraceThreshold + 0.1)
        )

        XCTAssertNil(harness.engine.breakState)
        XCTAssertNil(harness.engine.activeBreakCommitment)
        XCTAssertEqual(harness.overlayDelegate.returnsToWork, 2)
    }

    func testLeavingAgainCancelsExistingBreakReturnGrace() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 1_800)
        _ = harness.engine.requestBreak(intention: "Take a walk", now: Date(), bypassMinimum: true)

        harness.enterNeutralContext()
        harness.enterProductiveContext()
        let graceTimer = try XCTUnwrap(harness.pendingBreakReturnGraceTimer)

        harness.enterNeutralContext()

        XCTAssertTrue(graceTimer.isCancelled)
        XCTAssertNil(harness.engine.breakReturnGraceStartedAt)

        graceTimer.fireIgnoringCancellation()

        XCTAssertEqual(harness.engine.breakState, .breakActive)
        XCTAssertNotNil(harness.engine.activeBreakCommitment)
        XCTAssertEqual(harness.overlayDelegate.returnsToWork, 1)
    }

    func testSecondReturnSupersedesFirstBreakReturnGraceTimer() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 1_800)
        _ = harness.engine.requestBreak(intention: "Take a walk", now: Date(), bypassMinimum: true)

        harness.enterNeutralContext()
        harness.enterProductiveContext()
        let firstTimer = try XCTUnwrap(harness.pendingBreakReturnGraceTimer)

        harness.enterNeutralContext()
        harness.enterProductiveContext()
        let secondTimer = try XCTUnwrap(harness.pendingBreakReturnGraceTimer)

        XCTAssertTrue(firstTimer.isCancelled)
        XCTAssertFalse(secondTimer.isCancelled)

        firstTimer.fireIgnoringCancellation()
        XCTAssertEqual(harness.engine.breakState, .breakActive)

        let startedAt = try XCTUnwrap(harness.engine.breakReturnGraceStartedAt)
        harness.engine.breakReturnGraceTimerExpired(
            now: startedAt.addingTimeInterval(harness.engine.breakReturnGraceThreshold + 0.1)
        )

        XCTAssertNil(harness.engine.breakState)
        XCTAssertNil(harness.engine.activeBreakCommitment)
        XCTAssertEqual(harness.overlayDelegate.returnsToWork, 2)
    }

    func testStopDuringBreakClearsBreakStateAndPendingTimers() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 1_800)
        _ = harness.engine.requestBreak(intention: "Take a walk", now: Date(), bypassMinimum: true)

        harness.enterNeutralContext()
        harness.enterProductiveContext()

        let breakTimer = try XCTUnwrap(harness.pendingBreakTimer)
        let graceTimer = try XCTUnwrap(harness.pendingBreakReturnGraceTimer)

        harness.engine.stop()

        XCTAssertTrue(breakTimer.isCancelled)
        XCTAssertTrue(graceTimer.isCancelled)
        XCTAssertNil(harness.engine.breakState)
        XCTAssertNil(harness.engine.activeBreakCommitment)
        XCTAssertFalse(harness.engine.isDimming)

        breakTimer.fireIgnoringCancellation()
        graceTimer.fireIgnoringCancellation()

        harness.assertNoEnforcement()
    }

    func testOldBreakReviewResultCannotAffectNewerSession() throws {
        let harness = FocusEngineTestHarness()
        defer { harness.dispose() }

        harness.enterProductiveContext()
        harness.anchorSession(duration: 1_800)
        _ = harness.engine.requestBreak(intention: "Take a walk", now: Date(), bypassMinimum: true)

        let oldBreakTimer = try XCTUnwrap(harness.pendingBreakTimer)

        harness.engine.endSession(action: .dismissed)
        harness.enterProductiveContext()
        harness.anchorSession(duration: 1_800)

        oldBreakTimer.fireIgnoringCancellation()

        XCTAssertNil(harness.engine.breakState)
        XCTAssertNil(harness.engine.activeBreakCommitment)
        XCTAssertNotNil(harness.engine.activeSession)
        XCTAssertEqual(harness.engine.state, .anchored)
    }

    func testCloudProviderChangeRejectsOldResultAndReclassifiesCurrentContext() throws {
        try assertCloudRevisionInvalidation(
            mutateRevision: { harness in
                harness.preferences.cloudProvider = 1
            }
        )
    }

    func testActiveProfileChangeRejectsOldResultAndReclassifiesCurrentContext() throws {
        try assertCloudRevisionInvalidation { harness in
            harness.profileManager.switchProfile(to: "Video")
        }
    }

    func testCloudAPIKeyNotificationRejectsOldResultAndReclassifiesCurrentContext() throws {
        try assertCloudRevisionInvalidation { _ in
            NotificationCenter.default.post(name: .anchoredCloudAPIKeyDidChange, object: nil)
        }
    }

    private func assertCloudRevisionInvalidation(
        mutateRevision: (FocusEngineTestHarness) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let harness = FocusEngineTestHarness(
            enableCloudClassification: true,
            cloudProvider: 0
        )
        defer { harness.dispose() }

        let firstRequestReceived = expectation(description: "first cloud request")
        let secondRequestReceived = expectation(description: "second cloud request")
        var requestCount = 0
        harness.cloudClassificationService.onRequest = { _ in
            requestCount += 1
            if requestCount == 1 {
                firstRequestReceived.fulfill()
            } else if requestCount == 2 {
                secondRequestReceived.fulfill()
            }
        }

        harness.enterNeutralContext(bundleID: "com.example.Notepad", title: "Draft")
        wait(for: [firstRequestReceived], timeout: 1.0)

        mutateRevision(harness)

        wait(for: [secondRequestReceived], timeout: 1.0)

        let pendingRequests = harness.cloudClassificationService.pendingRequests
        let newestRequest = try XCTUnwrap(pendingRequests.last)

        newestRequest.complete(
            .success(
                ClassificationResult(
                    label: .productive,
                    confidence: 0.95,
                    modelVersion: "replacement-cloud",
                    latency: 0,
                    explanation: "replacement productive result"
                )
            )
        )

        let promotedSettled = expectation(description: "replacement completion settled")
        DispatchQueue.main.async {
            promotedSettled.fulfill()
        }
        wait(for: [promotedSettled], timeout: 1.0)

        for request in pendingRequests.dropLast() {
            request.complete(
                .success(
                    ClassificationResult(
                        label: .productive,
                        confidence: 0.95,
                        modelVersion: "stale-cloud",
                        latency: 0,
                        explanation: "stale productive result"
                    )
                )
            )
        }

        let staleCompletionSettled = expectation(description: "stale completion settled")
        DispatchQueue.main.async {
            staleCompletionSettled.fulfill()
        }
        wait(for: [staleCompletionSettled], timeout: 1.0)

        XCTAssertTrue(harness.engine.currentClassification.isFocus, file: file, line: line)
        XCTAssertEqual(harness.engine.state, .watching, file: file, line: line)
        XCTAssertEqual(harness.engine.lastWorkAppBundleID, "com.example.Notepad", file: file, line: line)
        XCTAssertTrue(harness.cloudClassificationService.pendingRequests.isEmpty, file: file, line: line)
    }
}
