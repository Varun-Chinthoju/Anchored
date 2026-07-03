import Foundation
import AppKit
import ApplicationServices

/// The central engine that coordinates focus session tracking and state transitions.
final class FocusEngine {
    private let activityMonitor: ActivityMonitor
    private let distractionListManager: DistractionListManager
    private let sessionStore: SessionStore
    private let profileManager: ProfileManager
    
    /// The delegate to receive state transition callbacks.
    weak var delegate: FocusEngineDelegate?
    
    /// The bundle identifier of the current active application in the foreground.
    private(set) var currentApp: String?
    
    /// The URL of the current active page in the browser (if applicable).
    private(set) var currentURL: URL?
    
    /// The start date of the current work session (focused time).
    var workSessionStart: Date?
    
    /// The active session if the user has anchored.
    var activeSession: ActiveSession?
    
    /// The bundle identifier of the last work/neutral app in the foreground.
    private(set) var lastWorkAppBundleID: String?
    
    /// A flag indicating whether the user is currently being escalated/dimmed.
    private(set) var isDimming = false
    
    /// The default focus threshold (default 10 minutes / 600 seconds).
    var focusThreshold: TimeInterval
    
    /// The threshold for the distraction countdown pill (default 10 seconds).
    var distractionCountdownThreshold: TimeInterval = 10.0
    
    // Timers
    private var distractionTimer: Timer?
    private var sessionTimer: Timer?
    
    // Idle tracking
    var totalIdleTime: TimeInterval = 0.0
    private var idleTimer: Timer?
    
    /// The date when the user entered a distraction app.
    private var distractionStartDate: Date?
    
    /// The current state of the focus engine.
    var state: SessionState {
        if activeSession != nil {
            return .anchored
        } else if workSessionStart != nil {
            return .watching
        } else {
            return .idle
        }
    }
    
