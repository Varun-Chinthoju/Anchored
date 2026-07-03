import Foundation
import AppKit
import ApplicationServices

/// Errors that can occur during AppleScript compilation or execution.
public enum AppleScriptError: Error, Equatable {
    case compilationFailed
    case executionFailed(code: Int, message: String)
}

/// A protocol defining an interface for executing AppleScript source code.
public protocol AppleScriptExecutor {
    func execute(_ source: String) throws -> String
}

/// A concrete implementation of AppleScriptExecutor using NSAppleScript.
public class NSAppleScriptExecutor: AppleScriptExecutor {
    public init() {}
    
    public func execute(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError.compilationFailed
        }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let error = errorDict {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw AppleScriptError.executionFailed(code: code, message: message)
        }
        return result.stringValue ?? ""
    }
}

public struct BrowserContext: Equatable {
    public let title: String
    public let url: URL
    
    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

/// Protocol defining a strategy for retrieving the active browser context from a browser.
public protocol BrowserStrategy {
    /// The bundle identifier of the browser this strategy supports.
    var bundleIdentifier: String { get }
    
    /// Fetches the active context from the browser.
    /// - Returns: The active context if successfully retrieved, nil otherwise.
    func getActiveContext() -> BrowserContext?
}

/// Strategy for fetching the active context from Chromium-based browsers using AppleScript.
public class ChromiumBrowserStrategy: BrowserStrategy {
    public let bundleIdentifier: String
    public let appName: String
    private let executor: AppleScriptExecutor
    
    public init(bundleIdentifier: String, appName: String, executor: AppleScriptExecutor = NSAppleScriptExecutor()) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.executor = executor
    }
    
    public func getActiveContext() -> BrowserContext? {
        let scriptSource = """
        tell application "\(appName)"
            if window 1 exists then
                tell window 1
                    return (title of active tab) & "\\n" & (URL of active tab)
                end tell
            end if
        end tell
        """
        do {
            let response = try executor.execute(scriptSource).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !response.isEmpty else { return nil }
            
            let components = response.components(separatedBy: "\n")
            let title: String
            let urlString: String
            
            if components.count >= 2 {
                urlString = components.last!.trimmingCharacters(in: .whitespacesAndNewlines)
                title = components.dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if components.count == 1 {
                urlString = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                title = ""
            } else {
                return nil
            }
            
            guard !urlString.isEmpty, let url = URL(string: urlString), url.scheme != nil else { return nil }
            return BrowserContext(title: title, url: url)
        } catch {
            return nil
        }
    }
}

/// Delegate protocol for SafariBrowserStrategy to handle specific events.
public protocol SafariBrowserStrategyDelegate: AnyObject {
    /// Called when the Safari strategy detects that 'Allow JavaScript from Apple Events' is disabled.
    func safariBrowserStrategyDidDetectDisabledJavaScriptEvents(_ strategy: SafariBrowserStrategy)
}

/// Strategy for fetching the active URL from Safari, supporting JavaScript validation.
public class SafariBrowserStrategy: BrowserStrategy {
    public let bundleIdentifier = "com.apple.Safari"
    private let executor: AppleScriptExecutor
    
    public weak var delegate: SafariBrowserStrategyDelegate?
    public var onJavaScriptEventsDisabled: (() -> Void)?
    
    /// Tracks whether the warning callback/delegate has already been triggered.
    public var hasTriggeredWarning = false
    
    public init(executor: AppleScriptExecutor = NSAppleScriptExecutor()) {
        self.executor = executor
    }
    
    public func getActiveContext() -> BrowserContext? {
        // 1. Try to fetch URL and title using JavaScript execution first.
        // This is necessary to detect if "Allow JavaScript from Apple Events" is enabled/disabled.
        let jsScriptSource = """
        tell application "Safari"
            if window 1 exists then
                tell window 1
                    do JavaScript "document.title + '\\n' + window.location.href" in current tab
                end tell
            end if
        end tell
        """
        
        do {
            let response = try executor.execute(jsScriptSource).trimmingCharacters(in: .whitespacesAndNewlines)
            if !response.isEmpty, let context = parseResponse(response) {
                return context
            }
        } catch let error as AppleScriptError {
            switch error {
            case .executionFailed(let code, let message):
                // Safari returns error code 8 (or a descriptive message) if Apple Event JS is off.
                if code == 8 || message.contains("Allow JavaScript from Apple Events") {
                    handleDisabledJavaScript()
                }
            default:
                break
            }
        } catch {
            // General error
        }
        
        // 2. Fallback to standard URL and title property retrieval if JavaScript events are disabled.
        let fallbackScriptSource = """
        tell application "Safari"
            if window 1 exists then
                return (name of current tab of window 1) & "\\n" & (URL of current tab of window 1)
            end if
        end tell
        """
        
        do {
            let response = try executor.execute(fallbackScriptSource).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !response.isEmpty, let context = parseResponse(response) else { return nil }
            return context
        } catch {
            return nil
        }
    }
    
