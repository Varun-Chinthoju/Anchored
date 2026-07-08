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
    
    /// The title of the current active window or page.
    private(set) var currentTitle: String = ""
    
    /// The current context of the active window/tab.
    private(set) var currentContext: AppContext?
    
    /// The start date of the current work session (focused time).
    var workSessionStart: Date?
    
    /// The active session if the user has anchored.
    var activeSession: ActiveSession?
    
    /// The bundle identifier of the last work/neutral app in the foreground.
    private(set) var lastWorkAppBundleID: String?
    
    /// A flag indicating whether the user is currently being escalated/dimmed.
    private(set) var isDimming = false
    
    /// Productive time selected in onboarding before a focus-session prompt appears.
    var focusThreshold: TimeInterval {
        didSet {
            scheduleFocusPromptTimer()
        }
    }

    /// Whether the onboarding Smart Nudges preference allows proactive prompts.
    var focusPromptsEnabled = true {
        didSet {
            if focusPromptsEnabled {
                scheduleFocusPromptTimer()
            } else {
                cancelFocusPromptTimer()
            }
        }
    }
    
    /// The threshold for the distraction countdown pill (default 10 seconds).
    var distractionCountdownThreshold: TimeInterval = 10.0
    
    // Timers
    private var distractionTimer: Timer?
    private var sessionTimer: Timer?
    private var focusPromptTimer: Timer?
    private var hasPromptedForCurrentFocusRun = false
    
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
        
        self.activityMonitor.onContextChange = { [weak self] bundleID, url, title in
            self?.handleContextChange(bundleID: bundleID, url: url, title: title)
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
        cancelFocusPromptTimer()
        cancelIdleTimer()
    }
    
    private func isDistraction(bundleID: String, url: URL?, title: String) -> Bool {
        if let url = url {
            if URLMatcher.matches(url: url, domains: profileManager.activeProfile.distractionDomains) {
                return true
            }
            if URLMatcher.matches(url: url, domains: profileManager.activeProfile.allowedDomains) {
                return false
            }
        }
        if BrowserStrategyFactory.isSupportedBrowser(bundleID),
           BrowserContextClassifier.isEntertainment(url: url, title: title) {
            return true
        }
        if isFocusApp(bundleID: bundleID) {
            return false
        }
        if !profileManager.activeProfile.allowedApps.isEmpty {
            return true
        }
        return profileManager.activeProfile.distractionApps.contains(bundleID)
    }

    private func isFocusContext(bundleID: String, url: URL?, title: String) -> Bool {
        if let url = url {
            if URLMatcher.matches(url: url, domains: profileManager.activeProfile.allowedDomains) {
                return true
            }
            if URLMatcher.matches(url: url, domains: profileManager.activeProfile.distractionDomains) {
                return false
            }
        }
        if BrowserStrategyFactory.isSupportedBrowser(bundleID) {
            return !BrowserContextClassifier.isEntertainment(url: url, title: title)
        }
        return isFocusApp(bundleID: bundleID)
    }

    private func isFocusApp(bundleID: String) -> Bool {
        profileManager.activeProfile.allowedApps.contains(bundleID)
    }
    
    @objc private func handleActiveProfileChange() {
        guard let currentApp = currentApp else { return }
        
        let now = Date()
        let isCurrentlyDistraction = isDistraction(
            bundleID: currentApp,
            url: currentURL,
            title: currentTitle
        )
        
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
                if workSessionStart != nil {
                    requestFocusPromptIfEligible(now: now)
                }
                resetFocusTracking()
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
                if isFocusContext(bundleID: currentApp, url: currentURL, title: currentTitle) {
                    lastWorkAppBundleID = currentApp
                    if workSessionStart == nil {
                        workSessionStart = now
                        hasPromptedForCurrentFocusRun = false
                    }
                    scheduleFocusPromptTimer()
                }
            }
        }
    }
    
    /// Handles context changes from the activity monitor.
    private func handleContextChange(bundleID: String, url: URL?, title: String) {
        guard bundleID != "com.varun.Anchored" else { return }
        
        currentApp = bundleID
        currentURL = url
        currentTitle = title
        let now = Date()
        
        let context = AppContext(
            bundleIdentifier: bundleID,
            localizedName: getAppName(for: bundleID),
            title: title
        )
        currentContext = context
        
        let isFocus = isFocusContext(bundleID: bundleID, url: url, title: title)
        NotificationCenter.default.post(
            name: .focusEngineContextDidChange,
            object: self,
            userInfo: [
                "bundleID": bundleID,
                "url": url as Any,
                "title": title,
                "isFocus": isFocus,
                "context": context
            ]
        )
        
        if isDistraction(bundleID: bundleID, url: url, title: title) {
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
                requestFocusPromptIfEligible(now: now)
                resetFocusTracking()
            }
        } else if isFocusContext(bundleID: bundleID, url: url, title: title) {
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
                    hasPromptedForCurrentFocusRun = false
                }
                scheduleFocusPromptTimer()
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
                requestFocusPromptIfEligible(now: now)
                resetFocusTracking()
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
        cancelFocusPromptTimer()
        
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
        resetFocusTracking()
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
        resetFocusTracking()
        isDimming = false
        distractionStartDate = nil
        
        cancelSessionTimer()
        cancelDistractionTimer()
        
        // Notify delegate
        delegate?.sessionDidEnd()
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: nil)
        
        // Present Permission Gate immediately for testing if accessibility is not yet granted
        if !AXIsProcessTrusted() {
            delegate?.didRequestPermissionGate()
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

    private func scheduleFocusPromptTimer() {
        cancelFocusPromptTimer()
        guard focusPromptsEnabled,
              activeSession == nil,
              !hasPromptedForCurrentFocusRun,
              let start = workSessionStart else {
            return
        }

        let remaining = max(0, focusThreshold - Date().timeIntervalSince(start))
        focusPromptTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            self?.focusPromptTimerExpired()
        }
    }

    private func cancelFocusPromptTimer() {
        focusPromptTimer?.invalidate()
        focusPromptTimer = nil
    }

    private func resetFocusTracking() {
        cancelFocusPromptTimer()
        workSessionStart = nil
        hasPromptedForCurrentFocusRun = false
    }

    private func requestFocusPromptIfEligible(now: Date) {
        guard focusPromptsEnabled,
              activeSession == nil,
              !hasPromptedForCurrentFocusRun,
              let start = workSessionStart else {
            return
        }

        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= focusThreshold else { return }

        hasPromptedForCurrentFocusRun = true
        cancelFocusPromptTimer()
        let focusedAppName = getAppName(for: lastWorkAppBundleID ?? currentApp ?? "")
        delegate?.didRequestExitTrigger(duration: elapsed, appName: focusedAppName)
    }

    internal func focusPromptTimerExpired() {
        cancelFocusPromptTimer()
        guard let bundleID = currentApp,
              isFocusContext(bundleID: bundleID, url: currentURL, title: currentTitle) else {
            return
        }

        requestFocusPromptIfEligible(now: Date())
        if !hasPromptedForCurrentFocusRun {
            scheduleFocusPromptTimer()
        }
    }
    
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
                return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
            }
        }
        return bundleID
    }
}

private enum BrowserContextClassifier {
    private static let entertainmentHosts = [
        "youtube.com",
        "netflix.com",
        "twitch.tv",
        "hulu.com",
        "disneyplus.com",
        "steampowered.com",
        "store.steampowered.com",
        "epicgames.com"
    ]

    private static let entertainmentTerms = [
        "gaming",
        "gameplay",
        "livestream",
        "live stream",
        "watch movie",
        "watch tv",
        "entertainment",
        "netflix",
        "twitch"
    ]

    static func isEntertainment(url: URL?, title: String) -> Bool {
        let host = url?.host?.lowercased() ?? ""
        if entertainmentHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }

        let searchableText = "\(title) \(url?.path ?? "")".lowercased()
        return entertainmentTerms.contains(where: searchableText.contains)
    }
}

extension Notification.Name {
    static let focusEngineStateDidChange = Notification.Name("com.varun.Anchored.focusEngineStateDidChange")
    static let focusEngineContextDidChange = Notification.Name("com.varun.Anchored.focusEngineContextDidChange")
}
