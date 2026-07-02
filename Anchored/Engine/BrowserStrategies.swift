import Foundation

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

/// Protocol defining a strategy for retrieving the active URL from a browser.
public protocol BrowserStrategy {
    /// The bundle identifier of the browser this strategy supports.
    var bundleIdentifier: String { get }
    
    /// Fetches the active URL from the browser.
    /// - Returns: The active URL if successfully retrieved, nil otherwise.
    func getActiveURL() -> URL?
}

/// Strategy for fetching the active URL from Chromium-based browsers using AppleScript.
public class ChromiumBrowserStrategy: BrowserStrategy {
    public let bundleIdentifier: String
    public let appName: String
    private let executor: AppleScriptExecutor
    
    public init(bundleIdentifier: String, appName: String, executor: AppleScriptExecutor = NSAppleScriptExecutor()) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.executor = executor
    }
    
    public func getActiveURL() -> URL? {
        let scriptSource = """
        tell application "\(appName)"
            if window 1 exists then
                return URL of active tab of window 1
            end if
        end tell
        """
        do {
            let urlString = try executor.execute(scriptSource).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlString.isEmpty else { return nil }
            return URL(string: urlString)
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
    
    public func getActiveURL() -> URL? {
        // 1. Try to fetch URL using JavaScript execution first.
        // This is necessary to detect if "Allow JavaScript from Apple Events" is enabled/disabled.
        let jsScriptSource = """
        tell application "Safari"
            if window 1 exists then
                tell window 1
                    do JavaScript "window.location.href" in current tab
                end tell
            end if
        end tell
        """
        
        do {
            let urlString = try executor.execute(jsScriptSource).trimmingCharacters(in: .whitespacesAndNewlines)
            if !urlString.isEmpty {
                return URL(string: urlString)
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
        
        // 2. Fallback to standard URL property retrieval if JavaScript events are disabled.
        let fallbackScriptSource = """
        tell application "Safari"
            if window 1 exists then
                return URL of current tab of window 1
            end if
        end tell
        """
        
        do {
            let urlString = try executor.execute(fallbackScriptSource).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlString.isEmpty else { return nil }
            return URL(string: urlString)
        } catch {
            return nil
        }
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
        default:
            return nil
        }
    }
    
    public static func isSupportedBrowser(_ bundleIdentifier: String) -> Bool {
        return strategy(for: bundleIdentifier) != nil
    }
}
