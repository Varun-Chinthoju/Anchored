import Foundation

/// Represents an active focused work session.
struct ActiveSession: Codable, Equatable {
    /// The date the work session actually started (counts retroactively).
    let startDate: Date
    
    /// The total duration of the anchored session (e.g. 25 minutes).
    let anchoredDuration: TimeInterval
    
    /// The localized name of the work application that triggered this session.
    let appName: String
    
    /// The category/profile name of this session (optional).
    let category: String?
    
    /// The custom name/goal of this session (optional).
    let goal: String?
    
    /// Initializes a new active session.
    init(startDate: Date, anchoredDuration: TimeInterval, appName: String, category: String? = nil, goal: String? = nil) {
        self.startDate = startDate
        self.anchoredDuration = anchoredDuration
        self.appName = appName
        self.category = category
        self.goal = goal
    }

    var displayName: String {
        let trimmedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAppName.isEmpty {
            return trimmedAppName
        }

        if let trimmedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedCategory.isEmpty {
            return trimmedCategory
        }

        if let trimmedGoal = goal?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedGoal.isEmpty {
            return trimmedGoal
        }

        return "Manual Focus Session"
    }
}
