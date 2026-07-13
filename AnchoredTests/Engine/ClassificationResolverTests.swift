import XCTest
@testable import Anchored

final class ClassificationResolverTests: XCTestCase {
    func testEvidenceClampsConfidenceAndKeepsUIReason() {
        let evidence = ClassificationEvidence(
            label: .productive,
            source: .heuristic,
            confidence: 1.4,
            reason: .deterministicHeuristic
        )

        XCTAssertEqual(evidence.confidence, 1.0)
        XCTAssertEqual(evidence.reason, .deterministicHeuristic)
    }

    func testExplicitBlockedDomainBeatsAllowedAppEvidence() {
        let decision = ClassificationResolver().resolve([
            ClassificationEvidence(
                label: .productive,
                source: .explicitAppRule,
                confidence: 1.0,
                reason: .explicitAllowRule
            ),
            ClassificationEvidence(
                label: .distracting,
                source: .explicitDomainRule,
                confidence: 1.0,
                reason: .explicitBlockRule
            )
        ])

        XCTAssertEqual(decision.label, .distracting)
        XCTAssertEqual(decision.source, .explicitDomainRule)
        XCTAssertEqual(decision.reason, .explicitBlockRule)
    }

    func testExplicitAllowedAppBeatsHeuristicEvidence() {
        let decision = ClassificationResolver().resolve([
            ClassificationEvidence(
                label: .distracting,
                source: .heuristic,
                confidence: 1.0,
                reason: .deterministicHeuristic
            ),
            ClassificationEvidence(
                label: .productive,
                source: .explicitAppRule,
                confidence: 1.0,
                reason: .explicitAllowRule
            )
        ])

        XCTAssertEqual(decision.label, .productive)
        XCTAssertEqual(decision.source, .explicitAppRule)
    }

    func testLegacyConflictingExplicitDomainEvidencePreservesAllowWins() {
        let decision = ClassificationResolver().resolve([
            ClassificationEvidence(
                label: .distracting,
                source: .explicitDomainRule,
                confidence: 1.0,
                reason: .explicitBlockRule
            ),
            ClassificationEvidence(
                label: .productive,
                source: .explicitDomainRule,
                confidence: 1.0,
                reason: .explicitAllowRule
            )
        ])

        XCTAssertEqual(decision.label, .productive)
        XCTAssertEqual(decision.source, .explicitDomainRule)
        XCTAssertEqual(decision.reason, .explicitAllowRule)
    }

    func testLowConfidenceOptionalEvidenceResolvesNeutral() {
        let decision = ClassificationResolver().resolve([
            ClassificationEvidence(
                label: .productive,
                source: .localModel,
                confidence: 0.79,
                reason: .modelEvidence
            )
        ])

        XCTAssertEqual(decision.label, .neutral)
        XCTAssertEqual(decision.source, .neutralFallback)
        XCTAssertEqual(decision.reason, .lowConfidence)
    }

    func testConflictingOptionalEvidenceResolvesNeutral() {
        let decision = ClassificationResolver().resolve([
            ClassificationEvidence(
                label: .productive,
                source: .heuristic,
                confidence: 0.9,
                reason: .deterministicHeuristic
            ),
            ClassificationEvidence(
                label: .distracting,
                source: .heuristic,
                confidence: 0.9,
                reason: .deterministicHeuristic
            )
        ])

        XCTAssertEqual(decision.label, .neutral)
        XCTAssertEqual(decision.source, .neutralFallback)
        XCTAssertEqual(decision.reason, .conflictingEvidence)
    }

    func testOptionalDistractingModelEvidenceCannotTriggerDistraction() {
        let decision = ClassificationResolver().resolve([
            ClassificationEvidence(
                label: .distracting,
                source: .cloudModel,
                confidence: 1.0,
                reason: .modelEvidence
            )
        ])

        XCTAssertEqual(decision.label, .neutral)
        XCTAssertEqual(decision.reason, .optionalDistractionIsNonEnforcing)
    }

    func testInteractionCanPromoteAmbiguousProductiveEvidenceByAtMostFifteenPercent() {
        let decision = ClassificationResolver().resolve(
            [ClassificationEvidence(
                label: .productive,
                source: .heuristic,
                confidence: 0.70,
                reason: .deterministicHeuristic
            )],
            interactionSummary: InteractionSummary(foregroundDuration: 600, idleDuration: 0)
        )

        XCTAssertEqual(decision.label, .productive)
        XCTAssertEqual(decision.confidence, 0.85, accuracy: 0.001)
    }

    func testInteractionCannotOverrideExplicitBlockedDomain() {
        let decision = ClassificationResolver().resolve(
            [ClassificationEvidence(
                label: .distracting,
                source: .explicitDomainRule,
                confidence: 1.0,
                reason: .explicitBlockRule
            )],
            interactionSummary: InteractionSummary(foregroundDuration: 600, idleDuration: 0)
        )

        XCTAssertEqual(decision.label, .distracting)
        XCTAssertEqual(decision.confidence, 1.0)
    }

    func testInteractionBucketsAloneDoNotCreateFocusDecision() {
        let decision = ClassificationResolver().resolve(
            [ClassificationEvidence(
                label: .productive,
                source: .heuristic,
                confidence: 0.70,
                reason: .deterministicHeuristic
            )],
            interactionSummary: InteractionSummary(
                foregroundDuration: 300,
                idleDuration: 300,
                scrollBucket: 100
            )
        )

        XCTAssertTrue(decision.isNeutral)
        XCTAssertEqual(decision.reason, .lowConfidence)
    }
}
