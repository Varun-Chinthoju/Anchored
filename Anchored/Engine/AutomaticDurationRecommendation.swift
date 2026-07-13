import Foundation

struct AutomaticDurationRecommendation {
    static let minimumEligibleSessions = 5
    static let recentSessionLimit = 12
    static let minimumDuration: TimeInterval = 5 * 60
    static let lowerBound: TimeInterval = 15 * 60
    static let upperBound: TimeInterval = 90 * 60
    static let roundingIncrement: TimeInterval = 5 * 60

    static func recommendedDuration(
        from events: [SessionEvent],
        fallback: TimeInterval
    ) -> TimeInterval {
        let durations = events
            .filter {
                $0.type == .sessionEnd &&
                $0.completionOutcome == .done &&
                TimeInterval($0.sessionDurationSeconds ?? 0) >= minimumDuration
            }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(recentSessionLimit)
            .map { TimeInterval($0.sessionDurationSeconds ?? 0) }

        guard durations.count >= minimumEligibleSessions else {
            return fallback
        }

        let sortedDurations = durations.sorted()
        let middle = sortedDurations.count / 2
        let median: TimeInterval
        if sortedDurations.count.isMultiple(of: 2) {
            median = (sortedDurations[middle - 1] + sortedDurations[middle]) / 2
        } else {
            median = sortedDurations[middle]
        }

        let rounded = (median / roundingIncrement).rounded() * roundingIncrement
        return min(upperBound, max(lowerBound, rounded))
    }
}
