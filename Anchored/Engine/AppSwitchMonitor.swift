import AppKit

/// Monitors application switch events via `NSWorkspace.didActivateApplicationNotification`
/// and publishes the active application's bundle identifier.
final class AppSwitchMonitor: ActivityMonitor {
    /// Callback invoked when a context change is detected.
    var onContextChange: ((_ bundleID: String, _ url: URL?) -> Void)?
    
    private var observer: NSObjectProtocol?
    private var isMonitoring = false
    
    init() {}
    
    /// Starts monitoring application switch notifications.
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
            // In V1, URL is always nil.
            self.onContextChange?(bundleID, nil)
        }
    }
    
    /// Stops monitoring and removes notification observers.
    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }
    
    deinit {
        stop()
    }
}
