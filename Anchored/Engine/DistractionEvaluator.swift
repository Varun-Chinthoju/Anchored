import Foundation

/// The deterministic, synchronous classification boundary used by FocusEngine.
///
/// A decision here is final for explicit rules. Optional visual and cloud services may
/// only promote a neutral decision after FocusEngine verifies the context is still current.
enum ContextDisposition: Equatable {
    case focus
    case distraction
    case neutral
}

enum ContextDecisionSource: Equatable {
    case explicitAllowedDomain
    case explicitBlockedDomain
    case profileAllowedApp
    case profileBlockedApp
    case browserHeuristic
    case localHeuristic
    case neutralFallback
}

struct ContextDecision: Equatable {
    let disposition: ContextDisposition
    let source: ContextDecisionSource

    var isFocus: Bool { disposition == .focus }
    var isDistraction: Bool { disposition == .distraction }
}

/// Keeps rule precedence independent from timers, persistence, overlays, and async work.
final class DistractionEvaluator {
    private let distractionListManager: DistractionListManager
    private let profileProvider: () -> WorkProfile

    init(
        distractionListManager: DistractionListManager,
        profileProvider: @escaping () -> WorkProfile
    ) {
        self.distractionListManager = distractionListManager
        self.profileProvider = profileProvider
    }

    func evaluate(bundleID: String, url: URL?, title: String) -> ContextDecision {
        let profile = profileProvider()

        // URL rules are more specific than application rules. Within a level, an
        // explicit allow is intentional and wins over a conflicting explicit block.
        if let url, URLMatcher.matches(url: url, domains: profile.allowedDomains) {
            return ContextDecision(disposition: .focus, source: .explicitAllowedDomain)
        }

        if let url, URLMatcher.matches(url: url, domains: profile.distractionDomains) {
            return ContextDecision(disposition: .distraction, source: .explicitBlockedDomain)
        }

        if BrowserStrategyFactory.isSupportedBrowser(bundleID) {
            guard url != nil else {
                return ContextDecision(disposition: .neutral, source: .neutralFallback)
            }

            if BrowserContentHeuristic.isEntertainment(url: url, title: title) {
                return ContextDecision(disposition: .distraction, source: .browserHeuristic)
            }

            if SmartWebClassifier.isCodingForumOrDoc(url: url, title: title) {
                return ContextDecision(disposition: .focus, source: .localHeuristic)
            }
        }

        if profile.allowedApps.contains(bundleID) {
            return ContextDecision(disposition: .focus, source: .profileAllowedApp)
        }

        if profile.distractionApps.contains(bundleID) {
            return ContextDecision(disposition: .distraction, source: .profileBlockedApp)
        }

        if SmartAppClassifier.isProductiveApp(bundleID: bundleID) {
            return ContextDecision(disposition: .focus, source: .localHeuristic)
        }

        return ContextDecision(disposition: .neutral, source: .neutralFallback)
    }
}

private enum BrowserContentHeuristic {
    private static let entertainmentHosts = [
        "youtube.com",
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
        "live stream",
        "watch movie",
        "watch tv",
        "entertainment",
        "netflix",
        "twitch"
    ]

    static func isEntertainment(url: URL?, title: String) -> Bool {
        let host = url?.host?.lowercased() ?? ""
        if entertainmentHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }

        let searchableText = "\(title) \(url?.path ?? "")".lowercased()
        return entertainmentTerms.contains(where: searchableText.contains)
    }
}
