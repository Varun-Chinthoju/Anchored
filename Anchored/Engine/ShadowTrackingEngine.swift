import Foundation
import AppKit

final class ShadowTrackingEngine {
    private let focusEngine: FocusEngine
    private let preferencesManager: PreferencesManager
    
    private var timer: Timer?
    private var continuousWorkTime: TimeInterval = 0.0
    private var isSleeping = false
    private var isFocusContextActive = false
    
    var onThresholdCrossed: (() -> Void)?
    
    // Default threshold is 5 minutes (300 seconds)
    var nudgeThreshold: TimeInterval = 300.0
    
    init(focusEngine: FocusEngine, preferencesManager: PreferencesManager = .shared) {
        self.focusEngine = focusEngine
        self.preferencesManager = preferencesManager
        
        setupObservers()
        updateTrackingState()
    }
    
    deinit {
        stopTimer()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    private func setupObservers() {
        // Observe focus engine state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .focusEngineStateDidChange,
            object: nil
        )
        
        // Observe context changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContextChange(_:)),
            name: .focusEngineContextDidChange,
            object: nil
        )
        
        // Observe sleep/wake
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    @objc private func handleStateChange() {
        updateTrackingState()
    }
    
    @objc private func handleContextChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let isFocus = userInfo["isFocus"] as? Bool else {
            return
        }
        
        isFocusContextActive = isFocus
        updateTrackingState()
    }
    
    @objc private func handleWorkspaceWillSleep() {
        isSleeping = true
        updateTrackingState()
    }
    
    @objc private func handleWorkspaceDidWake() {
        isSleeping = false
        updateTrackingState()
    }
    
    private func updateTrackingState() {
        // Only track if:
        // 1. Focus session is NOT active (i.e. focusEngine.state != .anchored)
        // 2. Preferences enable smart nudges
        // 3. System is NOT sleeping
        // 4. Current context is a focus context
        
        let shouldTrack = (focusEngine.state != .anchored) &&
                          preferencesManager.enableSmartNudges &&
                          !isSleeping &&
                          isFocusContextActive
        
        if shouldTrack {
            startTimerIfNeeded()
        } else {
            stopTimer()
            if !isFocusContextActive || focusEngine.state == .anchored {
                // Reset continuous time if they switch away from a focus app or start a real session
                continuousWorkTime = 0.0
            }
        }
    }
    
    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func tick() {
        continuousWorkTime += 1.0
        if continuousWorkTime >= nudgeThreshold {
            onThresholdCrossed?()
            // Reset counter to avoid double nudging repeatedly
            continuousWorkTime = 0.0
        }
    }
    
    // For unit testing
    func getContinuousWorkTime() -> TimeInterval {
        return continuousWorkTime
    }
    
    func setContinuousWorkTime(_ val: TimeInterval) {
        continuousWorkTime = val
    }
    
    func forceUpdateTrackingState() {
        updateTrackingState()
    }
}
