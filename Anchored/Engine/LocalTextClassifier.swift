import Foundation

/// A local on-device classifier for sanitized context identity plus transient
/// visible text captured on-device. It stays fully offline and only uses real
/// app context data, not a remote model server.
public final class LocalTextClassifier: ContextClassifying, @unchecked Sendable {
    public static let version = "local-text-v1"

    private static let productiveSignals = [
        "xcode", "vscode", "visual studio", "terminal", "iterm", "notion", "obsidian",
        "bear", "craft", "pages", "word", "figma", "github", "stackoverflow", "stackexchange",
        "developer", "documentation", "programming", "coding", "software", "api", "tutorial",
        "swift", "kotlin", "java", "python", "rust", "javascript", "typescript", "database",
        "compiler", "docker", "kubernetes", "learn", "course"
    ]

    private static let distractingSignals = [
        "spotify", "steam", "youtube", "netflix", "twitch", "tiktok", "instagram",
        "facebook", "reddit", "twitter", "gaming", "gameplay", "livestream", "entertainment",
        "music", "movie", "stream"
    ]

    private let preferences: PreferencesManager

    public init(preferences: PreferencesManager = .shared) {
        self.preferences = preferences
    }

    public func classify(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
        guard preferences.enableLocalTextClassification else {
            return heuristicClassification(snapshot: snapshot, screenText: screenText)
        }

        return localClassification(snapshot: snapshot, screenText: screenText)
    }

    public func classify(snapshot: ContextSnapshot) -> ClassificationResult {
        classify(snapshot: snapshot, screenText: nil)
    }
}

private extension LocalTextClassifier {
    func localClassification(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
        let identity = snapshot.identity
        let visibleText = Self.normalized(screenText) ?? ""
        let searchableText = [
            identity.bundleID,
            identity.sanitizedURL ?? "",
            identity.normalizedTitle,
            visibleText
        ]
        .joined(separator: " ")
        .lowercased()

        let productiveScore = Self.score(Self.productiveSignals, in: searchableText)
        let distractingScore = Self.score(Self.distractingSignals, in: searchableText)

        if productiveScore > 0 && distractingScore > 0 {
            return ClassificationResult(
                label: .neutral,
                confidence: 0.5,
                modelVersion: Self.version,
                latency: 0,
                explanation: "local signals conflict"
            )
        }

        if productiveScore > 0 {
            return ClassificationResult(
                label: .productive,
                confidence: min(0.98, 0.90 + Double(max(0, productiveScore - 1)) * 0.04),
                modelVersion: Self.version,
                latency: 0,
                explanation: "local productive signals"
            )
        }

        if distractingScore > 0 {
            return ClassificationResult(
                label: .distracting,
                confidence: min(0.98, 0.90 + Double(max(0, distractingScore - 1)) * 0.04),
                modelVersion: Self.version,
                latency: 0,
                explanation: "local distracting suggestion"
            )
        }

        return ClassificationResult(
            label: .neutral,
            confidence: 0,
            modelVersion: Self.version,
            latency: 0,
            explanation: "local confidence below gate"
        )
    }

    func heuristicClassification(snapshot: ContextSnapshot, screenText: String?) -> ClassificationResult {
        let identity = snapshot.identity
        let searchableText = [
            identity.bundleID,
            identity.sanitizedURL ?? "",
            identity.normalizedTitle,
            Self.normalized(screenText) ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        let productiveScore = Self.score(Self.productiveSignals, in: searchableText)
        let distractingScore = Self.score(Self.distractingSignals, in: searchableText)

        if productiveScore > 0 && distractingScore > 0 {
            return ClassificationResult(
                label: .neutral,
                confidence: 0.5,
                modelVersion: Self.version,
                latency: 0,
                explanation: "local signals conflict"
            )
        }

        if productiveScore > 0 {
            return ClassificationResult(
                label: .productive,
                confidence: min(0.98, 0.90 + Double(max(0, productiveScore - 1)) * 0.04),
                modelVersion: Self.version,
                latency: 0,
                explanation: "local productive signals"
            )
        }

        if distractingScore > 0 {
            return ClassificationResult(
                label: .distracting,
                confidence: min(0.98, 0.90 + Double(max(0, distractingScore - 1)) * 0.04),
                modelVersion: Self.version,
                latency: 0,
                explanation: "local distracting suggestion"
            )
        }

        return ClassificationResult(
            label: .neutral,
            confidence: 0,
            modelVersion: Self.version,
            latency: 0,
            explanation: "local confidence below gate"
        )
    }

    static func score(_ signals: [String], in text: String) -> Int {
        signals.reduce(into: 0) { score, signal in
            if text.contains(signal) {
                score += 1
            }
        }
    }

    static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }
}
