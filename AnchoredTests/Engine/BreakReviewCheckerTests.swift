import XCTest
@testable import Anchored

final class BreakReviewCheckerTests: XCTestCase {
    private let checker = ConservativeBreakReviewChecker()

    func testExplicitDistractionCanUseExistingCountdown() {
        let identity = BreakReviewIdentity(sessionID: UUID(), contextGeneration: 4)
        let input = BreakReviewInput(
            sessionID: identity.sessionID,
            identity: ContextIdentity(bundleID: "com.example.Distraction", sanitizedURL: nil, normalizedTitle: ""),
            contextGeneration: 4,
            decision: ClassificationDecision(label: .distracting, confidence: 1, source: .explicitAppRule, reason: .explicitBlockRule, evidence: [])
        )

        let result = checker.evaluate(input: input, expectedIdentity: identity)

        XCTAssertEqual(result.outcome, .explicitDistraction)
        XCTAssertTrue(result.mayStartExistingCountdown)
    }

    func testOptionalDistractionDoesNotEnforce() {
        let identity = BreakReviewIdentity(sessionID: UUID(), contextGeneration: 4)
        let input = BreakReviewInput(
            sessionID: identity.sessionID,
            identity: ContextIdentity(bundleID: "com.example.Browser", sanitizedURL: "https://example.com", normalizedTitle: "Entertainment"),
            contextGeneration: 4,
            decision: ClassificationDecision(label: .distracting, confidence: 0.99, source: .cloudModel, reason: .modelEvidence, evidence: [])
        )

        let result = checker.evaluate(input: input, expectedIdentity: identity)

        XCTAssertEqual(result.outcome, .neutral)
        XCTAssertFalse(result.mayStartExistingCountdown)
    }

    func testLowConfidenceNeutralFailureStaleAndNoBreakAreConservative() {
        let identity = BreakReviewIdentity(sessionID: UUID(), contextGeneration: 4)
        let lowConfidence = BreakReviewInput(
            sessionID: identity.sessionID,
            identity: ContextIdentity(bundleID: "com.example.App", sanitizedURL: nil, normalizedTitle: ""),
            contextGeneration: 4,
            decision: ClassificationDecision(label: .neutral, confidence: 0.1, source: .heuristic, reason: .lowConfidence, evidence: [])
        )

        XCTAssertEqual(checker.evaluate(input: lowConfidence, expectedIdentity: identity).outcome, .lowConfidence)
        XCTAssertEqual(checker.evaluate(input: nil, expectedIdentity: identity).outcome, .noActiveBreak)
        XCTAssertEqual(checker.evaluate(input: lowConfidence, expectedIdentity: BreakReviewIdentity(sessionID: identity.sessionID, contextGeneration: 5)).outcome, .stale)
    }
}
