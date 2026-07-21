import Foundation
import UserNotifications
import AppKit

final class SmartNudgeManager: NSObject, UNUserNotificationCenterDelegate {
    private let shadowEngine: ShadowTrackingEngine
    private let focusEngine: FocusEngine
    private let preferencesManager: PreferencesManager
    private let sessionStore: SessionStore
    
    init(
        shadowEngine: ShadowTrackingEngine,
        focusEngine: FocusEngine,
        preferencesManager: PreferencesManager = .shared,
        sessionStore: SessionStore = .shared
    ) {
        self.shadowEngine = shadowEngine
        self.focusEngine = focusEngine
        self.preferencesManager = preferencesManager
        self.sessionStore = sessionStore
        super.init()
        
        setupNudgeCallback()
        if preferencesManager.enableSmartNudges {
            requestNotificationPermission()
        }
        UNUserNotificationCenter.current().delegate = self
    }
    
    private func setupNudgeCallback() {
        shadowEngine.onThresholdCrossed = { [weak self] in
            guard let self = self else { return }
            
            self.sessionStore.fetchAllEvents { [weak self] events in
                guard let self else { return }
                guard self.focusEngine.currentClassification.isFocus,
                      self.focusEngine.canAutoStartFocusSession else { return }

                let duration = AutomaticDurationRecommendation.recommendedDuration(
                    from: events,
                    fallback: self.preferencesManager.automaticSessionDuration
                )
                let activeProfileName = ProfileManager.shared.activeProfile.name
                self.focusEngine.anchorSession(duration: duration, category: activeProfileName, goal: "Auto-chartered Voyage")

                // Alert the user via a local notification
                if self.preferencesManager.enableSmartNudges {
                    self.sendAutoAnchorNotification()
                }
            }
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
    
    private func sendAutoAnchorNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Voyage Automatically Anchored"
        content.body = "Anchored detected sustained focus and automatically started a session."
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "com.varun.Anchored.autoanchor"
        
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
        if response.notification.request.content.categoryIdentifier == "com.varun.Anchored.autoanchor" {
            DispatchQueue.main.async {
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
