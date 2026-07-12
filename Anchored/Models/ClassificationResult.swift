import Foundation

public enum ClassificationLabel: String, Codable, Equatable, CaseIterable, Sendable {
    case productive
    case distracting
    case neutral
}

public struct ClassificationResult: Equatable, Codable, Sendable {
    public let label: ClassificationLabel
    public let confidence: Double
    public let modelVersion: String
    public let latency: TimeInterval
    public let explanation: String?

    public init(
        label: ClassificationLabel,
        confidence: Double,
        modelVersion: String,
        latency: TimeInterval,
        explanation: String? = nil
    ) {
        self.label = label
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.modelVersion = modelVersion
        self.latency = max(latency, 0.0)
        self.explanation = explanation
    }

    public static func neutralMock(version: String = "mock-1.0") -> ClassificationResult {
        ClassificationResult(
            label: .neutral,
            confidence: 1.0,
            modelVersion: version,
            latency: 0.0,
            explanation: "deterministic neutral fallback"
        )
    }
}

public enum ClassificationPolicy {
    /// Precedence (highest to lowest):
    /// 1. explicit rules - profile allowedApps/distractionApps, allowedDomains/distractionDomains, BrowserStrategyFactory, SmartAppClassifier/SmartWebClassifier
    /// 2. override cache - user feedback store (Mark as Focus / Distraction / Not Sure) persisted locally
    /// 3. ML prediction - on-device CoreML model via ContextClassifying, applied only when confidence >= highConfidenceThreshold
    /// 4. neutral fallback - uncertain, low-confidence, timed-out, or failed predictions resolve to neutral and never trigger blocking
    ///
    /// Privacy: classification input is sanitized ContextSnapshot only (bundleID, host/path, normalized title via ContextSanitizer).
    /// Safety: ML cannot directly start dimming/blocking without FocusEngine timers and state invariants.
    /// Threading: ML inference must run off main on background serial queue with generation-based stale rejection; CoreML stays out of FocusEngine.

    public static let precedence: [String] = [
        "explicitRules",
        "overrideCache",
        "mlPrediction",
        "neutralFallback"
    ]

    public static let highConfidenceThreshold: Double = 0.80
    public static let lowConfidenceThreshold: Double = 0.50

    public static func shouldApplyML(confidence: Double, hasExplicitRule: Bool, hasOverride: Bool) -> Bool {
        if hasExplicitRule { return false }
        if hasOverride { return false }
        return confidence >= highConfidenceThreshold
    }

    public static func resolveToNeutralIfUncertain(confidence: Double) -> Bool {
        return confidence < lowConfidenceThreshold
    }
}
