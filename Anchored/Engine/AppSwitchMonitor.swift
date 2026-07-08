import AppKit
import ApplicationServices

/// Monitors application switch events via `NSWorkspace.didActivateApplicationNotification`
/// and publishes the active application's bundle identifier and browser URL, if applicable.
final class AppSwitchMonitor: ActivityMonitor {
    /// Callback invoked when a context change is detected.
    var onContextChange: ((_ bundleID: String, _ url: URL?, _ title: String) -> Void)?
    
    private var observer: NSObjectProtocol?
    private var isMonitoring = false
    
    // URL Polling properties
    private var pollingTimer: Timer?
    private var activeBrowserBundleID: String?
    private var lastPolledURL: URL?
    private var lastPolledTitle = ""
    
    init() {}
    
    /// Starts monitoring application switch notifications and initializes browser URL polling.
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            guard let bundleID = app.bundleIdentifier else {
                return
            }
            self.handleApplicationActivation(bundleID: bundleID)
        }
        
        // Handle the current frontmost application immediately on start
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontApp.bundleIdentifier {
            handleApplicationActivation(bundleID: bundleID)
        }
    }
    
    /// Stops monitoring and removes notification observers.
    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        cancelPollingTimer()
        
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }
    
    private func getNativeWindowTitle(for bundleID: String) -> String {
        guard AXIsProcessTrusted() else {
            return ""
        }
        
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return ""
        }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        var windowRef: AnyObject?
        let windowError = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard windowError == .success, let activeWindow = windowRef else {
            return ""
        }
        
        var titleRef: AnyObject?
        let titleError = AXUIElementCopyAttributeValue(activeWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
        guard titleError == .success, let title = titleRef as? String else {
            return ""
        }
        
        return title
    }

    private func handleApplicationActivation(bundleID: String) {
        cancelPollingTimer()
        
        if BrowserStrategyFactory.isSupportedBrowser(bundleID) {
            activeBrowserBundleID = bundleID
            
            if AXIsProcessTrusted() {
                // Fetch current URL immediately
                let strategy = BrowserStrategyFactory.strategy(for: bundleID)
                let context = strategy?.getActiveContext()
                let currentURL = context?.url
                let title = context?.title ?? ""
                lastPolledURL = currentURL
                lastPolledTitle = title
                onContextChange?(bundleID, currentURL, title)
                
                // Start background 2.5-second polling timer
                startPollingTimer()
            } else {
                // Treat browser as neutral since accessibility isn't granted
                onContextChange?(bundleID, nil, "")
            }
        } else {
            activeBrowserBundleID = nil
            lastPolledURL = nil
            lastPolledTitle = ""
            let title = getNativeWindowTitle(for: bundleID)
            onContextChange?(bundleID, nil, title)
        }
    }
    
    private func startPollingTimer() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.pollActiveBrowser()
        }
    }
    
    private func cancelPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func pollActiveBrowser() {
        guard let bundleID = activeBrowserBundleID,
              AXIsProcessTrusted() else {
            cancelPollingTimer()
            return
        }
        
        let strategy = BrowserStrategyFactory.strategy(for: bundleID)
        let context = strategy?.getActiveContext()
        let currentURL = context?.url
        let title = context?.title ?? ""
        
        if currentURL != lastPolledURL || title != lastPolledTitle {
            lastPolledURL = currentURL
            lastPolledTitle = title
            onContextChange?(bundleID, currentURL, title)
        }
    }
    
    deinit {
        stop()
    }
}
