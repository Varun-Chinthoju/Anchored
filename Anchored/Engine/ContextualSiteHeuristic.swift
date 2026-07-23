import Foundation

enum ContextualSiteHeuristic {
    private static let contextualDomains: Set<String> = [
        "chatgpt.com",
        "claude.ai",
        "gemini.google.com",
        "notebooklm.google.com",
        "reddit.com",
        "youtu.be",
        "youtube.com",
        "discord.com",
        "x.com",
        "twitter.com",
        "linkedin.com",
        "facebook.com",
        "instagram.com",
        "tiktok.com"
    ]

    static func normalizedDomain(for url: URL?) -> String? {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func pageCategory(for url: URL?, title: String) -> ContextualPageCategory {
        guard let domain = normalizedDomain(for: url) else { return .general }

        if domain.contains("chatgpt.com") || domain.contains("claude.ai") || domain.contains("gemini.google.com") || domain.contains("notebooklm.google.com") {
            return .chat
        }
        if domain.contains("reddit.com") || domain.contains("news.ycombinator.com") {
            return .community
        }
        if domain.contains("youtube.com") || domain.contains("youtu.be") {
            return .video
        }
        if domain.contains("discord.com") {
            return .messaging
        }
        if domain.contains("github.com") || title.lowercased().contains("stackoverflow") || domain.contains("stackoverflow.com") {
            return .code
        }
        if domain.contains("docs.") || domain.contains("notion.so") || domain.contains("readthedocs.org") || domain.contains("confluence.") {
            return .docs
        }
        if domain.contains("x.com") || domain.contains("twitter.com") || domain.contains("facebook.com") || domain.contains("instagram.com") || domain.contains("tiktok.com") || domain.contains("linkedin.com") {
            return .social
        }
        return .general
    }

    static func intentCategory(for focusIntent: FocusIntent?) -> ContextualIntentCategory {
        let text = [
            focusIntent?.sanitizedGoal,
            focusIntent?.baseline?.activeProfileName,
            focusIntent?.baseline?.activeProfileCategory
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if containsAny(["code", "coding", "programming", "developer", "development", "swift", "xcode"], in: text) {
            return .coding
        }
        if containsAny(["write", "writing", "docs", "documentation", "draft", "blog"], in: text) {
            return .writing
        }
        if containsAny(["research", "learn", "study", "reading", "read"], in: text) {
            return .research
        }
        if containsAny(["meeting", "email", "message", "chat", "communic"], in: text) {
            return .communication
        }
        if containsAny(["design", "figma", "mockup", "wireframe"], in: text) {
            return .design
        }

        return .general
    }

    static func reviewScope(for bundleID: String, url: URL?, title: String) -> ProductiveCorrectionScope {
        guard BrowserStrategyFactory.isSupportedBrowser(bundleID) else {
            return .app
        }

        guard url?.host?.isEmpty == false else {
            return .app
        }

        return isMixedUseContext(url: url, title: title) ? .page : .website
    }

    static func reviewChoices(for bundleID: String, url: URL?, title: String) -> [ProductiveCorrectionScope] {
        guard BrowserStrategyFactory.isSupportedBrowser(bundleID), url?.host?.isEmpty == false else {
            return [.app]
        }

        let recommendedScope = reviewScope(for: bundleID, url: url, title: title)
        switch recommendedScope {
        case .page:
            return [.page, .website, .app]
        case .website:
            return [.website, .page, .app]
        case .app:
            return [.app]
        }
    }

    static func reviewActionTitle() -> String {
        return "Review Current Item"
    }

    static func isMixedUseContext(url: URL?, title: String) -> Bool {
        guard let domain = normalizedDomain(for: url) else { return false }
        if contextualDomains.contains(domain) {
            return true
        }

        switch pageCategory(for: url, title: title) {
        case .chat, .community, .messaging, .video:
            return true
        case .code, .docs, .general:
            return false
        case .social:
            return true
        }
    }

    static func learningKey(
        normalizedDomain: String,
        pageCategory: ContextualPageCategory,
        intentCategory: ContextualIntentCategory
    ) -> String {
        "\(normalizedDomain)|\(pageCategory.rawValue)|\(intentCategory.rawValue)"
    }

    private static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
