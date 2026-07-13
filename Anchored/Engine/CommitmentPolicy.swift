import Foundation

enum CommitmentPolicy {
    static let minimumBreakFocusDuration: TimeInterval = 30 * 60
    static let breakDuration: TimeInterval = 2 * 60
    static let weeklyReviewDeliveryHour = 8
    static let weeklyReviewDeliveryWeekday = 1 // Sunday in Calendar's Gregorian weekday numbering.
    static let explicitRulesMayEnforceBreakReview = true
    static let optionalClassifiersMayEnforceBreakReview = false
    static let maximumSessionSummaryLength = 500

    static func breakRequest(
        netFocusedDuration: TimeInterval,
        intention: String,
        now: Date,
        sessionID: UUID,
        contextGeneration: UInt64,
        bypassMinimum: Bool = false
    ) -> BreakRequestDecision {
        guard bypassMinimum || netFocusedDuration >= minimumBreakFocusDuration else {
            return .refusedUnderMinimum
        }

        let reviewIdentity = BreakReviewIdentity(sessionID: sessionID, contextGeneration: contextGeneration)
        return .accepted(
            BreakCommitment(
                sessionID: sessionID,
                intention: intention,
                requestedAt: now,
                deadline: now.addingTimeInterval(breakDuration),
                reviewIdentity: reviewIdentity
            )
        )
    }

    static func canFinishSession(afterNetFocusedDuration: TimeInterval) -> Bool {
        true
    }

    static func summaryState(promptEnabled: Bool, summary: String?) -> SessionSummaryState {
        guard promptEnabled else { return .notRequested }
        guard let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .skippedSummary
        }
        return .completedSummary
    }

    /// Returns a bounded, local-only summary or nil for empty/oversized input.
    static func sanitizedSessionSummary(_ summary: String?) -> String? {
        guard let summary else { return nil }

        let withoutControlCharacters = summary.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        let normalized = withoutControlCharacters
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty, normalized.count <= maximumSessionSummaryLength else {
            return nil
        }
        return normalized
    }

    static func isCurrentReview(_ identity: BreakReviewIdentity, expected: BreakReviewIdentity) -> Bool {
        identity == expected
    }

    static func nextWeeklyReviewDelivery(after date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = weeklyReviewDeliveryWeekday
        components.hour = weeklyReviewDeliveryHour
        components.minute = 0
        components.second = 0

        guard let thisWeekDelivery = calendar.date(from: components) else {
            return date
        }
        if thisWeekDelivery > date {
            return thisWeekDelivery
        }

        return calendar.date(byAdding: .day, value: 7, to: thisWeekDelivery) ?? thisWeekDelivery
    }
}
