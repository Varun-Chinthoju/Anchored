import AppKit
import Foundation

/// Coordinator that links the FocusEngine delegate callbacks to the overlay windows and panels.
class OverlayManager: NSObject, FocusEngineDelegate {
    
    /// The associated focus engine instance.
    weak var focusEngine: FocusEngine?
    
    /// The currently active exit trigger panel, if any.
    var exitTriggerPanel: ExitTriggerPanel?
    
    /// The currently active countdown pill panel, if any.
    var countdownPillPanel: CountdownPillPanel?
    
    /// The currently active permission gate panel, if any.
    var permissionGatePanel: PermissionGatePanel?
    
    /// The currently active dim center panel, if any.
    var dimCenterPanel: DimCenterPanel?
    
    /// The active dim overlay windows (one per screen).
    var dimWindows: [DimOverlayWindow] = []
    private(set) var lastBreakReview: (intention: String, result: BreakReviewResult)?
    private(set) var refusedBreakCount = 0
    
    /// Configurable countdown duration in seconds. Clamped to the range 5-20.
    private var _countdownDuration: Int = 10
    var countdownDuration: Int {
        get { _countdownDuration }
        set { _countdownDuration = max(0, min(3600, newValue)) }
    }
    
    /// Initializes the OverlayManager.
    /// - Parameter focusEngine: The FocusEngine instance to wire callbacks to.
    init(focusEngine: FocusEngine? = nil) {
        self.focusEngine = focusEngine
        super.init()
        
        // Listen to screen parameter changes to adapt overlays to display changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - FocusEngineDelegate Conformance
    
    /// Callback from FocusEngine to request showing the exit-trigger capsule.
    func didRequestExitTrigger(duration: TimeInterval, appName: String) {
        RuntimeTrace.event("overlay_exit_trigger_requested", fields: ["duration": String(duration)])
        // Ensure only one exit-trigger capsule is shown at a time (debounce rapid app switches)
        dismissExitTrigger()
        
        // Play .pop sound feedback on capsule show
        AudioEngine.shared.play(.pop)
        
        let panel = ExitTriggerPanel()
        exitTriggerPanel = panel
        
        panel.show(duration: duration, appName: appName, onAnchor: { [weak self] chosenDuration in
            // Play .chime sound feedback on session anchor
            AudioEngine.shared.play(.chime)
            
            // Wire anchor click back to FocusEngine
            self?.focusEngine?.anchorSession(duration: chosenDuration)
            self?.dismissExitTrigger()
        }, onDismiss: { [weak self] in
            // Wire dismiss click back to FocusEngine
            self?.focusEngine?.dismissTrigger()
            self?.dismissExitTrigger()
        })
    }
    
    /// Callback from FocusEngine when distraction is detected during an active session.
    func didDetectDistraction(bundleID: String) {
        RuntimeTrace.event("overlay_countdown_requested", fields: ["bundleID": bundleID, "seconds": String(countdownDuration)])
        // Only allow one countdown/escalation sequence at a time
        guard countdownPillPanel == nil && dimWindows.isEmpty else { return }
        
        let pill = CountdownPillPanel()
        countdownPillPanel = pill
        
        pill.show(seconds: countdownDuration, onComplete: { [weak self] in
            // On expiry (0 seconds), trigger escalation on the DimOverlayWindow instances
            self?.startEscalation()
        }, onBreak: { [weak self] in
            self?.focusEngine?.requestBreak(intention: "Take a restorative break", bypassMinimum: true)
        })
    }
    
    func didRequestImmediateDim() {
        startEscalation()
    }
    
    /// Callback from FocusEngine when the user returns to work.
    func didReturnToWork() {
        RuntimeTrace.event("overlay_return_to_work")
        // Cancel the countdown pill if active
        if let pill = countdownPillPanel {
            pill.cancel()
            countdownPillPanel = nil
        }
        
        // Lift the dim overlays if active (fades out and removes them)
        liftDimOverlays()
    }
    
    /// Callback from FocusEngine when the active session ends.
    func sessionDidEnd() {
        RuntimeTrace.event("overlay_session_ended")
        // Hide all panels and overlays
        dismissExitTrigger()
        
        if let pill = countdownPillPanel {
            pill.cancel()
            countdownPillPanel = nil
        }
        
        if let gate = permissionGatePanel {
            gate.close()
            permissionGatePanel = nil
        }
        
        dismissDimCenterPanel()
        
        // Close dim windows immediately
        for window in dimWindows {
            window.close()
        }
        dimWindows.removeAll()
        lastBreakReview = nil
    }
    
    /// Callback from FocusEngine to request showing the Accessibility Permission Gate.
    func didRequestPermissionGate() {
        guard permissionGatePanel == nil else { return }
        
        let panel = PermissionGatePanel()
        permissionGatePanel = panel
        
        panel.show(onGrant: { [weak self] in
            // Trigger standard Accessibility prompt
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            
            // Backup action: open System Preferences directly to Privacy & Security -> Accessibility
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(settingsURL)
            }
            
            self?.permissionGatePanel = nil
        }, onDismiss: { [weak self] in
            self?.permissionGatePanel = nil
        })
    }

