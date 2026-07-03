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
        // Reset key for onboarding testing
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        setupMainMenu()
        showOnboardingFlow()
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
        
        // Re-setup main menu with menuBarController target populated
        setupMainMenu()
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
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // 1. App Menu ("Anchored")
        let appMenu = NSMenu(title: "Anchored")
        appMenu.addItem(withTitle: "About the Vessel (About Anchored)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "Ship Rigging (Preferences)...", action: #selector(MenuBarController.openPreferences), keyEquivalent: ",")
        prefsItem.target = menuBarController
        appMenu.addItem(prefsItem)
        
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Vessel", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Scuttle the Ship (Quit)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. Voyage Menu ("Voyage")
        let voyageMenu = NSMenu(title: "Voyage")
        
        let startItem = NSMenuItem(title: "Set Sail (Start Session)...", action: #selector(MenuBarController.startSessionClicked), keyEquivalent: "s")
        startItem.target = menuBarController
        voyageMenu.addItem(startItem)
        
        let endItem = NSMenuItem(title: "Abandon Voyage (Mutiny!)", action: #selector(MenuBarController.endSessionClicked), keyEquivalent: "w")
        endItem.target = menuBarController
        voyageMenu.addItem(endItem)
        
        voyageMenu.addItem(NSMenuItem.separator())
        
        let logItem = NSMenuItem(title: "Peer into Captain's Log (Dashboard)...", action: #selector(MenuBarController.openDashboard), keyEquivalent: "d")
        logItem.target = menuBarController
        voyageMenu.addItem(logItem)
        
        let voyageMenuItem = NSMenuItem()
        voyageMenuItem.submenu = voyageMenu
        mainMenu.addItem(voyageMenuItem)
        
        // 3. Edit Menu ("Edit")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 4. Window Menu ("Window")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        focusEngine?.stop()
    }
}
