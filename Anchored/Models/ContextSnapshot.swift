import Foundation

public struct ContextSnapshot: Codable, Equatable {
    public enum Source: String, Codable, Equatable, Sendable {
        case application
        case chromium
        case safari
        case firefox
    }

    public let bundleIdentifier: String
    public let localizedName: String
    public let url: URL?
    public let title: String
    public let source: Source
    public let observedAt: Date

    public init(
        bundleIdentifier: String,
        localizedName: String,
        url: URL?,
        title: String,
        source: Source,
        observedAt: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.url = url
        self.title = title
        self.source = source
        self.observedAt = observedAt
    }

    public var identity: ContextIdentity {
        ContextIdentity(
            bundleID: bundleIdentifier,
            sanitizedURL: ContextSanitizer.sanitizePersistedURL(url),
            normalizedTitle: ContextSanitizer.sanitizeTitle(title)
        )
    }
}

public struct ContextIdentity: Codable, Equatable, Hashable {
    public let bundleID: String
    public let sanitizedURL: String?
    public let normalizedTitle: String

    public init(bundleID: String, sanitizedURL: String?, normalizedTitle: String) {
        self.bundleID = bundleID
        self.sanitizedURL = sanitizedURL
        self.normalizedTitle = normalizedTitle
    }
}
