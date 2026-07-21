import Foundation

/// Produces deterministic and heuristic evidence for one context.
///
/// This type does not resolve conflicts or change FocusEngine state. The
/// `ClassificationResolver` is the only owner of precedence and final labels.
final class DistractionEvaluator {
    private let profileProvider: () -> WorkProfile

    init(
        distractionListManager: DistractionListManager,
        profileProvider: @escaping () -> WorkProfile
    ) {
        self.profileProvider = profileProvider
    }

    func evidence(bundleID: String, url: URL?, title: String) -> [ClassificationEvidence] {
        let profile = profileProvider()
        var evidence: [ClassificationEvidence] = []

        // Collect both sides of a same-target conflict. The resolver preserves
        // the legacy allow-wins behavior while retaining the full trace.
        if let url, URLMatcher.matches(url: url, domains: profile.allowedDomains) {
            evidence.append(ClassificationEvidence(
                label: .productive,
                source: .explicitDomainRule,
                confidence: 1.0,
                reason: .explicitAllowRule
            ))
        }
        if let url, URLMatcher.matches(url: url, domains: profile.distractionDomains) {
            evidence.append(ClassificationEvidence(
                label: .distracting,
                source: .explicitDomainRule,
                confidence: 1.0,
                reason: .explicitBlockRule
            ))
        }

        if profile.allowedApps.contains(bundleID) {
            evidence.append(ClassificationEvidence(
                label: .productive,
                source: .explicitAppRule,
                confidence: 1.0,
                reason: .explicitAllowRule
            ))
        }
        if profile.distractionApps.contains(bundleID) {
            evidence.append(ClassificationEvidence(
                label: .distracting,
                source: .explicitAppRule,
                confidence: 1.0,
                reason: .explicitBlockRule
            ))
        }

        if BrowserStrategyFactory.isSupportedBrowser(bundleID), url != nil {
            let isMixedUseContext = ContextualSiteHeuristic.isMixedUseContext(url: url, title: title)
            if isMixedUseContext {
                evidence.append(ClassificationEvidence(
                    label: .contextual,
                    source: .heuristic,
                    confidence: 0.65,
                    reason: .contextualMixedUse
                ))
            }

            if BrowserContentHeuristic.isEducationalContent(url: url, title: title) {
                // Educational video content should stay neutral unless another
                // explicit rule or stronger intent signal says otherwise.
            } else if !isMixedUseContext, BrowserContentHeuristic.isEntertainment(url: url) {
                evidence.append(ClassificationEvidence(
                    label: .distracting,
                    source: .heuristic,
                    confidence: 0.90,
                    reason: .deterministicHeuristic
                ))
            } else if !isMixedUseContext, SmartWebClassifier.isCodingForumOrDoc(url: url, title: title) {
                evidence.append(ClassificationEvidence(
                    label: .productive,
                    source: .heuristic,
                    confidence: 0.85,
                    reason: .deterministicHeuristic
                ))
            }
        }

        if SmartAppClassifier.isProductiveApp(bundleID: bundleID) {
            evidence.append(ClassificationEvidence(
                label: .productive,
                source: .heuristic,
                confidence: 0.85,
                reason: .deterministicHeuristic
            ))
        }

        return evidence
    }
}

private enum BrowserContentHeuristic {
    private static let educationalTerms = [
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

    private static let entertainmentHosts = [
        "netflix.com",
        "twitch.tv",
        "hulu.com",
        "disneyplus.com",
        "steampowered.com",
        "store.steampowered.com",
        "epicgames.com"
    ]

    private static let entertainmentTerms = [
        "gaming",
        "gameplay",
        "livestream",
        "live-stream",
        "watch-movie",
        "watch-tv",
        "entertainment",
        "netflix",
        "twitch"
    ]

    static func isEntertainment(url: URL?) -> Bool {
        guard let url else { return false }
        let host = url.host?.lowercased() ?? ""
        if entertainmentHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }

        let searchableURL = url.absoluteString.lowercased()
        return entertainmentTerms.contains(where: searchableURL.contains)
    }

    static func isEducationalContent(url: URL?, title: String) -> Bool {
        guard let url else { return false }
        let host = url.host?.lowercased() ?? ""
        guard host.contains("youtube.com") || host.contains("youtu.be") || host.contains("vimeo.com") else {
            return false
        }

        let searchable = [
            host,
            url.absoluteString.lowercased(),
            ContextSanitizer.sanitizeTitle(title).lowercased()
        ]
        .joined(separator: " ")

        return educationalTerms.contains(where: searchable.contains)
    }
}