    /// Initializes a new FocusEngine.
    init(
        activityMonitor: ActivityMonitor,
        distractionListManager: DistractionListManager,
        sessionStore: SessionStore = .shared,
        profileManager: ProfileManager = .shared,
        focusThreshold: TimeInterval = 600.0
    ) {
        self.activityMonitor = activityMonitor
        self.distractionListManager = distractionListManager
        self.sessionStore = sessionStore
        self.profileManager = profileManager
        self.focusThreshold = focusThreshold
        
        self.activityMonitor.onContextChange = { [weak self] bundleID, url in
            self?.handleContextChange(bundleID: bundleID, url: url)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleActiveProfileChange),
            name: .activeProfileDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Starts monitoring application switch events.
    func start() {
        activityMonitor.start()
    }
    
    /// Stops monitoring application switch events.
    func stop() {
        activityMonitor.stop()
        cancelSessionTimer()
        cancelDistractionTimer()
        cancelIdleTimer()
    }
    
    private func isDistraction(bundleID: String, url: URL?) -> Bool {
        if let url = url {
            if URLMatcher.matches(url: url, domains: profileManager.activeProfile.distractionDomains) {
                return true
            }
            if URLMatcher.matches(url: url, domains: profileManager.activeProfile.allowedDomains) {
                return false
            }
        }
        return profileManager.activeProfile.distractionApps.contains(bundleID)
    }
    
    private func isFocusContext(bundleID: String, url: URL?) -> Bool {
        if let url = url {
            if URLMatcher.matches(url: url, domains: profileManager.activeProfile.allowedDomains) {
                return true
            }
            if URLMatcher.matches(url: url, domains: profileManager.activeProfile.distractionDomains) {
                return false
            }
        }
        return FocusListManager.shared.isFocusApp(bundleID)
    }
    
    @objc private func handleActiveProfileChange() {
        guard let currentApp = currentApp else { return }
        
        let now = Date()
        let isCurrentlyDistraction = isDistraction(bundleID: currentApp, url: currentURL)
        
        if isCurrentlyDistraction {
            // It is now a distraction under the new active profile
            if activeSession != nil {
                // If we have an active session
                if distractionStartDate == nil {
                    // It wasn't previously flagged as a distraction
                    distractionStartDate = now
                    
                    let event = SessionEvent(
                        type: .distractionDetected,
                        appBundleID: lastWorkAppBundleID ?? "",
                        appName: getAppName(for: lastWorkAppBundleID ?? ""),
                        url: currentURL?.absoluteString,
                        distractionAppBundleID: currentApp,
                        distraction_domain: currentURL?.host
                    )
                    sessionStore.log(event)
                    
                    delegate?.didDetectDistraction(bundleID: currentApp)
                    scheduleDistractionTimer(distractionBundleID: currentApp)
                }
            } else {
                // No active session
                if let start = workSessionStart {
                    let elapsed = now.timeIntervalSince(start)
                    if elapsed >= focusThreshold {
                        let focusedAppName = getAppName(for: lastWorkAppBundleID ?? currentApp)
                        delegate?.didRequestExitTrigger(duration: elapsed, appName: focusedAppName)
                    }
                }
                workSessionStart = nil
            }
        } else {
            // It is now allowed (NOT a distraction) under the new active profile
            if activeSession != nil {
                // Cancel warning/dimming
                if isDimming {
                    isDimming = false
                    delegate?.didReturnToWork()
                }
                cancelDistractionTimer()
                distractionStartDate = nil
            } else {
                // No active session: it is now a work or neutral app
                if isFocusContext(bundleID: currentApp, url: currentURL) {
                    lastWorkAppBundleID = currentApp
                    if workSessionStart == nil {
                        workSessionStart = now
                    }
                }
            }
        }
    }
    
    /// Handles context changes from the activity monitor.
    private func handleContextChange(bundleID: String, url: URL?) {
        guard bundleID != "com.varun.Anchored" else { return }
        
        currentApp = bundleID
        currentURL = url
        let now = Date()
        
        let isFocus = isFocusContext(bundleID: bundleID, url: url)
        NotificationCenter.default.post(
            name: .focusEngineContextDidChange,
            object: self,
            userInfo: [
                "bundleID": bundleID,
                "url": url as Any,
                "isFocus": isFocus
            ]
        )
        
        if isDistraction(bundleID: bundleID, url: url) {
            // Distraction app/URL detected
            if activeSession != nil {
                // Distraction app detected + active session -> delegate call to show countdown pill
                if distractionStartDate == nil {
                    distractionStartDate = now
                    
                    // Log distraction_detected event
                    let event = SessionEvent(
                        type: .distractionDetected,
                        appBundleID: lastWorkAppBundleID ?? "",
                        appName: getAppName(for: lastWorkAppBundleID ?? ""),
                        url: url?.absoluteString,
                        distractionAppBundleID: bundleID,
                        distraction_domain: url?.host
                    )
                    sessionStore.log(event)
                    
                    delegate?.didDetectDistraction(bundleID: bundleID)
                    
                    // Start countdown timer
                    scheduleDistractionTimer(distractionBundleID: bundleID)
                }
            } else {
                // Distraction app detected + no session
                if let start = workSessionStart {
                    let elapsed = now.timeIntervalSince(start)
                    if elapsed >= focusThreshold {
                        // elapsed > threshold -> delegate call to show exit-trigger capsule
                        let focusedAppName = getAppName(for: lastWorkAppBundleID ?? bundleID)
                        delegate?.didRequestExitTrigger(duration: elapsed, appName: focusedAppName)
                    }
                }
                // distraction app detected + no session -> resets workSessionStart
                workSessionStart = nil
            }
        } else if isFocusContext(bundleID: bundleID, url: url) {
            // Whitelisted focus app/URL detected
            lastWorkAppBundleID = bundleID
            
            if activeSession != nil {
                if isDimming {
                    isDimming = false
                    delegate?.didReturnToWork()
                }
                cancelDistractionTimer()
                distractionStartDate = nil
            } else {
                if workSessionStart == nil {
                    workSessionStart = now
                }
            }
        } else {
            // Neutral app/URL detected
            if activeSession != nil {
                if isDimming {
                    isDimming = false
                    delegate?.didReturnToWork()
                }
                cancelDistractionTimer()
                distractionStartDate = nil
            } else {
                // Check if the user accumulated enough focus time on the previous focus app before switching away
                if let start = workSessionStart {
                    let elapsed = now.timeIntervalSince(start)
                    if elapsed >= focusThreshold {
                        let focusedAppName = getAppName(for: lastWorkAppBundleID ?? bundleID)
                        delegate?.didRequestExitTrigger(duration: elapsed, appName: focusedAppName)
                    }
                }
                workSessionStart = nil
            }
        }
    }
    
    /// Locks in an active focused session.
    func anchorSession(duration: TimeInterval, category: String? = nil, goal: String? = nil) {
        let now = Date()
        let start = workSessionStart ?? now
        let focusedAppName = getAppName(for: lastWorkAppBundleID ?? "")
        
        let session = ActiveSession(
            startDate: start,
            anchoredDuration: duration,
            appName: focusedAppName,
            category: category,
            goal: goal
        )
        self.activeSession = session
        
        // Reset idle tracking
        self.totalIdleTime = 0.0
        self.startIdleTimer()
        
        // Log sessionStart event
        let focusDuration = now.timeIntervalSince(start)
        let event = SessionEvent(
            type: .sessionStart,
            appBundleID: lastWorkAppBundleID ?? "",
            appName: focusedAppName,
            url: nil,
            focusDurationSeconds: Int(focusDuration),
            sessionDurationSeconds: Int(duration),
            distractionAppBundleID: nil,
            distraction_domain: nil,
            action: .anchored,
            category: category,
            sessionGoal: goal
        )
        sessionStore.log(event)
        
        // Schedule session end timer (accounting for retroactive time)
        let remaining = max(0, duration - now.timeIntervalSince(start))
        scheduleSessionTimer(duration: remaining)
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: nil)
    }
    
