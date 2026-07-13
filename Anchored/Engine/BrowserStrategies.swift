import Foundation
import AppKit
import ApplicationServices

public struct BrowserContext: Equatable {
    public let title: String
    public let url: URL
    
    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

/// Protocol defining a strategy for retrieving the active browser context from a browser asynchronously.
public protocol BrowserStrategy {
    /// The bundle identifier of the browser this strategy supports.
    var bundleIdentifier: String { get }
    
    /// Fetches the active context from the browser.
    func getActiveContext(completion: @escaping (Result<BrowserContext, CollectionError>) -> Void)
}

/// Strategy for fetching the active context from Chromium-based browsers using AppleScript.
public class ChromiumBrowserStrategy: BrowserStrategy {
    public let bundleIdentifier: String
    public let appName: String
    private let executor: AppleEventExecuting
    
    public init(bundleIdentifier: String, appName: String, executor: AppleEventExecuting = AppleEventExecutor()) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.executor = executor
    }
    
    public func getActiveContext(completion: @escaping (Result<BrowserContext, CollectionError>) -> Void) {
        let scriptSource = """
        tell application "\(appName)"
            if window 1 exists then
                tell window 1
                    return (title of active tab) & "\\n" & (URL of active tab)
                end tell
            end if
        end tell
        """
        executor.execute(scriptSource, timeout: 0.75) { result in
            switch result {
            case .success(let response):
                let responseTrimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !responseTrimmed.isEmpty else {
                    self.executeAccessibilityFallback(completion: completion, originalError: .execFailed("Empty response from browser"))
                    return
                }
                
                let components = responseTrimmed.components(separatedBy: "\n")
                let title: String
                let urlString: String
                
                if components.count >= 2 {
                    urlString = components.last!.trimmingCharacters(in: .whitespacesAndNewlines)
                    title = components.dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if components.count == 1 {
                    urlString = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    title = ""
                } else {
                    self.executeAccessibilityFallback(completion: completion, originalError: .execFailed("Invalid script output format"))
                    return
                }
                
                guard !urlString.isEmpty, let url = URL(string: urlString), url.scheme != nil else {
                    self.executeAccessibilityFallback(completion: completion, originalError: .execFailed("Invalid URL string: \(urlString)"))
                    return
                }
                
                completion(.success(BrowserContext(title: title, url: url)))
                
            case .failure(let error):
                let mappedError: CollectionError
                switch error {
                case .timedOut:
                    mappedError = .timedOut
                case .execFailed(let msg):
                    mappedError = .execFailed(msg)
                }
                self.executeAccessibilityFallback(completion: completion, originalError: mappedError)
            }
        }
    }
    
    private func executeAccessibilityFallback(
        completion: @escaping (Result<BrowserContext, CollectionError>) -> Void,
        originalError: CollectionError
    ) {
        AccessibilityBrowserHelper.getActiveContext(bundleIdentifier: bundleIdentifier) { result in
            switch result {
            case .success(let context):
                completion(.success(context))
            case .failure:
                completion(.failure(originalError))
            }
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
    private let executor: AppleEventExecuting
    
    public weak var delegate: SafariBrowserStrategyDelegate?
    public var onJavaScriptEventsDisabled: (() -> Void)?
    
    /// Tracks whether the warning callback/delegate has already been triggered.
    public var hasTriggeredWarning = false
    
    public init(executor: AppleEventExecuting = AppleEventExecutor()) {
        self.executor = executor
    }
    
    public func getActiveContext(completion: @escaping (Result<BrowserContext, CollectionError>) -> Void) {
        // Try JS script first
        let jsScriptSource = """
        tell application "Safari"
            if window 1 exists then
                tell window 1
                    do JavaScript "document.title + '\\n' + window.location.href" in current tab
                end tell
            end if
        end tell
        """
        
        executor.execute(jsScriptSource, timeout: 0.75) { result in
            switch result {
            case .success(let response):
                let responseTrimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                if !responseTrimmed.isEmpty, let context = self.parseResponse(responseTrimmed) {
                    completion(.success(context))
                } else {
                    self.executeFallback(completion: completion, originalError: .execFailed("JS empty/invalid response"))
                }
                
            case .failure(let error):
                let mappedError: CollectionError
                switch error {
                case .timedOut:
                    mappedError = .timedOut
                case .execFailed(let msg):
                    mappedError = .execFailed(msg)
                    if msg.contains("Allow JavaScript from Apple Events") || msg.contains("errAEEventNotAllowed") || msg.contains("code 8") {
                        self.handleDisabledJavaScript()
                    }
                }
                self.executeFallback(completion: completion, originalError: mappedError)
            }
        }
    }
    
    private func executeFallback(
        completion: @escaping (Result<BrowserContext, CollectionError>) -> Void,
        originalError: CollectionError
    ) {
        let fallbackScriptSource = """
        tell application "Safari"
            if window 1 exists then
                return (name of current tab of window 1) & "\\n" & (URL of current tab of window 1)
            end if
        end tell
        """
        
        executor.execute(fallbackScriptSource, timeout: 0.75) { result in
            switch result {
            case .success(let response):
                let responseTrimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                if !responseTrimmed.isEmpty, let context = self.parseResponse(responseTrimmed) {
                    completion(.success(context))
                } else {
                    self.executeAccessibilityFallback(completion: completion, originalError: .execFailed("Fallback empty/invalid"))
                }
            case .failure(let error):
                let fallbackError: CollectionError
                switch error {
                case .timedOut:
                    fallbackError = .timedOut
                case .execFailed(let msg):
                    fallbackError = .execFailed(msg)
                }
                self.executeAccessibilityFallback(completion: completion, originalError: fallbackError)
            }
        }
    }
    
    private func executeAccessibilityFallback(
        completion: @escaping (Result<BrowserContext, CollectionError>) -> Void,
        originalError: CollectionError
    ) {
        AccessibilityBrowserHelper.getActiveContext(bundleIdentifier: bundleIdentifier) { result in
            switch result {
            case .success(let context):
                completion(.success(context))
            case .failure:
                completion(.failure(originalError))
            }
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

/// Strategy for fetching the active URL from Firefox using the Accessibility API asynchronously.
public class FirefoxBrowserStrategy: BrowserStrategy {
    public let bundleIdentifier = "org.mozilla.firefox"
    
    public init() {}
    
    public func getActiveContext(completion: @escaping (Result<BrowserContext, CollectionError>) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let firefoxApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == self.bundleIdentifier }) else {
                completion(.failure(.execFailed("Firefox not running")))
                return
            }
            
            let appRef = AXUIElementCreateApplication(firefoxApp.processIdentifier)
            AXUIElementSetMessagingTimeout(appRef, 0.25)
            
            let targetWindow: AXUIElement
            var windowRef: AnyObject?
            let windowError = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
            
            if windowError == .success, let activeWindow = windowRef {
                targetWindow = activeWindow as! AXUIElement
            } else {
                var windowsRef: AnyObject?
                let windowsError = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
                guard windowsError == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
                    completion(.failure(.execFailed("Firefox window unavailable")))
                    return
                }
                targetWindow = windows[0]
            }
            
            var titleRef: AnyObject?
            let titleError = AXUIElementCopyAttributeValue(targetWindow, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleError == .success ? titleRef as? String : nil) ?? ""
            
            if let url = self.findURLInUIElement(targetWindow) {
                completion(.success(BrowserContext(title: title, url: url)))
            } else {
                completion(.failure(.execFailed("URL not found in Firefox")))
            }
        }
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
    public static func strategy(for bundleIdentifier: String, executor: AppleEventExecuting = AppleEventExecutor()) -> BrowserStrategy? {
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

internal struct AccessibilityBrowserHelper {
    static func getActiveContext(
        bundleIdentifier: String,
        completion: @escaping (Result<BrowserContext, CollectionError>) -> Void
    ) {
        DispatchQueue.main.async {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                completion(.failure(.execFailed("Application not running")))
                return
            }
            
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appRef, 0.25)
            
            let targetWindow: AXUIElement
            var windowRef: AnyObject?
            let windowError = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
            
            if windowError == .success, let activeWindow = windowRef {
                targetWindow = activeWindow as! AXUIElement
            } else {
                var windowsRef: AnyObject?
                let windowsError = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
                guard windowsError == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
                    completion(.failure(.execFailed("Window unavailable")))
                    return
                }
                targetWindow = windows[0]
            }
            
            var titleRef: AnyObject?
            let titleError = AXUIElementCopyAttributeValue(targetWindow, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleError == .success ? titleRef as? String : nil) ?? ""
            
            var visitedCount = 0
            if let url = findURL(in: targetWindow, depth: 0, visitedCount: &visitedCount) {
                completion(.success(BrowserContext(title: title, url: url)))
            } else {
                completion(.failure(.execFailed("URL not found via Accessibility")))
            }
        }
    }
    
    private static func findURL(in element: AXUIElement, depth: Int, visitedCount: inout Int) -> URL? {
        guard depth <= 16, visitedCount < 256 else { return nil }
        visitedCount += 1
        
        var urlValue: AnyObject?
        let urlError = AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlValue)
        if urlError == .success {
            if let url = urlValue as? URL {
                return url
            } else if let urlStr = urlValue as? String, let url = URL(string: urlStr), url.host != nil {
                return url
            }
        }
        
        var roleValue: AnyObject?
        let roleError = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if roleError == .success, let role = roleValue as? String {
            if role == kAXTextFieldRole || role == "AXComboBox" || role == "AXSearchField" || role == "AXAddressIndicator" {
                var valueRef: AnyObject?
                let valueError = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                if valueError == .success, let urlStr = valueRef as? String {
                    let trimmed = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if trimmed.contains("://") || trimmed.contains(".") {
                            let finalUrlStr = trimmed.contains("://") ? trimmed : "https://" + trimmed
                            if let url = URL(string: finalUrlStr), url.host != nil, url.host!.contains(".") {
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
            if let url = findURL(in: child, depth: depth + 1, visitedCount: &visitedCount) {
                return url
            }
        }
        
        return nil
    }
}
