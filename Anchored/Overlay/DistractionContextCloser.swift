import AppKit
import ApplicationServices
import Foundation

/// Closes the tab or window that was active when distraction escalation began.
protocol DistractionContextClosing: AnyObject {
    func closeContext(bundleID: String, completion: @escaping () -> Void)
}

final class DistractionContextCloser: DistractionContextClosing {
    private let appleEventExecutor: AppleEventExecuting
    private let closeFocusedWindow: (String) -> Bool

    init(
        appleEventExecutor: AppleEventExecuting = AppleEventExecutor(),
        closeFocusedWindow: @escaping (String) -> Bool = DistractionContextCloser.closeFocusedWindow
    ) {
        self.appleEventExecutor = appleEventExecutor
        self.closeFocusedWindow = closeFocusedWindow
    }

    func closeContext(bundleID: String, completion: @escaping () -> Void) {
        guard let script = Self.closeTabScript(for: bundleID) else {
            recordWindowClose(bundleID: bundleID)
            Self.completeOnMain(completion)
            return
        }

        appleEventExecutor.execute(script, timeout: 0.75) { [weak self] result in
            switch result {
            case .success:
                RuntimeTrace.event("distraction_context_closed", fields: ["bundleID": bundleID, "kind": "tab"])
            case .failure:
                self?.recordWindowClose(bundleID: bundleID)
            }
            Self.completeOnMain(completion)
        }
    }

    private static func completeOnMain(_ completion: @escaping () -> Void) {
        if Thread.isMainThread {
            completion()
        } else {
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func recordWindowClose(bundleID: String) {
        let didClose = closeFocusedWindow(bundleID)
        RuntimeTrace.event(
            didClose ? "distraction_context_closed" : "distraction_context_close_unavailable",
            fields: ["bundleID": bundleID, "kind": "window"]
        )
    }

    private static func closeTabScript(for bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari":
            return """
            tell application id "com.apple.Safari"
                if exists front window then
                    close current tab of front window
                end if
            end tell
            """
        case "com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser":
            return """
            tell application id "\(bundleID)"
                if exists front window then
                    close active tab of front window
                end if
            end tell
            """
        default:
            return nil
        }
    }

    private static func closeFocusedWindow(bundleID: String) -> Bool {
        let close = {
            guard AXIsProcessTrusted(),
                  let application = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })
            else {
                return false
            }

            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            guard let window = AccessibilityValue.element(
                from: AccessibilityValue.copy(kAXFocusedWindowAttribute as CFString, from: appElement)
            ), let closeButton = AccessibilityValue.element(
                from: AccessibilityValue.copy(kAXCloseButtonAttribute as CFString, from: window)
            ) else {
                return false
            }

            return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
        }

        if Thread.isMainThread {
            return close()
        }

        return DispatchQueue.main.sync(execute: close)
    }
}
