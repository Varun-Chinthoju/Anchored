import Foundation

enum BreakReviewOutcome: Equatable {
    case explicitDistraction
    case mismatch
    case neutral
    case lowConfidence
    case failed
    case stale
    case noActiveBreak
}

/// The only input accepted by the break reviewer: sanitized identity and a
/// final classification category. It cannot carry screenshots, OCR, raw URLs,
/// typed text, or model explanations.
struct BreakReviewInput: Equatable {
    let sessionID: UUID
    let identity: ContextIdentity
    let contextGeneration: UInt64
    let decision: ClassificationDecision?
}

struct BreakReviewResult: Equatable {
    let outcome: BreakReviewOutcome

    var mayStartExistingCountdown: Bool {
        outcome == .explicitDistraction
    }
}

protocol BreakReviewChecking {
    func evaluate(
        input: BreakReviewInput?,
        expectedIdentity: BreakReviewIdentity?
    ) -> BreakReviewResult
}

struct ConservativeBreakReviewChecker: BreakReviewChecking {
    func evaluate(
        input: BreakReviewInput?,
        expectedIdentity: BreakReviewIdentity?
    ) -> BreakReviewResult {
        guard let input, let expectedIdentity else {
            return BreakReviewResult(outcome: .noActiveBreak)
        }

        guard input.sessionID == expectedIdentity.sessionID,
              input.contextGeneration == expectedIdentity.contextGeneration else {
            return BreakReviewResult(outcome: .stale)
        }

        guard let decision = input.decision else {
            return BreakReviewResult(outcome: .failed)
        }

        if decision.source.isExplicitRule {
            if decision.isDistraction {
                return BreakReviewResult(outcome: .explicitDistraction)
            }
            return BreakReviewResult(outcome: .mismatch)
        }

        if decision.reason == .lowConfidence || decision.confidence < ClassificationPolicy.lowConfidenceThreshold {
            return BreakReviewResult(outcome: .lowConfidence)
        }

        // Heuristics and optional classifier output are advisory only during a
        // break review. They never start the dimming/countdown path directly.
        return decision.isFocus
            ? BreakReviewResult(outcome: .mismatch)
            : BreakReviewResult(outcome: .neutral)
    }
}
