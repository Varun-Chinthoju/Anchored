import AppKit
import ApplicationServices

/// Monitors application switch events via `NSWorkspace.didActivateApplicationNotification`
/// and publishes the active application's bundle identifier and browser URL, if applicable.
final class AppSwitchMonitor: ActivityMonitor {
    /// Callback invoked when a context change is detected.
    var onContextChange: ((_ bundleID: String, _ url: URL?, _ title: String) -> Void)?
    
    private var observer: NSObjectProtocol?
    private var isMonitoring = false
    
    // URL and Window Polling properties
    private var pollingTimer: Timer?
    private var activeBundleID: String?
    private var lastPolledURL: URL?
    private var lastPolledTitle = ""
    
    init() {}
    
    /// Starts monitoring application switch notifications and initializes browser URL and window polling.
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
        
        startPollingTimer()
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
        activeBundleID = bundleID
        
        if BrowserStrategyFactory.isSupportedBrowser(bundleID) {
            if AXIsProcessTrusted() {
                // Fetch current URL immediately
                let strategy = BrowserStrategyFactory.strategy(for: bundleID)
                let context = strategy?.getActiveContext()
                let currentURL = context?.url
                let title = (context?.title.isEmpty == false) ? context!.title : getNativeWindowTitle(for: bundleID)
                lastPolledURL = currentURL
                lastPolledTitle = title
                onContextChange?(bundleID, currentURL, title)
            } else {
                lastPolledURL = nil
                lastPolledTitle = ""
                onContextChange?(bundleID, nil, "")
            }
        } else {
            lastPolledURL = nil
            let title = getNativeWindowTitle(for: bundleID)
            lastPolledTitle = title
            onContextChange?(bundleID, nil, title)
        }
    }
    
    private func startPollingTimer() {
        cancelPollingTimer()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollActiveContext()
        }
    }
    
    private func cancelPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func pollActiveContext() {
        guard let bundleID = activeBundleID else { return }
        
        if BrowserStrategyFactory.isSupportedBrowser(bundleID) {
            guard AXIsProcessTrusted() else { return }
            let strategy = BrowserStrategyFactory.strategy(for: bundleID)
            let context = strategy?.getActiveContext()
            let currentURL = context?.url
            let title = (context?.title.isEmpty == false) ? context!.title : getNativeWindowTitle(for: bundleID)
            
            if currentURL != lastPolledURL || title != lastPolledTitle {
                lastPolledURL = currentURL
                lastPolledTitle = title
                onContextChange?(bundleID, currentURL, title)
            }
        } else {
            let title = getNativeWindowTitle(for: bundleID)
            if title != lastPolledTitle {
                lastPolledURL = nil
                lastPolledTitle = title
                onContextChange?(bundleID, nil, title)
            }
        }
    }
    
    deinit {
        stop()
    }
}
