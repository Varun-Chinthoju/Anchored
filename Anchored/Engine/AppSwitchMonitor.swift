import AppKit
import ApplicationServices

/// Monitors application switch events via `NSWorkspace.didActivateApplicationNotification`
/// and publishes the active application's bundle identifier and browser URL asynchronously.
final class AppSwitchMonitor: ActivityMonitor {
    /// Callback invoked when a context change is detected.
    var onContextChange: ((ContextSnapshot) -> Void)?
    
    private let collector: ContextCollecting
    private var observer: NSObjectProtocol?
    private var isMonitoring = false
    
    // Polling properties
    private var pollingTimer: Timer?
    private var activeBundleID: String?
    private var lastPolledIdentity: ContextIdentity?
    
    init(collector: ContextCollecting = ContextCollector()) {
        self.collector = collector
    }
    
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
    
    /// Stops monitoring, removes notification observers, and cancels polling.
    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        cancelPollingTimer()
        activeBundleID = nil
        lastPolledIdentity = nil
        
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }
    
    func handleApplicationActivation(bundleID: String) {
        activeBundleID = bundleID
        pollActiveContext()
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
        
        collector.collectContext(for: bundleID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.isMonitoring, self.activeBundleID == bundleID else { return }
                
                switch result {
                case .success(let snapshot):
                    let newIdentity = snapshot.identity
                    if newIdentity != self.lastPolledIdentity {
                        self.lastPolledIdentity = newIdentity
                        self.onContextChange?(snapshot)
                    }
                case .failure:
                    // Fallback to empty snapshot for the active bundle ID
                    let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })
                    let localizedName = runningApp?.localizedName ?? ""
                    let fallbackSnapshot = ContextSnapshot(
                        bundleIdentifier: bundleID,
                        localizedName: localizedName,
                        url: nil,
                        title: "",
                        source: .application,
                        observedAt: Date()
                    )
                    let fallbackIdentity = fallbackSnapshot.identity
                    if fallbackIdentity != self.lastPolledIdentity {
                        self.lastPolledIdentity = fallbackIdentity
                        self.onContextChange?(fallbackSnapshot)
                    }
                }
            }
        }
    }
    
    deinit {
        stop()
    }
}
