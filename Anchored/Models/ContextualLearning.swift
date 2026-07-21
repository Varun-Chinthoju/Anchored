import Foundation

public enum ContextualPageCategory: String, Codable, Equatable, CaseIterable, Sendable {
    case chat
    case community
    case code
    case docs
    case messaging
    case social
    case video
    case general
}

public enum ContextualIntentCategory: String, Codable, Equatable, CaseIterable, Sendable {
    case coding
    case writing
    case research
    case communication
    case design
    case general
}

public struct ContextualLearningRecord: Codable, Equatable, Sendable {
    public let normalizedDomain: String
    public let pageCategory: ContextualPageCategory
    public let intentCategory: ContextualIntentCategory
    public let decision: ClassificationLabel
    public let timestamp: Date

    public init(
        normalizedDomain: String,
        pageCategory: ContextualPageCategory,
        intentCategory: ContextualIntentCategory,
        decision: ClassificationLabel,
        timestamp: Date = Date()
    ) {
        self.normalizedDomain = normalizedDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.pageCategory = pageCategory
        self.intentCategory = intentCategory
        self.decision = decision
        self.timestamp = timestamp
    }
}

