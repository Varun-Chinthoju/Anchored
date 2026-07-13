import Foundation
import GRDB

public enum ClassificationCorrection: String, Codable, Equatable, CaseIterable {
    case allowApp
    case blockApp
    case allowDomain
    case blockDomain
    case markSessionProductive
}

struct ClassificationFeedback: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let bundleID: String
    let domain: String?
    let originalLabel: ClassificationLabel
    let correctedLabel: ClassificationLabel
    let correction: ClassificationCorrection
    let source: ClassificationSource

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bundleID: String,
        domain: String?,
        originalLabel: ClassificationLabel,
        correctedLabel: ClassificationLabel,
        correction: ClassificationCorrection,
        source: ClassificationSource
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = domain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.originalLabel = originalLabel
        self.correctedLabel = correctedLabel
        self.correction = correction
        self.source = source
    }
}

extension ClassificationFeedback: FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "classification_feedback"

    init(row: Row) {
        id = row["id"] ?? UUID()
        createdAt = row["createdAt"] ?? Date.distantPast
        bundleID = row["bundleID"] ?? ""
        domain = row["domain"]
        originalLabel = ClassificationLabel(rawValue: row["originalLabel"] ?? "neutral") ?? .neutral
        correctedLabel = ClassificationLabel(rawValue: row["correctedLabel"] ?? "neutral") ?? .neutral
        correction = ClassificationCorrection(rawValue: row["correction"] ?? "markSessionProductive") ?? .markSessionProductive
        source = ClassificationSource(rawValue: row["source"] ?? "neutralFallback") ?? .neutralFallback
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["createdAt"] = createdAt
        container["bundleID"] = bundleID
        container["domain"] = domain
        container["originalLabel"] = originalLabel.rawValue
        container["correctedLabel"] = correctedLabel.rawValue
        container["correction"] = correction.rawValue
        container["source"] = source.rawValue
    }
}
