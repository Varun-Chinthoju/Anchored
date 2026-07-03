import Foundation

/// A protocol defining the interface for monitoring foreground activity.
/// This acts as the seam for both app switch and URL monitoring.
protocol ActivityMonitor: AnyObject {
    /// Callback fired when the foreground context changes.
    /// - Parameter bundleID: The active application's bundle identifier.
    /// - Parameter url: The active URL, if applicable (nil in V1).
    var onContextChange: ((_ bundleID: String, _ url: URL?, _ title: String) -> Void)? { get set }
    
    /// Starts monitoring application switches.
    func start()
    
    /// Stops monitoring application switches.
    func stop()
}
