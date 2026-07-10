import Foundation
import AppKit

/// Errors that can occur during AppleEvent execution.
public enum ExecutorError: Error, Equatable {
    case timedOut
    case execFailed(String)
}

/// A protocol defining an interface for asynchronous AppleScript/AppleEvent execution.
public protocol AppleEventExecuting: AnyObject {
    func execute(
        _ scriptSource: String,
        timeout: TimeInterval,
        completion: @escaping (Result<String, ExecutorError>) -> Void
    )
}

/// Executes AppleScripts on a serial background queue with custom sub-second timeouts.
public final class AppleEventExecutor: AppleEventExecuting {
    private let queue: DispatchQueue
    
    public init(queueLabel: String = "com.anchored.AppleEventExecutor") {
        self.queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    }
    
    public func execute(
        _ scriptSource: String,
        timeout: TimeInterval = 0.75, // Default 750 ms
        completion: @escaping (Result<String, ExecutorError>) -> Void
    ) {
        let lock = NSLock()
        var isCompleted = false
        
        let safeCompletion: (Result<String, ExecutorError>) -> Void = { result in
            lock.lock()
            defer { lock.unlock() }
            guard !isCompleted else { return }
            isCompleted = true
            completion(result)
        }
        
        // Schedule timeout boundary check
        let timeoutWorkItem = DispatchWorkItem {
            safeCompletion(.failure(.timedOut))
        }
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + timeout,
            execute: timeoutWorkItem
        )
        
        // Execute compilation & execution on a serial background queue
        queue.async {
            // Check if timeout has already fired before we begin
            lock.lock()
            let alreadyFinished = isCompleted
            lock.unlock()
            
            if alreadyFinished {
                return
            }
            
            guard let script = NSAppleScript(source: scriptSource) else {
                timeoutWorkItem.cancel()
                safeCompletion(.failure(.execFailed("AppleScript compilation failed")))
                return
            }
            
            var errorDict: NSDictionary?
            let resultDescriptor = script.executeAndReturnError(&errorDict)
            
            timeoutWorkItem.cancel()
            
            if let error = errorDict {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error (code \(code))"
                safeCompletion(.failure(.execFailed(message)))
            } else {
                let resultText = resultDescriptor.stringValue ?? ""
                safeCompletion(.success(resultText))
            }
        }
    }
}
