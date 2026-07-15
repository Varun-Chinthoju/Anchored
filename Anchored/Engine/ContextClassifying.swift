import Foundation

/// Testable boundary for on-device classification.
/// - Input: sanitized ContextSnapshot plus optional transient visible text captured on-device
/// - Output: ClassificationResult with label, confidence, modelVersion, latency, explanation
/// - CoreML is isolated to concrete implementations; FocusEngine depends only on this protocol.
/// - Implementations must be thread-safe and must not require main thread.
///   FocusEngine future integration pattern:
///     let classifier: ContextClassifying?
///     DispatchQueue.global(qos: .userInitiated).async {
///         let result = classifier.classify(snapshot: sanitizedSnapshot, screenText: visibleText)
///         // generation check, then DispatchQueue.main.async for state update
///     }
///   This preserves V2.6 non-blocking invariant and keeps p95 <50ms off main.
/// - ClassificationResolver owns precedence; this protocol only returns
///   evidence/results and never enforces focus state.
public protocol ContextClassifying: Sendable {
    func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult
}

public extension ContextClassifying {
    func classify(snapshot: ContextSnapshot) -> ClassificationResult {
        classify(snapshot: snapshot, screenText: nil)
    }
}

public final class MockContextClassifier: ContextClassifying, Sendable {
    private let version: String

    public init(version: String = "mock-1.0") {
        self.version = version
    }

    public func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
        ClassificationResult(
            label: .neutral,
            confidence: 1.0,
            modelVersion: version,
            latency: 0.0,
            explanation: "mock neutral"
        )
    }
}
