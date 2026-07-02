import Foundation

/// Represents an active focused work session.
struct ActiveSession: Codable, Equatable {
    /// The date the work session actually started (counts retroactively).
    let startDate: Date
    
    /// The total duration of the anchored session (e.g. 25 minutes).
    let anchoredDuration: TimeInterval
    
    /// The localized name of the work application that triggered this session.
    let appName: String
    
    /// Initializes a new active session.
    init(startDate: Date, anchoredDuration: TimeInterval, appName: String) {
        self.startDate = startDate
        self.anchoredDuration = anchoredDuration
        self.appName = appName
    }
}
