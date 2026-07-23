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
            let isEducationalVideo = BrowserContentHeuristic.isEducationalContent(url: url, title: title)
            let pageCategory = ContextualSiteHeuristic.pageCategory(for: url, title: title)

            if isMixedUseContext {
                evidence.append(ClassificationEvidence(
                    label: .contextual,
                    source: .heuristic,
                    confidence: 0.65,
                    reason: .contextualMixedUse
                ))
            }

            if pageCategory == .social {
                switch SocialContentHeuristic.signal(url: url, title: title) {
                case .productive:
                    evidence.append(ClassificationEvidence(
                        label: .productive,
                        source: .deterministicRule,
                        confidence: 0.85,
                        reason: .deterministicHeuristic
                    ))
                case .distracting:
                    evidence.append(ClassificationEvidence(
                        label: .distracting,
                        source: .deterministicRule,
                        confidence: 0.90,
                        reason: .deterministicHeuristic
                    ))
                case .unknown:
                    break
                }
            }

            if isEducationalVideo {
                // Educational video content should stay neutral unless another
                // explicit rule or stronger intent signal says otherwise.
            } else if BrowserContentHeuristic.isVideoPlatform(url: url) {
                // Generic video browsing should still be treated as a real
                // distraction even when the page is mixed-use.
                evidence.append(ClassificationEvidence(
                    label: .distracting,
                    source: .deterministicRule,
                    confidence: 0.90,
                    reason: .deterministicHeuristic
                ))
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
        "epicgames.com",
        "x.com",
        "twitter.com",
        "facebook.com",
        "instagram.com",
        "tiktok.com",
        "linkedin.com"
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

    static func isVideoPlatform(url: URL?) -> Bool {
        guard let url else { return false }
        let host = url.host?.lowercased() ?? ""
        return host.contains("youtube.com") || host.contains("youtu.be") || host.contains("vimeo.com")
    }

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
        guard let url, isVideoPlatform(url: url) else {
            return false
        }
        let host = url.host?.lowercased() ?? ""

        let searchable = [
            host,
            url.absoluteString.lowercased(),
            ContextSanitizer.sanitizeTitle(title).lowercased()
        ]
        .joined(separator: " ")

        return educationalTerms.contains(where: searchable.contains)
    }
}

private enum SocialContentHeuristic {
    private static let productiveTerms = [
        "code",
        "coding",
        "programming",
        "software",
        "developer",
        "development",
        "swift",
        "xcode",
        "tutorial",
        "documentation",
        "docs",
        "learn",
        "build",
        "api",
        "stack overflow",
        "github",
        "open source"
    ]

    private static let distractingTerms = [
        "home",
        "feed",
        "for you",
        "explore",
        "trending",
        "following",
        "notifications",
        "bookmarks",
        "messages",
        "inbox",
        "reels",
        "shorts",
        "watch",
        "discover",
        "popular",
        "recommended",
        "suggested"
    ]

    enum Signal {
        case productive
        case distracting
        case unknown
    }

    static func signal(url: URL?, title: String) -> Signal {
        let searchable = [
            url?.absoluteString.lowercased() ?? "",
            ContextSanitizer.sanitizeTitle(title).lowercased()
        ]
        .joined(separator: " ")

        if productiveTerms.contains(where: searchable.contains) {
            return .productive
        }

        if distractingTerms.contains(where: searchable.contains) {
            return .distracting
        }

        return .unknown
    }
}
