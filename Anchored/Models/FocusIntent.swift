import Foundation

public enum IntentRelation: String, Codable, CaseIterable, Equatable, Sendable {
    case related
    case entertainment
    case unrelated
    case uncertain
}

public enum IntentClassificationReason: String, Codable, CaseIterable, Equatable, Sendable {
    case goalMatched
    case goalMismatched
    case entertainmentMatched
    case baselineMatched
    case insufficientIntent
    case lowConfidence
    case conflictingSignals
}

public struct FocusIntentBaseline: Codable, Equatable, Sendable {
    public let identity: ContextIdentity
    public let activeProfileName: String?
    public let activeProfileCategory: String?

    public init(
        identity: ContextIdentity,
        activeProfileName: String? = nil,
        activeProfileCategory: String? = nil
    ) {
        self.identity = identity
        self.activeProfileName = activeProfileName
        self.activeProfileCategory = activeProfileCategory
    }
}

public struct FocusIntent: Codable, Equatable, Sendable {
    public let sanitizedGoal: String?
    public let goalFeatures: [String]
    public let baseline: FocusIntentBaseline?

    public init(
        sanitizedGoal: String? = nil,
        goalFeatures: [String] = [],
        baseline: FocusIntentBaseline? = nil
    ) {
        self.sanitizedGoal = sanitizedGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.goalFeatures = Self.normalizeFeatures(goalFeatures)
        self.baseline = baseline
    }

    public var hasIntentSignal: Bool {
        !(sanitizedGoal?.isEmpty ?? true) || !goalFeatures.isEmpty || baseline != nil
    }

    public var safeTrackingSummary: String? {
        var parts: [String] = []
        if !goalFeatures.isEmpty {
            parts.append("goal:" + goalFeatures.joined(separator: ","))
        } else if let sanitizedGoal, !sanitizedGoal.isEmpty {
            let extracted = Self.extractGoalFeatures(from: sanitizedGoal)
            if !extracted.isEmpty {
                parts.append("goal:" + extracted.joined(separator: ","))
            }
        }

        if let baseline {
            parts.append("baseline:" + baseline.identity.bundleID)
            if let profile = baseline.activeProfileName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !profile.isEmpty {
                parts.append("profile:" + profile.lowercased())
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "|")
    }

    public func makeInput(
        snapshot: ContextSnapshot,
        activeProfileName: String? = nil,
        activeProfileCategory: String? = nil
    ) -> IntentClassificationInput {
        IntentClassificationInput(
            snapshot: snapshot,
            sanitizedGoal: sanitizedGoal,
            goalFeatures: goalFeatures,
            baseline: baseline,
            activeProfileName: activeProfileName?.trimmingCharacters(in: .whitespacesAndNewlines),
            activeProfileCategory: activeProfileCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public static func make(
        goal: String?,
        baselineContext: ContextSnapshot?,
        activeProfileName: String? = nil,
        activeProfileCategory: String? = nil
    ) -> FocusIntent {
        let sanitizedGoal = goal.map { ContextSanitizer.sanitizeTitle($0) }
        let goalFeatures = sanitizedGoal.map(Self.extractGoalFeatures(from:)) ?? []
        let baseline: FocusIntentBaseline?
        if let baselineContext {
            baseline = FocusIntentBaseline(
                identity: baselineContext.identity,
                activeProfileName: activeProfileName,
                activeProfileCategory: activeProfileCategory
            )
        } else {
            baseline = nil
        }

        return FocusIntent(
            sanitizedGoal: sanitizedGoal,
            goalFeatures: goalFeatures,
            baseline: baseline
        )
    }

    public static func extractGoalFeatures(from goal: String) -> [String] {
        let text = ContextSanitizer.sanitizeTitle(goal).lowercased()
        guard !text.isEmpty else { return [] }

        let stopWords: Set<String> = [
            "a", "an", "and", "around", "at", "for", "from", "in", "into", "of", "on", "or",
            "the", "to", "with", "work", "task", "project", "today", "this", "that", "my",
            "your", "our", "their", "focus", "session", "goal"
        ]

        let synonyms: [String: String] = [
            "coding": "code",
            "programming": "code",
            "development": "code",
            "developer": "code",
            "writing": "write",
            "documentation": "docs",
            "researching": "research",
            "studying": "study",
            "designing": "design",
            "meetings": "meeting",
            "emails": "email",
            "reading": "read"
        ]

        var features: [String] = []
        for token in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let tokenText = String(token)
            guard tokenText.count >= 3, !stopWords.contains(tokenText) else { continue }
            let normalized = synonyms[tokenText] ?? tokenText
            if !features.contains(normalized) {
                features.append(normalized)
            }
        }

        return features
    }

    private static func normalizeFeatures(_ features: [String]) -> [String] {
        var normalized: [String] = []
        for feature in features {
            let trimmed = feature.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty, !normalized.contains(trimmed) else { continue }
            normalized.append(trimmed)
        }
        return normalized
    }
}

public struct IntentClassificationInput: Codable, Equatable, Sendable {
    public let snapshot: ContextSnapshot
    public let sanitizedGoal: String?
    public let goalFeatures: [String]
    public let baseline: FocusIntentBaseline?
    public let activeProfileName: String?
    public let activeProfileCategory: String?

    public init(
        snapshot: ContextSnapshot,
        sanitizedGoal: String? = nil,
        goalFeatures: [String] = [],
        baseline: FocusIntentBaseline? = nil,
        activeProfileName: String? = nil,
        activeProfileCategory: String? = nil
    ) {
        self.snapshot = snapshot
        self.sanitizedGoal = sanitizedGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.goalFeatures = goalFeatures.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty }
        self.baseline = baseline
        self.activeProfileName = activeProfileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeProfileCategory = activeProfileCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct IntentClassificationResult: Codable, Equatable, Sendable {
    public let relation: IntentRelation
    public let confidence: Double
    public let source: ClassificationSource
    public let modelVersion: String
    public let latency: TimeInterval
    public let reason: IntentClassificationReason
    public let explanation: String?

    public init(
        relation: IntentRelation,
        confidence: Double,
        source: ClassificationSource,
        modelVersion: String,
        latency: TimeInterval,
        reason: IntentClassificationReason,
        explanation: String? = nil
    ) {
        self.relation = relation
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.source = source
        self.modelVersion = modelVersion
        self.latency = max(latency, 0.0)
        self.reason = reason
        self.explanation = explanation
    }

    public var mappedLabel: ClassificationLabel {
        switch relation {
        case .related:
            return .productive
        case .entertainment, .unrelated:
            return .distracting
        case .uncertain:
            return .neutral
        }
    }

    public var isHighConfidence: Bool {
        confidence >= ClassificationPolicy.highConfidenceThreshold
    }
}