    private func parseResponse(_ response: String) -> BrowserContext? {
        let components = response.components(separatedBy: "\n")
        let title: String
        let urlString: String
        
        if components.count >= 2 {
            urlString = components.last!.trimmingCharacters(in: .whitespacesAndNewlines)
            title = components.dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else if components.count == 1 {
            urlString = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            title = ""
        } else {
            return nil
        }
        
        guard !urlString.isEmpty, let url = URL(string: urlString), url.scheme != nil else { return nil }
        return BrowserContext(title: title, url: url)
    }
    
    private func handleDisabledJavaScript() {
        guard !hasTriggeredWarning else { return }
        hasTriggeredWarning = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.safariBrowserStrategyDidDetectDisabledJavaScriptEvents(self)
            self.onJavaScriptEventsDisabled?()
        }
    }
}

/// Strategy for fetching the active URL from Firefox using the Accessibility API.
public class FirefoxBrowserStrategy: BrowserStrategy {
    public let bundleIdentifier = "org.mozilla.firefox"
    
    public init() {}
    
    public func getActiveContext() -> BrowserContext? {
        guard let firefoxApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        
        let appRef = AXUIElementCreateApplication(firefoxApp.processIdentifier)
        
        let targetWindow: AXUIElement
        var windowRef: AnyObject?
        let windowError = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        if windowError == .success, let activeWindow = windowRef {
            targetWindow = activeWindow as! AXUIElement
        } else {
            var windowsRef: AnyObject?
            let windowsError = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            guard windowsError == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
                return nil
            }
            targetWindow = windows[0]
        }
        
        var titleRef: AnyObject?
        let titleError = AXUIElementCopyAttributeValue(targetWindow, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleError == .success ? titleRef as? String : nil) ?? ""
        
        if let url = findURLInUIElement(targetWindow) {
            return BrowserContext(title: title, url: url)
        }
        return nil
    }
    
    private func findURLInUIElement(_ element: AXUIElement) -> URL? {
        var roleValue: AnyObject?
        let roleError = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if roleError == .success, let role = roleValue as? String {
            if role == kAXTextFieldRole {
                var valueRef: AnyObject?
                let valueError = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                if valueError == .success, let urlStr = valueRef as? String {
                    let trimmed = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        // Match address bar containing a URL-like value
                        if trimmed.contains("://") || trimmed.contains(".") {
                            let finalUrlStr = trimmed.contains("://") ? trimmed : "https://" + trimmed
                            if let url = URL(string: finalUrlStr), url.host != nil {
                                return url
                            }
                        }
                    }
                }
            }
        }
        
        var childrenRef: AnyObject?
        let childrenError = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard childrenError == .success, let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            if let url = findURLInUIElement(child) {
                return url
            }
        }
        
        return nil
    }
}

/// Registry factory to map browser bundle identifiers to their respective strategies.
public struct BrowserStrategyFactory {
    public static func strategy(for bundleIdentifier: String, executor: AppleScriptExecutor = NSAppleScriptExecutor()) -> BrowserStrategy? {
        switch bundleIdentifier {
        case "com.google.Chrome":
            return ChromiumBrowserStrategy(bundleIdentifier: bundleIdentifier, appName: "Google Chrome", executor: executor)
        case "company.thebrowser.Browser":
            return ChromiumBrowserStrategy(bundleIdentifier: bundleIdentifier, appName: "Arc", executor: executor)
        case "com.microsoft.edgemac":
            return ChromiumBrowserStrategy(bundleIdentifier: bundleIdentifier, appName: "Microsoft Edge", executor: executor)
        case "com.brave.Browser":
            return ChromiumBrowserStrategy(bundleIdentifier: bundleIdentifier, appName: "Brave Browser", executor: executor)
        case "com.apple.Safari":
            return SafariBrowserStrategy(executor: executor)
        case "org.mozilla.firefox":
            return FirefoxBrowserStrategy()
        default:
            return nil
        }
    }
    
    public static func isSupportedBrowser(_ bundleIdentifier: String) -> Bool {
        return strategy(for: bundleIdentifier) != nil
    }
}
