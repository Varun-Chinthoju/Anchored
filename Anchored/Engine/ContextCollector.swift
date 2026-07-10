import Foundation
import AppKit

public protocol ContextCollecting: AnyObject {
    func collectContext(for bundleID: String, completion: @escaping (Result<ContextSnapshot, CollectionError>) -> Void)
}

public enum CollectionError: Error, Equatable {
    case timedOut
    case permissionDenied
    case execFailed(String)
}

public final class ContextCollector: ContextCollecting {
    private let accessibilityProvider: AccessibilityContextProviding
    private let executor: AppleEventExecuting
    private let queue = DispatchQueue(label: "com.varun.Anchored.ContextCollector", qos: .userInitiated)
    
    private var currentGeneration = 0
    private let lock = NSLock()
    
    public init(
        accessibilityProvider: AccessibilityContextProviding = SystemAccessibilityContextProvider(),
        executor: AppleEventExecuting = AppleEventExecutor()
    ) {
        self.accessibilityProvider = accessibilityProvider
        self.executor = executor
    }
    
    public func collectContext(for bundleID: String, completion: @escaping (Result<ContextSnapshot, CollectionError>) -> Void) {
        lock.lock()
        currentGeneration += 1
        let generation = currentGeneration
        lock.unlock()
        
        let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })
        let localizedName = runningApp?.localizedName ?? ""
        
        let finishWithResult: (Result<ContextSnapshot, CollectionError>) -> Void = { [weak self] result in
            guard let self = self else { return }
            self.lock.lock()
            let activeGen = self.currentGeneration
            self.lock.unlock()
            
            if generation < activeGen {
                // Discard stale callback
                return
            }
            
            completion(result)
        }
        
        if BrowserStrategyFactory.isSupportedBrowser(bundleID) {
            let strategy = BrowserStrategyFactory.strategy(for: bundleID, executor: executor)
            guard let strategy = strategy else {
                finishWithResult(.failure(.execFailed("Strategy not found for \(bundleID)")))
                return
            }
            
            strategy.getActiveContext { result in
                switch result {
                case .success(let context):
                    let source: ContextSnapshot.Source
                    if bundleID == "com.apple.Safari" {
                        source = .safari
                    } else if bundleID == "org.mozilla.firefox" {
                        source = .firefox
                    } else {
                        source = .chromium
                    }
                    let snapshot = ContextSnapshot(
                        bundleIdentifier: bundleID,
                        localizedName: localizedName,
                        url: context.url,
                        title: context.title,
                        source: source,
                        observedAt: Date()
                    )
                    finishWithResult(.success(snapshot))
                case .failure(let error):
                    finishWithResult(.failure(error))
                }
            }
        } else {
            queue.async { [weak self] in
                guard let self = self else { return }
                
                self.lock.lock()
                let currentGenBeforeCheck = self.currentGeneration
                self.lock.unlock()
                
                if generation < currentGenBeforeCheck {
                    return
                }
                
                let result = self.accessibilityProvider.context(for: bundleID)
                
                switch result {
                case .success(let title, let url):
                    let snapshot = ContextSnapshot(
                        bundleIdentifier: bundleID,
                        localizedName: localizedName,
                        url: url,
                        title: title,
                        source: .application,
                        observedAt: Date()
                    )
                    finishWithResult(.success(snapshot))
                case .permissionDenied:
                    finishWithResult(.failure(.permissionDenied))
                case .windowUnavailable:
                    let snapshot = ContextSnapshot(
                        bundleIdentifier: bundleID,
                        localizedName: localizedName,
                        url: nil,
                        title: "",
                        source: .application,
                        observedAt: Date()
                    )
                    finishWithResult(.success(snapshot))
                case .invalidResponse:
                    finishWithResult(.failure(.execFailed("Invalid accessibility response")))
                }
            }
        }
    }
}