    func didRequestBreakReview(intention: String, result: BreakReviewResult) {
        lastBreakReview = (intention: intention, result: result)
        RuntimeTrace.event("overlay_break_review_requested", fields: [
            "outcome": String(describing: result.outcome),
            "enforcing": String(result.mayStartExistingCountdown)
        ])
    }

    func didRefuseBreak() {
        refusedBreakCount += 1
        RuntimeTrace.event("break_refused_under_minimum")
    }
    
    // MARK: - Helper Methods
    
    /// Triggers escalation, showing a dim overlay on all screens.
    private func startEscalation() {
        // Ensure we don't start duplicate escalations
        guard dimWindows.isEmpty else {
            RuntimeTrace.event("overlay_escalation_ignored_duplicate")
            return
        }

        RuntimeTrace.event("overlay_escalation_started", fields: ["screenCount": String(NSScreen.screens.count)])
        
        // Keep the status-level panel visible above the click-through dim layer so
        // the user can still choose a break or return through the menu bar.
        countdownPillPanel?.showDimmedState()
        
        // Create and show one dim window per connected screen
        for screen in NSScreen.screens {
            let window = DimOverlayWindow(screen: screen)
            window.makeKeyAndOrderFront(nil)
            window.startEscalation()
            dimWindows.append(window)
        }
        
        showDimCenterPanel()
    }
    
    /// Lifts the dim overlays by fading them out and closing them.
    private func liftDimOverlays() {
        RuntimeTrace.event("overlay_escalation_lifted", fields: ["screenCount": String(dimWindows.count)])
        for window in dimWindows {
            window.liftOverlay()
        }
        dimWindows.removeAll()
        
        dismissDimCenterPanel()
    }
    
    /// Closes and removes the current exit-trigger panel.
    private func dismissExitTrigger() {
        if let panel = exitTriggerPanel {
            panel.close()
            exitTriggerPanel = nil
        }
    }
    
    private func showDimCenterPanel() {
        dismissDimCenterPanel()
        
        let panel = DimCenterPanel()
        dimCenterPanel = panel
        
        panel.show(onBreak: { [weak self] in
            self?.focusEngine?.requestBreak(intention: "Take a restorative break", bypassMinimum: true)
        }, onCancel: { [weak self] in
            self?.focusEngine?.resumeSessionFromUI()
        }, onReturnToWork: { [weak self] in
            self?.focusEngine?.resumeSessionFromUI()
        }, onDeclareActivity: { [weak self] activity in
            self?.focusEngine?.startDeclaredActivityBypass(activity: activity)
        })
    }
    
    private func dismissDimCenterPanel() {
        if let panel = dimCenterPanel {
            panel.closePanel()
            dimCenterPanel = nil
        }
    }
    
    /// Responds to changes in display configuration.
    @objc private func handleScreenParametersChanged(_ notification: Notification) {
        // If we are currently escalated/dimming, adjust overlay windows to cover the new screen configuration
        guard !dimWindows.isEmpty else { return }
        
        // We can capture the current state/alpha value from one of the active windows
        let maxAlpha = CGFloat(PreferencesManager.shared.dimOpacity)
        let currentAlpha = dimWindows.first?.alphaValue ?? maxAlpha
        
        // Close current windows
        for window in dimWindows {
            window.close()
        }
        dimWindows.removeAll()
        
        // Recreate overlay windows on all connected screens at the current alpha level
        for screen in NSScreen.screens {
            let window = DimOverlayWindow(screen: screen)
            window.alphaValue = currentAlpha
            window.makeKeyAndOrderFront(nil)
            
            // If it wasn't fully dimmed yet, we can continue escalation animation
            if currentAlpha < window.maxAlpha {
                window.startEscalation()
            }
            dimWindows.append(window)
        }
    }
}
