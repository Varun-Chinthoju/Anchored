import Foundation

/// Delegate protocol for receiving focus engine state transitions and events.
protocol FocusEngineDelegate: AnyObject {
    /// Called when the user has completed enough work to warrant anchoring a session,
    /// triggering the exit-trigger capsule panel.
    func didRequestExitTrigger(duration: TimeInterval, appName: String)
    
    /// Called when a distraction app is detected during an active focus session.
    func didDetectDistraction(bundleID: String)
    
    /// Called when the user returns to a work/neutral app, lifting any distraction overlay.
    func didReturnToWork()
    
    /// Called when the active session ends (e.g. timeout or manual end).
    func sessionDidEnd()
    
    /// Called when the permission gate for accessibility access should be displayed.
    func didRequestPermissionGate()

    /// Called when a committed break reaches its review deadline.
    func didRequestBreakReview(intention: String, result: BreakReviewResult)

    /// Called when a break request is made before the minimum focus period.
    func didRefuseBreak()
    
    /// Called when the focus engine needs to dim the screen immediately (e.g. failed declared activity check).
    func didRequestImmediateDim()
}
