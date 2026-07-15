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
    
    /// The doomscroll loop-breaker panel, if active.
    var doomscrollBreakerPanel: DoomscrollBreakerPanel?
    
    /// The active dim overlay window for the display containing the distraction.
    var dimWindows: [DimOverlayWindow] = []
    private let distractionContextCloser: DistractionContextClosing
    private let preferencesManager: PreferencesManager
    private var activeDistractionBundleID: String?
    private var dimmedDisplayID: NSNumber?
    private var pendingDimCenterPanelReveal: DispatchWorkItem?
    private(set) var lastBreakReview: (intention: String, result: BreakReviewResult)?
    private(set) var refusedBreakCount = 0
    private let dimCenterRevealBuffer: TimeInterval = 0.15
    
    /// Configurable countdown duration in seconds. Clamped to the range 0-3600.
    private var _countdownDuration: Int = 30
    var countdownDuration: Int {
        get { _countdownDuration }
        set { _countdownDuration = max(0, min(3600, newValue)) }
    }
    
    /// Initializes the OverlayManager.
    /// - Parameter focusEngine: The FocusEngine instance to wire callbacks to.
    init(
        focusEngine: FocusEngine? = nil,
        distractionContextCloser: DistractionContextClosing = DistractionContextCloser(),
        preferencesManager: PreferencesManager = .shared
    ) {
        self.focusEngine = focusEngine
        self.distractionContextCloser = distractionContextCloser
        self.preferencesManager = preferencesManager
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
        activeDistractionBundleID = bundleID
        let graceSeconds = focusEngine?.currentDistractionGraceRemaining ?? TimeInterval(countdownDuration)
        let seconds = max(0, Int(ceil(graceSeconds)))
        RuntimeTrace.event("overlay_countdown_requested", fields: ["bundleID": bundleID, "seconds": String(seconds)])
        // Only allow one countdown/escalation sequence at a time
        guard countdownPillPanel == nil && dimWindows.isEmpty else { return }
        guard seconds > 0 else {
            startEscalation()
            return
        }

        guard preferencesManager.showCountdownPill else {
            return
        }
        
        let pill = CountdownPillPanel()
        countdownPillPanel = pill
        
        pill.show(seconds: seconds, onComplete: { [weak self] in
            // On expiry (0 seconds), trigger escalation on the DimOverlayWindow instances
            self?.startEscalation()
        }, onBreak: { [weak self] in
            self?.focusEngine?.requestBreak(intention: "Take a restorative break", bypassMinimum: true)
        })
    }
    
    func didRequestImmediateDim() {
        activeDistractionBundleID = focusEngine?.currentApp
        startEscalation()
    }
    
    /// Callback from FocusEngine when the user returns to work.
    func didReturnToWork() {
        RuntimeTrace.event("overlay_return_to_work")
        // Dismiss any doomscroll breaker panel
        dismissDoomscrollBreakerPanel()
        cancelPendingDimCenterPanelReveal()
        // Cancel the countdown pill if active
        if let pill = countdownPillPanel {
            pill.cancel()
            countdownPillPanel = nil
        }
        
        // Lift the dim overlays if active (fades out and removes them)
        liftDimOverlays()
        activeDistractionBundleID = nil
    }
    
    /// Callback from FocusEngine when the active session ends.
    func sessionDidEnd() {
        RuntimeTrace.event("overlay_session_ended")
        // Hide all panels and overlays
        dismissExitTrigger()
        dismissDoomscrollBreakerPanel()
        cancelPendingDimCenterPanelReveal()
        
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
        activeDistractionBundleID = nil
        dimmedDisplayID = nil
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
    
    func didDetectDoomscrolling(bundleID: String, threshold: TimeInterval) {
        activeDistractionBundleID = bundleID
        RuntimeTrace.event("overlay_doomscroll_breaker_requested", fields: ["bundleID": bundleID, "threshold": String(threshold)])
        guard doomscrollBreakerPanel == nil else { return }
        
        AudioEngine.shared.play(.pop)
        
        let panel = DoomscrollBreakerPanel()
        doomscrollBreakerPanel = panel
        
        panel.show(
            threshold: threshold,
            onDim: { [weak self] in
                self?.doomscrollBreakerPanel = nil
                self?.startDoomscrollDim()
            },
            onStartFocus: { [weak self] in
                self?.doomscrollBreakerPanel = nil
                // Treat like a manual focus trigger from menu bar
                self?.focusEngine?.anchorSession(duration: self?.preferencesManager.automaticSessionDuration ?? PreferencesManager.shared.automaticSessionDuration)
            },
            onDismiss: { [weak self] in
                self?.doomscrollBreakerPanel = nil
            }
        )
    }
    
    // MARK: - Helper Methods
    
    /// Triggers escalation on the display containing the distracting window.
    private func startEscalation() {
        // Ensure we don't start duplicate escalations
        guard dimWindows.isEmpty else {
            RuntimeTrace.event("overlay_escalation_ignored_duplicate")
            return
        }

        guard let screen = targetScreen() else { return }
        RuntimeTrace.event("overlay_escalation_started", fields: ["screenCount": "1"])
        
        // Keep the status-level panel visible above the click-through dim layer so
        // the user can still choose a break or return through the menu bar.
        countdownPillPanel?.showDimmedState()

        showDimOverlay(on: screen)
        scheduleDimCenterPanelReveal(delay: preferencesManager.dimTransitionDuration + dimCenterRevealBuffer) { [weak self] in
            self?.showDimCenterPanel(on: screen)
        }
    }
    
    /// Lifts the dim overlays by fading them out and closing them.
    private func liftDimOverlays() {
        cancelPendingDimCenterPanelReveal()
        RuntimeTrace.event("overlay_escalation_lifted", fields: ["screenCount": String(dimWindows.count)])
        for window in dimWindows {
            window.liftOverlay()
        }
        dimWindows.removeAll()
        dimmedDisplayID = nil
        
        dismissDimCenterPanel()
    }
    
    /// Closes and removes the current exit-trigger panel.
    private func dismissExitTrigger() {
        if let panel = exitTriggerPanel {
            panel.close()
            exitTriggerPanel = nil
        }
    }
    
    private func dismissDoomscrollBreakerPanel() {
        if let panel = doomscrollBreakerPanel {
            panel.closePanel()
            doomscrollBreakerPanel = nil
        }
    }
    
    /// Starts a temporary dim for the doomscroll loop-breaker (no session enforcement).
    private func startDoomscrollDim() {
        guard dimWindows.isEmpty else { return }
        guard let screen = targetScreen() else { return }
        RuntimeTrace.event("doomscroll_dim_started")
        showDimOverlay(on: screen)
        // Show a lightweight center panel for the doomscroll dim state
        scheduleDimCenterPanelReveal(delay: preferencesManager.dimTransitionDuration + dimCenterRevealBuffer) { [weak self] in
            self?.showDoomscrollDimCenterPanel(on: screen)
        }
    }
    
    private func showDoomscrollDimCenterPanel(on screen: NSScreen) {
        dismissDimCenterPanel()
        let panel = DimCenterPanel()
        dimCenterPanel = panel
        // Re-use the existing DimCenterView; "Return to Work" and "Cancel" both lift the dim
        panel.show(
            on: screen,
            suggestedActivity: nil,
            onBreak: { [weak self] in
                // Break requested from doomscroll dim: just lift the dim (no active session to pause)
                self?.liftDimOverlays()
            },
            onCancel: { [weak self] in
                self?.liftDimOverlays()
            },
            onReturnToWork: { [weak self] in
                self?.liftDimOverlays()
            },
            onDeclareActivity: { [weak self] _ in
                self?.liftDimOverlays()
            },
            onExitSession: { [weak self] _ in
                self?.liftDimOverlays()
            }
        )
    }
    
    private func showDimCenterPanel(on screen: NSScreen) {
        dismissDimCenterPanel()
        
        let panel = DimCenterPanel()
        dimCenterPanel = panel
        
        panel.show(
            on: screen,
            suggestedActivity: focusEngine?.suggestedSessionGoal(),
            onBreak: { [weak self] in
                self?.focusEngine?.requestBreak(intention: "Take a restorative break", bypassMinimum: true)
            },
            onCancel: { [weak self] in
                self?.focusEngine?.resumeSessionFromUI()
            },
            onReturnToWork: { [weak self] in
                self?.focusEngine?.resumeSessionFromUI()
            },
            onDeclareActivity: { [weak self] activity in
                self?.closeActiveDistractionContext { [weak self] in
                    self?.focusEngine?.startDeclaredActivityBypass(activity: activity)
                }
            },
            onExitSession: { [weak self] summary in
                self?.focusEngine?.endSession(action: .dismissed, completionOutcome: nil, summary: summary)
            }
        )
    }
    
    private func dismissDimCenterPanel() {
        if let panel = dimCenterPanel {
            panel.closePanel()
            dimCenterPanel = nil
        }
    }

    private func cancelPendingDimCenterPanelReveal() {
        pendingDimCenterPanelReveal?.cancel()
        pendingDimCenterPanelReveal = nil
    }

    private func scheduleDimCenterPanelReveal(delay: TimeInterval, reveal: @escaping () -> Void) {
        cancelPendingDimCenterPanelReveal()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.dimWindows.isEmpty else { return }
            reveal()
            self.pendingDimCenterPanelReveal = nil
        }
        pendingDimCenterPanelReveal = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: workItem)
    }

    private func closeActiveDistractionContext(completion: @escaping () -> Void) {
        guard let bundleID = activeDistractionBundleID else {
            completion()
            return
        }
        activeDistractionBundleID = nil
        distractionContextCloser.closeContext(bundleID: bundleID, completion: completion)
    }

    private func targetScreen() -> NSScreen? {
        if let dimmedDisplayID,
           let existingScreen = screen(for: dimmedDisplayID) {
            return existingScreen
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        dimmedDisplayID = screen.flatMap(displayID(for:))
        return screen
    }

    private func showDimOverlay(on screen: NSScreen) {
        let window = DimOverlayWindow(screen: screen)
        window.orderFront(nil)
        window.startEscalation()
        dimWindows.append(window)
    }

    private func displayID(for screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private func screen(for targetDisplayID: NSNumber) -> NSScreen? {
        NSScreen.screens.first { displayID(for: $0) == targetDisplayID }
    }
    
    /// Responds to changes in display configuration.
    @objc private func handleScreenParametersChanged(_ notification: Notification) {
        // If we are currently escalated/dimming, adjust overlay windows to cover the new screen configuration
        guard !dimWindows.isEmpty else { return }
        
        // We can capture the current state/alpha value from one of the active windows
        let maxAlpha = CGFloat(preferencesManager.dimOpacity)
        let currentAlpha = dimWindows.first?.alphaValue ?? maxAlpha
        
        // Close current windows
        for window in dimWindows {
            window.close()
        }
        dimWindows.removeAll()
        
        guard let screen = targetScreen() else { return }
        let window = DimOverlayWindow(screen: screen)
        window.alphaValue = currentAlpha
        window.orderFront(nil)
        if currentAlpha < window.maxAlpha {
            window.startEscalation()
        }
        dimWindows.append(window)
    }
}
