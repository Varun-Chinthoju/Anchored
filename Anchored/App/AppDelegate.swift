import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var appSwitchMonitor: AppSwitchMonitor?
    private var focusEngine: FocusEngine?
    private var overlayManager: OverlayManager?
    private var menuBarController: MenuBarController?
    private var onboardingWindow: OnboardingWindow?
    private var preferencesCancellables = Set<AnyCancellable>()
    private var shadowTrackingEngine: ShadowTrackingEngine?
    private var smartNudgeManager: SmartNudgeManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            startStandardFlow()
        } else {
            showOnboardingFlow()
        }
    }
    
    private func startStandardFlow() {
        appSwitchMonitor = AppSwitchMonitor()
        let prefs = PreferencesManager.shared
        
        let listManager = DistractionListManager.shared
        let engine = FocusEngine(
            activityMonitor: appSwitchMonitor!,
            distractionListManager: listManager,
            sessionStore: .shared,
            focusThreshold: prefs.focusThreshold          // Read from user preferences
        )
        focusEngine = engine
        
        // Keep engine in sync when the user changes settings
        prefs.$focusThreshold
            .dropFirst()
            .sink { [weak engine] newThreshold in
                engine?.focusThreshold = newThreshold
                print("FocusEngine: threshold updated to \(newThreshold)s")
            }
            .store(in: &preferencesCancellables)
        
        prefs.$countdownDuration
            .dropFirst()
            .sink { [weak engine] newDuration in
                engine?.distractionCountdownThreshold = TimeInterval(newDuration)
                print("FocusEngine: countdown updated to \(newDuration)s")
            }
            .store(in: &preferencesCancellables)
        
        let overlay = OverlayManager(focusEngine: engine)
        overlayManager = overlay
        engine.delegate = overlay
        
        menuBarController = MenuBarController(focusEngine: engine)
        
        let shadowEngine = ShadowTrackingEngine(focusEngine: engine, preferencesManager: prefs)
        self.shadowTrackingEngine = shadowEngine
        self.smartNudgeManager = SmartNudgeManager(shadowEngine: shadowEngine, focusEngine: engine, preferencesManager: prefs)
        
        engine.start()
        print("FocusEngine started (focusThreshold: \(prefs.focusThreshold)s, countdown: \(prefs.countdownDuration)s)")
    }
    
    private func showOnboardingFlow() {
        let window = OnboardingWindow { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            self.onboardingWindow = nil
            self.startStandardFlow()
        }
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        focusEngine?.stop()
    }
}
