import Foundation
import UserNotifications
import AppKit

final class SmartNudgeManager: NSObject, UNUserNotificationCenterDelegate {
    private let shadowEngine: ShadowTrackingEngine
    private let focusEngine: FocusEngine
    private let preferencesManager: PreferencesManager
    
    init(
        shadowEngine: ShadowTrackingEngine,
        focusEngine: FocusEngine,
        preferencesManager: PreferencesManager = .shared
    ) {
        self.shadowEngine = shadowEngine
        self.focusEngine = focusEngine
        self.preferencesManager = preferencesManager
        super.init()
        
        setupNudgeCallback()
        requestNotificationPermission()
        UNUserNotificationCenter.current().delegate = self
    }
    
    private func setupNudgeCallback() {
        shadowEngine.onThresholdCrossed = { [weak self] in
            self?.sendSmartNudge()
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("SmartNudgeManager Error: Notification permission request failed: \(error.localizedDescription)")
            } else {
                print("SmartNudgeManager: Notification permission granted: \(granted)")
            }
        }
    }
    
    private func sendSmartNudge() {
        let content = UNMutableNotificationContent()
        content.title = "Time to Focus?"
        content.body = "You've been working for 5 minutes. Ready to anchor your session?"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "com.varun.Anchored.nudge"
        
        let request = UNNotificationRequest(
            identifier: "com.varun.Anchored.smartnudge",
            content: content,
            trigger: nil // deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("SmartNudgeManager Error: Failed to add notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == "com.varun.Anchored.nudge" {
            // Clicking the notification starts a Focus Session via FocusEngine
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Anchor session for the user's default focus threshold
                let duration = self.preferencesManager.focusThreshold
                self.focusEngine.anchorSession(duration: duration)
                print("SmartNudgeManager: Programmatically started focus session for \(duration)s")
                
                // Bring app to front or activate if needed
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        completionHandler()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}
