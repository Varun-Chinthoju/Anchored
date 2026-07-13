import Foundation

/// Cross-module lifecycle states for a session commitment and its completion summary.
/// Intention text is kept in memory by the runtime and is not persisted by this contract.
enum CommitmentState: String, Codable, CaseIterable, Equatable {
    case breakRequested
    case breakActive
    case breakReview
    case done
    case skippedSummary
    case completedSummary
}

enum SessionCompletionOutcome: String, Codable, CaseIterable, Equatable {
    case done
    case timeout
    case dismissed
    case escalated
}

enum SessionSummaryState: String, Codable, CaseIterable, Equatable {
    case notRequested
    case skippedSummary
    case completedSummary
}

struct BreakReviewIdentity: Equatable, Hashable {
    let sessionID: UUID
    let contextGeneration: UInt64
}

struct BreakCommitment: Equatable {
    let sessionID: UUID
    let intention: String
    let requestedAt: Date
    let deadline: Date
    let reviewIdentity: BreakReviewIdentity
}

enum BreakRequestDecision: Equatable {
    case refusedUnderMinimum
    case accepted(BreakCommitment)
}
