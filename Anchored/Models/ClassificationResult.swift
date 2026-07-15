import Foundation

public enum ClassificationLabel: String, Codable, Equatable, CaseIterable, Sendable {
    case productive
    case distracting
    case neutral
}

/// The policy stage that produced an evidence item or final decision.
///
/// These cases intentionally describe trusted categories rather than carrying
/// app names, domains, titles, or model-generated text. That keeps the decision
/// trace safe to expose to the UI and safe to retain in future diagnostics.
public enum ClassificationSource: String, Codable, Equatable, CaseIterable, Sendable {
    case explicitDomainRule
    case explicitAppRule
    case deterministicRule
    case heuristic
    case localModel
    case cloudModel
    case visualFallback
    case neutralFallback

    public var isExplicitRule: Bool {
        switch self {
        case .explicitDomainRule, .explicitAppRule:
            return true
        case .deterministicRule, .heuristic, .localModel, .cloudModel, .visualFallback, .neutralFallback:
            return false
        }
    }
}

/// A bounded, UI-safe explanation category. Raw context must never be placed
/// in a classification reason.
public enum ClassificationReason: String, Codable, Equatable, CaseIterable, Sendable {
    case explicitAllowRule
    case explicitBlockRule
    case deterministicRule
    case deterministicHeuristic
    case modelEvidence
    case intentRelated
    case intentEntertainment
    case intentUnrelated
    case intentUncertain
    case conflictingEvidence
    case lowConfidence
    case optionalDistractionIsNonEnforcing
    case neutralFallback
}

public struct ClassificationEvidence: Equatable, Codable, Sendable {
    public let label: ClassificationLabel
    public let source: ClassificationSource
    public let confidence: Double
    public let reason: ClassificationReason

    public init(
        label: ClassificationLabel,
        source: ClassificationSource,
        confidence: Double,
        reason: ClassificationReason
    ) {
        self.label = label
        self.source = source
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.reason = reason
    }
}

public struct ClassificationDecision: Equatable, Codable, Sendable {
    public let label: ClassificationLabel
    public let confidence: Double
    public let source: ClassificationSource
    public let reason: ClassificationReason
    public let evidence: [ClassificationEvidence]

    public var isFocus: Bool { label == .productive }
    public var isDistraction: Bool { label == .distracting }
    public var isNeutral: Bool { label == .neutral }

    public init(
        label: ClassificationLabel,
        confidence: Double,
        source: ClassificationSource,
        reason: ClassificationReason,
        evidence: [ClassificationEvidence]
    ) {
        self.label = label
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.source = source
        self.reason = reason
        self.evidence = evidence
    }

    public static func neutral(
        reason: ClassificationReason = .neutralFallback,
        evidence: [ClassificationEvidence] = []
    ) -> ClassificationDecision {
        ClassificationDecision(
            label: .neutral,
            confidence: 0.0,
            source: .neutralFallback,
            reason: reason,
            evidence: evidence
        )
    }
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
    /// Precedence (highest to lowest): explicit domain rules, explicit app
    /// rules, deterministic rules, heuristics, local model, cloud model,
    /// experimental visual fallback, and neutral fallback.
    ///
    /// Within one explicit target, an allowed rule wins over a blocked rule to
    /// preserve the legacy duplicate-domain behavior. A domain rule always
    /// outranks an app rule. Optional model evidence can contribute to the
    /// intent-aware grace period, but never dims the screen immediately.
    ///
    /// Privacy: local classification input is a sanitized ContextSnapshot plus optional transient visible OCR text; cloud requests still receive only categorical features.
    /// Safety: asynchronous classifiers cannot directly start dimming/blocking.
    /// Threading: ML inference must run off main on background serial queue with generation-based stale rejection; CoreML stays out of FocusEngine.

    public static let precedence: [String] = [
        "explicitDomainRules",
        "explicitAppRules",
        "deterministicRules",
        "heuristics",
        "localModelPromotion",
        "cloudModelPromotion",
        "visualFallbackPromotion",
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

    public static func rank(of source: ClassificationSource) -> Int {
        switch source {
        case .explicitDomainRule:
            return 0
        case .explicitAppRule:
            return 1
        case .deterministicRule:
            return 2
        case .heuristic:
            return 3
        case .localModel:
            return 4
        case .cloudModel:
            return 5
        case .visualFallback:
            return 6
        case .neutralFallback:
            return 7
        }
    }
}
