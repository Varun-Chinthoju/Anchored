import Foundation

protocol IntentClassifying: Sendable {
    func classify(input: IntentClassificationInput) -> IntentClassificationResult
}

struct LocalIntentClassifier: IntentClassifying, Sendable {
    static let version = "intent-local-v1"

    func classify(input: IntentClassificationInput) -> IntentClassificationResult {
        let start = DispatchTime.now().uptimeNanoseconds

        let searchableText = Self.searchableText(for: input.snapshot)
        let goalFeatures = input.goalFeatures.isEmpty
            ? FocusIntent.extractGoalFeatures(from: input.sanitizedGoal ?? "")
            : input.goalFeatures
        let baseline = input.baseline

        let entertainmentSignals = Self.entertainmentSignals
        let entertainmentMatch = Self.containsAny(entertainmentSignals, in: searchableText)
        let educationalMatch = Self.isEducationalContent(searchableText: searchableText)
        let relatedMatch = Self.hasGoalMatch(
            goalFeatures,
            searchableText: searchableText,
            baseline: baseline,
            snapshot: input.snapshot
        )
        let baselineMatch = Self.matchesBaseline(baseline, snapshot: input.snapshot)

        let relation: IntentRelation
        let confidence: Double
        let reason: IntentClassificationReason
        let explanation: String

        if !input.hasMeaningfulIntent {
            return IntentClassificationResult(
                relation: .uncertain,
                confidence: 0.0,
                source: .heuristic,
                modelVersion: Self.version,
                latency: 0.0,
                reason: .insufficientIntent,
                explanation: "No goal or baseline intent was available."
            )
        }

        if educationalMatch && !relatedMatch {
            relation = .uncertain
            confidence = 0.58
            reason = .insufficientIntent
            explanation = "Educational video signals were present, but the current task intent was too weak to treat it as work."
        } else if entertainmentMatch && !relatedMatch {
            relation = .entertainment
            confidence = 0.92
            reason = .entertainmentMatched
            explanation = "Entertainment signals outweighed task intent."
        } else if relatedMatch {
            relation = .related
            confidence = 0.91
            reason = .goalMatched
            explanation = "Context matched the current task intent."
        } else if goalFeatures.isEmpty, baselineMatch {
            relation = .related
            confidence = 0.84
            reason = .baselineMatched
            explanation = "Context matched the session baseline."
        } else if !goalFeatures.isEmpty {
            if BrowserStrategyFactory.isSupportedBrowser(input.snapshot.bundleIdentifier) {
                relation = .uncertain
                confidence = 0.52
                reason = .insufficientIntent
                explanation = "Browser context lacked enough task signal."
            } else {
                relation = .unrelated
                confidence = 0.86
                reason = .goalMismatched
                explanation = "Context did not match the active task goal."
            }
        } else {
            relation = .uncertain
            confidence = 0.45
            reason = .insufficientIntent
            explanation = "Intent baseline was not specific enough to decide."
        }

        return IntentClassificationResult(
            relation: relation,
            confidence: confidence,
            source: .heuristic,
            modelVersion: Self.version,
            latency: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000,
            reason: reason,
            explanation: explanation
        )
    }
}

private extension IntentClassificationInput {
    var hasMeaningfulIntent: Bool {
        !(sanitizedGoal?.isEmpty ?? true) || !goalFeatures.isEmpty || baseline != nil
    }
}

private extension LocalIntentClassifier {
    static let entertainmentSignals: [String] = [
        "youtube.com",
        "netflix.com",
        "twitch.tv",
        "hulu.com",
        "disneyplus.com",
        "steam",
        "spotify",
        "gaming",
        "gameplay",
        "livestream",
        "entertainment",
        "watch movie",
        "watch tv"
    ]

    static let educationalSignals: [String] = [
        "computer science",
        "programming",
        "coding",
        "software engineering",
        "tutorial",
        "course",
        "lecture",
        "lesson",
        "documentation",
        "learn",
        "how to",
        "explain",
        "cs50",
        "stanford",
        "mit"
    ]

    static func searchableText(for snapshot: ContextSnapshot) -> String {
        let host = snapshot.url?.host ?? ""
        let path = snapshot.url?.path ?? ""
        return [
            snapshot.bundleIdentifier,
            snapshot.localizedName,
            host,
            path,
            ContextSanitizer.sanitizeTitle(snapshot.title)
        ]
        .joined(separator: " ")
        .lowercased()
    }

    static func containsAny(_ signals: [String], in text: String) -> Bool {
        signals.contains { text.contains($0) }
    }

    static func isEducationalContent(searchableText: String) -> Bool {
        guard searchableText.contains("youtube.com") || searchableText.contains("youtu.be") || searchableText.contains("vimeo.com") else {
            return false
        }

        return containsAny(educationalSignals, in: searchableText)
    }

    static func hasGoalMatch(
        _ goalFeatures: [String],
        searchableText: String,
        baseline: FocusIntentBaseline?,
        snapshot: ContextSnapshot
    ) -> Bool {
        if goalFeatures.contains(where: { searchableText.contains($0) }) {
            return true
        }

        guard let baseline else { return false }

        if baseline.identity.bundleID == snapshot.bundleIdentifier {
            return true
        }

        if let baselineHost = URL(string: baseline.identity.sanitizedURL ?? "")?.host?.lowercased(),
           let currentHost = snapshot.url?.host?.lowercased(),
           baselineHost == currentHost {
            return true
        }

        let baselineTitle = baseline.identity.normalizedTitle.lowercased()
        let currentTitle = ContextSanitizer.sanitizeTitle(snapshot.title).lowercased()
        return !baselineTitle.isEmpty && baselineTitle == currentTitle
    }

    static func matchesBaseline(_ baseline: FocusIntentBaseline?, snapshot: ContextSnapshot) -> Bool {
        guard let baseline else { return false }
        if baseline.identity.bundleID == snapshot.bundleIdentifier {
            return true
        }
        if let baselineURL = baseline.identity.sanitizedURL,
           baselineURL == ContextSanitizer.sanitizePersistedURL(snapshot.url) {
            return true
        }
        let baselineTitle = baseline.identity.normalizedTitle.lowercased()
        let currentTitle = ContextSanitizer.sanitizeTitle(snapshot.title).lowercased()
        return !baselineTitle.isEmpty && baselineTitle == currentTitle
    }
}
