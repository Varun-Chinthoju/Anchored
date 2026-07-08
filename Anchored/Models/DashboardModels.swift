import Foundation

struct DashboardTimeBucket: Codable, Equatable, Identifiable {
    let date: Date
    let duration: TimeInterval

    var id: Date { date }
}

struct DashboardDomainDistribution: Codable, Equatable, Identifiable {
    let domain: String
    let duration: TimeInterval

    var id: String { domain }
}

struct DashboardAppDistribution: Codable, Equatable, Identifiable {
    let bundleID: String
    let appName: String
    let duration: TimeInterval
    let domains: [DashboardDomainDistribution]

    var id: String { bundleID }
}

struct DashboardRangeSummary: Codable, Equatable {
    let sessionCount: Int
    let totalFocusDuration: TimeInterval
    let longestSessionDuration: TimeInterval

    var averageSessionDuration: TimeInterval {
        guard sessionCount > 0 else { return 0 }
        return totalFocusDuration / Double(sessionCount)
    }
}

enum DashboardQueryError: Error, LocalizedError {
    case invalidDateRange
    case storage(Error)

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "The selected date range is invalid."
        case .storage(let error):
            return error.localizedDescription
        }
    }
}

enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(String)
}

protocol DashboardQuerying: AnyObject {
    func fetchFocusTimePerHourForLast24Hours(
        relativeTo referenceDate: Date,
        calendar: Calendar,
        completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void
    )

    func fetchFocusTimePerDay(
        since startDate: Date,
        to endDate: Date,
        calendar: Calendar,
        completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void
    )

    func fetchAppDomainFocusDistribution(
        since startDate: Date,
        to endDate: Date,
        completion: @escaping (Result<[DashboardAppDistribution], DashboardQueryError>) -> Void
    )
}
