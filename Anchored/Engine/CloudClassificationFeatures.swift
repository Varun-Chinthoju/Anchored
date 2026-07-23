import Foundation

public enum CloudAppCategory: String, Codable, CaseIterable, Sendable {
    case editor
    case browser
    case communication
    case media
    case unknown
}

public enum CloudDomainCategory: String, Codable, CaseIterable, Sendable {
    case developer
    case documentation
    case entertainment
    case social
    case general
    case none
}

public enum CloudTitleFeature: String, Codable, CaseIterable, Hashable, Sendable {
    case code
    case documentation
    case meeting
    case media
    case socialFeed
    case socialProfile
    case socialPost
    case unknown
}

public struct CloudClassificationInput: Codable, Equatable, Sendable {
    public let appCategory: CloudAppCategory
    public let domainCategory: CloudDomainCategory
    public let titleFeatures: [CloudTitleFeature]
    public let source: ContextSnapshot.Source

    public init(
        appCategory: CloudAppCategory,
        domainCategory: CloudDomainCategory,
        titleFeatures: [CloudTitleFeature],
        source: ContextSnapshot.Source
    ) {
        self.appCategory = appCategory
        self.domainCategory = domainCategory
        self.titleFeatures = Array(Set(titleFeatures)).sorted { $0.rawValue < $1.rawValue }
        self.source = source
    }
}

enum CloudClassificationFeatureExtractor {
    static func make(
        appName: String,
        bundleID: String? = nil,
        url: URL?,
        title: String,
        source: ContextSnapshot.Source
    ) -> CloudClassificationInput {
        let appText = [appName, bundleID ?? ""].joined(separator: " ").lowercased()
        let titleText = ContextSanitizer.sanitizeTitle(title).lowercased()
        let host = url?.host?.lowercased() ?? ""
        let path = url?.path.lowercased() ?? ""
        let searchableDomain = "\(host)\(path)"

        let appCategory: CloudAppCategory
        if source != .application || appText.contains("safari") || appText.contains("chrome") || appText.contains("firefox") {
            appCategory = .browser
        } else if ["xcode", "vscode", "visual studio", "terminal", "iterm", "textedit", "word", "pages", "figma", "notion", "obsidian"]
            .contains(where: appText.contains) {
            appCategory = .editor
        } else if ["discord", "slack", "messages", "mail", "telegram", "zoom", "teams"]
            .contains(where: appText.contains) {
            appCategory = .communication
        } else if ["spotify", "music", "netflix", "twitch", "steam", "tv"]
            .contains(where: appText.contains) {
            appCategory = .media
        } else {
            appCategory = .unknown
        }

        let domainCategory: CloudDomainCategory
        if host.isEmpty {
            domainCategory = .none
        } else if ["github", "stackoverflow", "developer", "npm", "pypi", "docker", "kubernetes", "gitlab"]
            .contains(where: searchableDomain.contains) {
            domainCategory = .developer
        } else if ["docs", "documentation", "mdn", "w3schools", "api", "reference", "learn"]
            .contains(where: searchableDomain.contains) {
            domainCategory = .documentation
        } else if ["youtube", "netflix", "twitch", "tiktok", "spotify", "hulu", "disney"]
            .contains(where: searchableDomain.contains) {
            domainCategory = .entertainment
        } else if ["reddit", "twitter", "x.com", "instagram", "facebook"]
            .contains(where: searchableDomain.contains) {
            domainCategory = .social
        } else {
            domainCategory = .general
        }

        var titleFeatures: [CloudTitleFeature] = []
        if ["swift", "code", "coding", "programming", "function", "class", "api", "compiler"]
            .contains(where: titleText.contains) {
            titleFeatures.append(.code)
        }
        if ["documentation", "docs", "reference", "tutorial", "learn", "guide"]
            .contains(where: titleText.contains) {
            titleFeatures.append(.documentation)
        }
        if ["meeting", "standup", "calendar", "zoom", "teams"]
            .contains(where: titleText.contains) {
            titleFeatures.append(.meeting)
        }
        if ["video", "movie", "music", "livestream", "game", "gaming"]
            .contains(where: titleText.contains) {
            titleFeatures.append(.media)
        }
        if ["home", "feed", "for you", "explore", "trending", "following", "timeline", "notifications", "bookmarks"]
            .contains(where: searchableDomain.contains) || ["home", "feed", "for you", "explore", "trending", "following", "timeline", "notifications", "bookmarks"]
            .contains(where: titleText.contains) {
            titleFeatures.append(.socialFeed)
        }
        if ["profile", "status", "post", "thread", "reply", "replies", "discussion"]
            .contains(where: searchableDomain.contains) || ["profile", "status", "post", "thread", "reply", "replies", "discussion"]
            .contains(where: titleText.contains) {
            titleFeatures.append(.socialPost)
        }
        if ["user", "about", "followers", "following", "connections"]
            .contains(where: searchableDomain.contains) || ["user", "about", "followers", "following", "connections"]
            .contains(where: titleText.contains) {
            titleFeatures.append(.socialProfile)
        }
        if titleFeatures.isEmpty {
            titleFeatures = [.unknown]
        }

        return CloudClassificationInput(
            appCategory: appCategory,
            domainCategory: domainCategory,
            titleFeatures: titleFeatures,
            source: source
        )
    }
}

struct CloudStructuredResponse: Codable {
    let label: ClassificationLabel
    let confidence: Double
    let explanation: String?
}
