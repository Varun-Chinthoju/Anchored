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
    let distraction_domain: String?
    let action: SessionAction?
    let category: String?
    let sessionGoal: String?

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
        distraction_domain: String? = nil,
        action: SessionAction? = nil,
        category: String? = nil,
        sessionGoal: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.appBundleID = appBundleID
        self.appName = appName
        self.url = url.flatMap { ContextSanitizer.sanitizePersistedURL(URL(string: $0)) }
        self.focusDurationSeconds = focusDurationSeconds
        self.sessionDurationSeconds = sessionDurationSeconds
        self.distractionAppBundleID = distractionAppBundleID
        self.distraction_domain = distraction_domain
        self.action = action
        self.category = category
        self.sessionGoal = sessionGoal
    }
}

extension SessionEvent {
    func persistedCopy() -> SessionEvent {
        let sanitizedURL = url.flatMap { ContextSanitizer.sanitizePersistedURL(URL(string: $0)) }
        return SessionEvent(
            id: id,
            timestamp: timestamp,
            type: type,
            appBundleID: appBundleID,
            appName: appName,
            url: sanitizedURL,
            focusDurationSeconds: focusDurationSeconds,
            sessionDurationSeconds: sessionDurationSeconds,
            distractionAppBundleID: distractionAppBundleID,
            distraction_domain: distraction_domain,
            action: action,
            category: category,
            sessionGoal: sessionGoal
        )
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
