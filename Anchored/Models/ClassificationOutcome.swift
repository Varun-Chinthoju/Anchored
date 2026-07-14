import Foundation
import GRDB

struct ClassificationOutcome: Codable, Equatable, Sendable {
    struct Identity: Codable, Equatable, Hashable, Sendable {
        let contextGeneration: Int
        let sessionID: UUID?
        let contextIdentity: ContextIdentity

        var key: String {
            let sessionPart = sessionID?.uuidString ?? "none"
            let urlPart = contextIdentity.sanitizedURL ?? "nil"
            return "\(contextGeneration)|\(sessionPart)|\(contextIdentity.bundleID)|\(urlPart)|\(contextIdentity.normalizedTitle)"
        }
    }

    let id: UUID
    let observedAt: Date
    let identity: Identity
    let appName: String
    let intentSummary: String?
    let relation: IntentRelation
    let mappedLabel: ClassificationLabel
    let confidence: Double
    let source: ClassificationSource
    let modelVersion: String
    let latency: TimeInterval
    let graceStarted: Bool
    let enforcementOccurred: Bool
    let correction: ClassificationCorrection?
    let correctedAt: Date?

    init(
        id: UUID = UUID(),
        observedAt: Date = Date(),
        identity: Identity,
        appName: String,
        intentSummary: String? = nil,
        relation: IntentRelation,
        mappedLabel: ClassificationLabel,
        confidence: Double,
        source: ClassificationSource,
        modelVersion: String,
        latency: TimeInterval,
        graceStarted: Bool,
        enforcementOccurred: Bool,
        correction: ClassificationCorrection? = nil,
        correctedAt: Date? = nil
    ) {
        self.id = id
        self.observedAt = observedAt
        self.identity = identity
        self.appName = appName
        self.intentSummary = intentSummary
        self.relation = relation
        self.mappedLabel = mappedLabel
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.source = source
        self.modelVersion = modelVersion
        self.latency = max(latency, 0.0)
        self.graceStarted = graceStarted
        self.enforcementOccurred = enforcementOccurred
        self.correction = correction
        self.correctedAt = correctedAt
    }

    func sanitizedForPersistence() -> ClassificationOutcome {
        let sanitizedIdentity = Identity(
            contextGeneration: identity.contextGeneration,
            sessionID: identity.sessionID,
            contextIdentity: ContextIdentity(
                bundleID: identity.contextIdentity.bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
                sanitizedURL: identity.contextIdentity.sanitizedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                normalizedTitle: identity.contextIdentity.normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )

        return ClassificationOutcome(
            id: id,
            observedAt: observedAt,
            identity: sanitizedIdentity,
            appName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
            intentSummary: intentSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
            relation: relation,
            mappedLabel: mappedLabel,
            confidence: confidence,
            source: source,
            modelVersion: modelVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            latency: latency,
            graceStarted: graceStarted,
            enforcementOccurred: enforcementOccurred,
            correction: correction,
            correctedAt: correctedAt
        )
    }

    static func make(
        bundleID: String,
        appName: String,
        contextGeneration: Int,
        sessionID: UUID?,
        contextIdentity: ContextIdentity,
        intentSummary: String?,
        relation: IntentRelation,
        mappedLabel: ClassificationLabel,
        confidence: Double,
        source: ClassificationSource,
        modelVersion: String,
        latency: TimeInterval,
        graceStarted: Bool,
        enforcementOccurred: Bool,
        correction: ClassificationCorrection? = nil,
        correctedAt: Date? = nil,
        observedAt: Date = Date()
    ) -> ClassificationOutcome {
        ClassificationOutcome(
            observedAt: observedAt,
            identity: Identity(
                contextGeneration: contextGeneration,
                sessionID: sessionID,
                contextIdentity: ContextIdentity(
                    bundleID: bundleID,
                    sanitizedURL: contextIdentity.sanitizedURL,
                    normalizedTitle: contextIdentity.normalizedTitle
                )
            ),
            appName: appName,
            intentSummary: intentSummary,
            relation: relation,
            mappedLabel: mappedLabel,
            confidence: confidence,
            source: source,
            modelVersion: modelVersion,
            latency: latency,
            graceStarted: graceStarted,
            enforcementOccurred: enforcementOccurred,
            correction: correction,
            correctedAt: correctedAt
        ).sanitizedForPersistence()
    }
}

extension ClassificationOutcome: FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "classification_outcomes"

    init(row: Row) {
        id = (row["id"] as UUID?) ?? UUID()
        observedAt = row["timestamp"] ?? Date.distantPast
        identity = Identity(
            contextGeneration: row["contextGeneration"] ?? 0,
            sessionID: row["sessionID"],
            contextIdentity: ContextIdentity(
                bundleID: row["bundleID"] ?? "",
                sanitizedURL: row["url"],
                normalizedTitle: row["title"] ?? ""
            )
        )
        appName = row["appName"] ?? ""
        intentSummary = row["intentSummary"]
        relation = IntentRelation(rawValue: row["relation"] ?? "uncertain") ?? .uncertain
        mappedLabel = ClassificationLabel(rawValue: row["mappedLabel"] ?? "neutral") ?? .neutral
        confidence = row["confidence"] ?? 0
        source = ClassificationSource(rawValue: row["source"] ?? "neutralFallback") ?? .neutralFallback
        modelVersion = row["modelVersion"] ?? ""
        latency = row["latency"] ?? 0
        graceStarted = row["graceStarted"] ?? false
        enforcementOccurred = row["enforcementOccurred"] ?? false
        correction = ClassificationCorrection(rawValue: row["correction"] ?? "")
        correctedAt = row["correctedAt"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["timestamp"] = observedAt
        container["identityKey"] = identity.key
        container["contextGeneration"] = identity.contextGeneration
        container["sessionID"] = identity.sessionID
        container["bundleID"] = identity.contextIdentity.bundleID
        container["appName"] = appName
        container["url"] = identity.contextIdentity.sanitizedURL
        container["title"] = identity.contextIdentity.normalizedTitle
        container["intentSummary"] = intentSummary
        container["relation"] = relation.rawValue
        container["mappedLabel"] = mappedLabel.rawValue
        container["confidence"] = confidence
        container["source"] = source.rawValue
        container["modelVersion"] = modelVersion
        container["latency"] = latency
        container["graceStarted"] = graceStarted
        container["enforcementOccurred"] = enforcementOccurred
        container["correction"] = correction?.rawValue
        container["correctedAt"] = correctedAt
    }
}