    /// Resets the work session start time, e.g. when taking a break.
    func dismissTrigger() {
        workSessionStart = nil
    }
    
    /// Terminates the active session and logs a sessionEnd event.
    func endSession() {
        endSession(action: .timeout)
    }
    
    /// Terminates the active session with a specific action.
    func endSession(action: SessionAction) {
        guard let session = activeSession else { return }
        
        cancelIdleTimer()
        
        let now = Date()
        let duration = max(0, now.timeIntervalSince(session.startDate) - totalIdleTime)
        
        // Log sessionEnd event
        let event = SessionEvent(
            type: .sessionEnd,
            appBundleID: lastWorkAppBundleID ?? "",
            appName: session.appName,
            sessionDurationSeconds: Int(duration),
            action: action
        )
        sessionStore.log(event)
        
        // Clean up state
        activeSession = nil
        workSessionStart = nil
        isDimming = false
        distractionStartDate = nil
        
        cancelSessionTimer()
        cancelDistractionTimer()
        
        // Notify delegate
        delegate?.sessionDidEnd()
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: nil)
        
        // Present Permission Gate if we have at least 10 completed sessions and accessibility is not yet granted
        if !AXIsProcessTrusted() {
            let sessionCount = sessionStore.allEvents().filter { $0.type == .sessionEnd }.count
            if sessionCount >= 10 {
                delegate?.didRequestPermissionGate()
            }
        }
    }
    
    /// Returns the net focused time for the active session (subtracting idle time).
    func currentSessionFocusedTime() -> TimeInterval {
        guard let session = activeSession else { return 0.0 }
        let now = Date()
        let rawDuration = now.timeIntervalSince(session.startDate)
        return max(0, rawDuration - totalIdleTime)
    }
    
    private func startIdleTimer() {
        cancelIdleTimer()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkIdleTime()
        }
    }
    
    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }
    
    private func checkIdleTime() {
        let anyInputEventType = CGEventType(rawValue: ~0)!
        let idleTime = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
        
        if idleTime >= 60.0 {
            totalIdleTime += 1.0
            
            // Postpone the session end timer
            if let session = activeSession {
                let now = Date()
                let elapsed = now.timeIntervalSince(session.startDate)
                let netElapsed = max(0, elapsed - totalIdleTime)
                let remaining = max(0, session.anchoredDuration - netElapsed)
                scheduleSessionTimer(duration: remaining)
            }
        }
    }
    
    // MARK: - Timer Helpers
    
    private func scheduleSessionTimer(duration: TimeInterval) {
        cancelSessionTimer()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.sessionTimerExpired()
        }
    }
    
    private func cancelSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }
    
    internal func sessionTimerExpired() {
        endSession(action: .timeout)
    }
    
    private func scheduleDistractionTimer(distractionBundleID: String) {
        cancelDistractionTimer()
        distractionTimer = Timer.scheduledTimer(withTimeInterval: distractionCountdownThreshold, repeats: false) { [weak self] _ in
            self?.distractionTimerExpired(distractionBundleID: distractionBundleID)
        }
    }
    
    private func cancelDistractionTimer() {
        distractionTimer?.invalidate()
        distractionTimer = nil
    }
    
    internal func distractionTimerExpired(distractionBundleID: String) {
        isDimming = true
        
        // Log escalation_triggered event
        let event = SessionEvent(
            type: .escalationTriggered,
            appBundleID: lastWorkAppBundleID ?? "",
            appName: getAppName(for: lastWorkAppBundleID ?? ""),
            distractionAppBundleID: distractionBundleID,
            action: .escalated
        )
        sessionStore.log(event)
    }
    
    private func getAppName(for bundleID: String) -> String {
        if bundleID.isEmpty { return "" }
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = runningApp.localizedName, !name.isEmpty {
            return name
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let lastComponent = appURL.deletingPathExtension().lastPathComponent
            if !lastComponent.isEmpty {
                return lastComponent
            }
        }
        if let lastComponent = bundleID.split(separator: ".").last {
            let cleaned = String(lastComponent)
            if !cleaned.isEmpty {
                return cleaned.capitalized
            }
        }
        return bundleID
    }
}

extension Notification.Name {
    static let focusEngineStateDidChange = Notification.Name("com.varun.Anchored.focusEngineStateDidChange")
    static let focusEngineContextDidChange = Notification.Name("com.varun.Anchored.focusEngineContextDidChange")
}
