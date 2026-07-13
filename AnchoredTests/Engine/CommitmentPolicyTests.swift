import XCTest
@testable import Anchored

final class CommitmentPolicyTests: XCTestCase {
    func testBreakBeforeMinimumIsRefusedWithoutCreatingCommitment() {
        let decision = CommitmentPolicy.breakRequest(
            netFocusedDuration: CommitmentPolicy.minimumBreakFocusDuration - 1,
            intention: "Check the mail",
            now: Date(),
            sessionID: UUID(),
            contextGeneration: 4
        )

        XCTAssertEqual(decision, .refusedUnderMinimum)
    }

    func testBreakAtMinimumCreatesTwoMinuteCommitment() {
        let now = Date(timeIntervalSince1970: 100)
        let sessionID = UUID()
        let decision = CommitmentPolicy.breakRequest(
            netFocusedDuration: CommitmentPolicy.minimumBreakFocusDuration,
            intention: "Stretch",
            now: now,
            sessionID: sessionID,
            contextGeneration: 9
        )

        guard case .accepted(let commitment) = decision else {
            return XCTFail("Expected an accepted break commitment")
        }

        XCTAssertEqual(commitment.intention, "Stretch")
        XCTAssertEqual(commitment.sessionID, sessionID)
        XCTAssertEqual(commitment.deadline, now.addingTimeInterval(CommitmentPolicy.breakDuration))
        XCTAssertEqual(commitment.reviewIdentity, BreakReviewIdentity(sessionID: sessionID, contextGeneration: 9))
    }

    func testDoneIsAvailableAtAnySessionDuration() {
        XCTAssertTrue(CommitmentPolicy.canFinishSession(afterNetFocusedDuration: 0))
        XCTAssertTrue(CommitmentPolicy.canFinishSession(afterNetFocusedDuration: 1))
    }

    func testExplicitRulesHavePrecedenceAndOptionalClassifiersCannotEnforce() {
        XCTAssertTrue(CommitmentPolicy.explicitRulesMayEnforceBreakReview)
        XCTAssertFalse(CommitmentPolicy.optionalClassifiersMayEnforceBreakReview)
    }

    func testSummaryStateDistinguishesSkippedFromCompleted() {
        XCTAssertEqual(CommitmentPolicy.summaryState(promptEnabled: false, summary: nil), .notRequested)
        XCTAssertEqual(CommitmentPolicy.summaryState(promptEnabled: true, summary: nil), .skippedSummary)
        XCTAssertEqual(CommitmentPolicy.summaryState(promptEnabled: true, summary: "  Shipped it.  "), .completedSummary)
    }

    func testStaleReviewIdentityIsRejected() {
        let identity = BreakReviewIdentity(sessionID: UUID(), contextGeneration: 2)
        XCTAssertTrue(CommitmentPolicy.isCurrentReview(identity, expected: identity))
        XCTAssertFalse(
            CommitmentPolicy.isCurrentReview(
                identity,
                expected: BreakReviewIdentity(sessionID: identity.sessionID, contextGeneration: 3)
            )
        )
    }

    func testWeeklyReviewDeliveryUsesSundayAtEightLocalTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 9))!

        let deliveryDate = CommitmentPolicy.nextWeeklyReviewDelivery(after: referenceDate, calendar: calendar)
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: deliveryDate)

        XCTAssertEqual(components.weekday, 1)
        XCTAssertEqual(components.hour, CommitmentPolicy.weeklyReviewDeliveryHour)
        XCTAssertEqual(components.minute, 0)
    }
}
