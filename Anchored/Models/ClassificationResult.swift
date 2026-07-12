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
    /// 1. explicit domain rules - allowed domains, then blocked domains
    /// 2. local browser/app heuristics and profile app rules
    /// 3. optional visual classification, only to promote a still-current neutral context
    /// 4. optional cloud classification, using the same stale-result guard
    /// 5. neutral fallback - uncertain, timed-out, or failed predictions never trigger blocking
    ///
    /// Privacy: classification input is sanitized ContextSnapshot only (bundleID, host/path, normalized title via ContextSanitizer).
    /// Safety: asynchronous classifiers cannot directly start dimming/blocking.
    /// Threading: ML inference must run off main on background serial queue with generation-based stale rejection; CoreML stays out of FocusEngine.

    public static let precedence: [String] = [
        "explicitDomainRules",
        "localHeuristicsAndProfileRules",
        "visualNeutralPromotion",
        "cloudNeutralPromotion",
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
