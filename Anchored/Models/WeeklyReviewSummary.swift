import Foundation

/// Local aggregate data used by the Dashboard and weekly review notification.
/// It intentionally contains counts and durations only, never written summaries.
struct WeeklyReviewSummary: Codable, Equatable {
    let weekStart: Date
    let weekEnd: Date
    let sessionCount: Int
    let completedSessionCount: Int
    let totalFocusDuration: TimeInterval
    let summaryCount: Int

    init(
        weekStart: Date,
        weekEnd: Date,
        sessionCount: Int,
        completedSessionCount: Int,
        totalFocusDuration: TimeInterval,
        summaryCount: Int
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.sessionCount = max(0, sessionCount)
        self.completedSessionCount = max(0, completedSessionCount)
        self.totalFocusDuration = max(0, totalFocusDuration)
        self.summaryCount = max(0, summaryCount)
    }
}
