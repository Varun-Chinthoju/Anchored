import Foundation

struct SessionEvent: Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: SessionEventType
    let appBundleID: String
    let appName: String
    let url: String?
    let focusDurationSeconds: Int?
    let sessionDurationSeconds: Int?
    let distractionAppBundleID: String?
    let action: SessionAction?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: SessionEventType,
        appBundleID: String,
        appName: String,
        url: String? = nil,
        focusDurationSeconds: Int? = nil,
        sessionDurationSeconds: Int? = nil,
        distractionAppBundleID: String? = nil,
        action: SessionAction? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.appBundleID = appBundleID
        self.appName = appName
        self.url = url
        self.focusDurationSeconds = focusDurationSeconds
        self.sessionDurationSeconds = sessionDurationSeconds
        self.distractionAppBundleID = distractionAppBundleID
        self.action = action
    }
}

enum SessionEventType: String, Codable, CaseIterable {
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case distractionDetected = "distraction_detected"
    case escalationTriggered = "escalation_triggered"
}

enum SessionAction: String, Codable, CaseIterable {
    case anchored
    case dismissed
    case timeout
    case escalated
    case returned
}
