import ApplicationServices
import Foundation

protocol UserActivityProviding {
    func idleDuration(at date: Date) -> TimeInterval
}

enum UserActivityEnvironment {
    static var shared: UserActivityProviding = SystemUserActivityProvider()
}

enum UserActivityPolicy {
    // Keep the grace short enough to avoid counting abandoned desks as work,
    // but still tolerate brief pauses while the user is actively engaged.
    static let recentActivityIdleThreshold: TimeInterval = 15.0
}

struct SystemUserActivityProvider: UserActivityProviding {
    func idleDuration(at _: Date) -> TimeInterval {
        let anyInputEventType = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
    }
}
