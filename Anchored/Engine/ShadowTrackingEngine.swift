import Foundation
import AppKit

final class ShadowTrackingEngine {
    private let focusEngine: FocusEngine
    private let preferencesManager: PreferencesManager
    
    private var timer: Timer?
    private var continuousWorkTime: TimeInterval = 0.0
    private var isSleeping = false
    private var isFocusContextActive: Bool {
        focusEngine.currentClassification.isFocus
    }
    
    var onThresholdCrossed: (() -> Void)?
    
    var nudgeThreshold: TimeInterval
    
    init(focusEngine: FocusEngine, preferencesManager: PreferencesManager = .shared) {
        self.focusEngine = focusEngine
        self.preferencesManager = preferencesManager
        self.nudgeThreshold = preferencesManager.effectiveFocusThreshold
        
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
            object: focusEngine
        )
        
        // Observe classification changes (covers both initial context switches and promotions)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClassificationChange),
            name: .focusEngineClassificationDidChange,
            object: focusEngine
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
    
    @objc private func handleClassificationChange() {
        print("🕵️ [Shadow] classificationChange isFocus=\(isFocusContextActive) state=\(focusEngine.state) threshold=\(nudgeThreshold)s")
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
        // 2. System is NOT sleeping
        // 3. Current context is a focus context

        let shouldTrack = (focusEngine.state != .anchored) &&
                          !isSleeping &&
                          isFocusContextActive
        
        print("🕵️ [Shadow] updateTracking shouldTrack=\(shouldTrack) state=\(focusEngine.state) sleeping=\(isSleeping) isFocusCtx=\(isFocusContextActive) elapsed=\(continuousWorkTime)s")
        if shouldTrack {
            startTimerIfNeeded()
        } else {
            stopTimer()
            if focusEngine.currentClassification.isDistraction || focusEngine.state == .anchored {
                // Reset continuous time if they switch to a distraction app/domain or start a real session
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
        print("🕵️ [Shadow] tick elapsed=\(continuousWorkTime)s threshold=\(nudgeThreshold)s")
        if continuousWorkTime >= nudgeThreshold {
            print("🕵️ [Shadow] THRESHOLD CROSSED — firing onThresholdCrossed")
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
