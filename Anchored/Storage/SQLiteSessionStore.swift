import Foundation
import GRDB

typealias StorageWriteCompletion = (Result<Void, Error>) -> Void

class SQLiteSessionStore {
    static let shared = SQLiteSessionStore()
    
    let dbQueue: DatabaseQueue
    let queue = DispatchQueue(label: "com.varun.Anchored.SQLiteSessionStore", qos: .utility)
    private let databaseURL: URL
    private(set) var migrationError: Error?
    
    init(databaseURL: URL? = nil) {
        let fileManager = FileManager.default
        let url: URL
        if let customURL = databaseURL {
            url = customURL
        } else {
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectoryURL = appSupportURL.appendingPathComponent("Anchored")
            url = appDirectoryURL.appendingPathComponent("anchored.db")
        }
        self.databaseURL = url
        
        if url.scheme == "file" {
            let directoryURL = url.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
        }
        
        do {
            if url.absoluteString == "file::memory:" || (url.scheme != "file" && url.path.isEmpty) {
                self.dbQueue = try DatabaseQueue()
            } else {
                self.dbQueue = try DatabaseQueue(path: url.path)
            }
            migrateDatabase()
        } catch {
            fatalError("Failed to initialize SQLite database: \(error)")
        }
    }
    
    private func migrateDatabase() {
        do {
            try SQLiteDatabaseMigrations.makeMigrator().migrate(dbQueue)
        } catch {
            migrationError = error
            print("SQLiteSessionStore Error: Database migration failed. \(error.localizedDescription)")
        }
    }
    
    func log(_ event: SessionEvent, completion: StorageWriteCompletion? = nil) {
        let persistedEvent = event.persistedCopy()
        queue.async {
            do {
                try self.dbQueue.write { db in
                    try persistedEvent.insert(db)
                }
                print("💾 [DB Event Logged] Type: \(persistedEvent.type.rawValue) | AppName: \(persistedEvent.appName) | Duration: \(persistedEvent.sessionDurationSeconds ?? 0)s")
                self.finishWrite(completion, with: .success(()))
            } catch {
                print("SQLiteSessionStore Error: Failed to log event. \(error.localizedDescription)")
                self.finishWrite(completion, with: .failure(error))
            }
        }
    }
    
    private func warnIfMainThreadIfNeeded(caller: String = #function) {
        if Thread.isMainThread {
            print("⚠️ [MainThreadSQLite] \(caller) called on main thread - consider async.")
        }
    }

    func recentSessions(limit: Int) -> [SessionEvent] {
        warnIfMainThreadIfNeeded()
        return queue.sync {
            do {
                return try dbQueue.read { db in
                    let request = SessionEvent
                        .filter(Column("type") == SessionEventType.sessionEnd.rawValue)
                        .order(Column("timestamp").desc, Column("rowid").desc)
                        .limit(limit)
                    return try request.fetchAll(db)
                }
            } catch {
                print("SQLiteSessionStore Error: Failed to fetch recent sessions. \(error.localizedDescription)")
                return []
            }
        }
    }
    
    func allEvents() -> [SessionEvent] {
        warnIfMainThreadIfNeeded()
        return queue.sync {
            do {
                return try dbQueue.read { db in
                    try SessionEvent.order(Column("timestamp").asc, Column("rowid").asc).fetchAll(db)
                }
            } catch {
                print("SQLiteSessionStore Error: Failed to fetch all events. \(error.localizedDescription)")
                return []
            }
        }
    }

    func recordedEvents() -> [SessionEvent] {
        queue.sync {
            do {
                return try dbQueue.read { db in
                    try SessionEvent.order(Column("timestamp").asc, Column("rowid").asc).fetchAll(db)
                }
            } catch {
                print("SQLiteSessionStore Error: Failed to fetch all recorded events. \(error.localizedDescription)")
                return []
            }
        }
    }

    func fetchRecentSessions(limit: Int, completion: @escaping ([SessionEvent]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let sessions = self.queue.sync {
                (try? self.dbQueue.read { db in
                    try SessionEvent
                        .filter(Column("type") == SessionEventType.sessionEnd.rawValue)
                        .order(Column("timestamp").desc, Column("rowid").desc)
                        .limit(limit)
                        .fetchAll(db)
                }) ?? []
            }
            DispatchQueue.main.async { completion(sessions) }
        }
    }

    func insertContextObservation(_ observation: PersistedContextObservation) throws {
        let sanitizedObservation = observation.sanitizedForPersistence()
        try dbQueue.write { db in
            try sanitizedObservation.insert(db)
        }
    }

    func deleteAllContextObservations() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM context_observations;")
        }
    }

    func deleteContextObservations(olderThan cutoffDate: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM context_observations WHERE timestamp < ?;",
                arguments: [cutoffDate]
            )
        }
    }

    func contextObservationCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM context_observations;") ?? 0
        }
    }

    func oldestContextObservationDate() throws -> Date? {
        try dbQueue.read { db in
            try Date.fetchOne(
                db,
                sql: "SELECT timestamp FROM context_observations ORDER BY timestamp ASC, rowid ASC LIMIT 1;"
            )
        }
    }

    func latestContextObservationIdentity() throws -> PersistedContextObservation.Identity? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT bundleID, url AS sanitizedURL, title
                FROM context_observations
                ORDER BY timestamp DESC, rowid DESC
                LIMIT 1
                """
            ) else {
                return nil
            }

            return PersistedContextObservation.Identity(
                bundleID: row["bundleID"],
                sanitizedURL: row["sanitizedURL"],
                title: row["title"]
            )
        }
    }

    func insertContextualLearningRecord(_ record: ContextualLearningRecord) throws {
        let normalizedDomain = record.normalizedDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO contextual_learning (
                    timestamp,
                    normalizedDomain,
                    pageCategory,
                    intentCategory,
                    decision
                ) VALUES (?, ?, ?, ?, ?);
                """,
                arguments: [
                    record.timestamp,
                    normalizedDomain,
                    record.pageCategory.rawValue,
                    record.intentCategory.rawValue,
                    record.decision.rawValue
                ]
            )
        }
    }

    func fetchContextualLearningRecords() throws -> [ContextualLearningRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT timestamp, normalizedDomain, pageCategory, intentCategory, decision
                FROM contextual_learning
                ORDER BY timestamp ASC, rowid ASC
                """
            ).map { row in
                ContextualLearningRecord(
                    normalizedDomain: row["normalizedDomain"],
                    pageCategory: ContextualPageCategory(rawValue: row["pageCategory"] ?? "") ?? .general,
                    intentCategory: ContextualIntentCategory(rawValue: row["intentCategory"] ?? "") ?? .general,
                    decision: ClassificationLabel(rawValue: row["decision"] ?? "") ?? .contextual,
                    timestamp: row["timestamp"] ?? Date.distantPast
                )
            }
        }
    }

    func deleteAllContextualLearningRecords() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM contextual_learning;")
        }
    }

    func deleteContextualLearningRecords(olderThan cutoffDate: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM contextual_learning WHERE timestamp < ?;",
                arguments: [cutoffDate]
            )
        }
    }

    func insertClassificationFeedback(_ feedback: ClassificationFeedback) throws {
        try dbQueue.write { db in
            try feedback.insert(db)
        }
    }

    func deleteAllClassificationFeedback() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM classification_feedback;")
        }
    }

    func deleteClassificationFeedback(olderThan cutoffDate: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM classification_feedback WHERE createdAt < ?;",
                arguments: [cutoffDate]
            )
        }
    }

    func classificationFeedbackCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM classification_feedback;") ?? 0
        }
    }

    func oldestClassificationFeedbackDate() throws -> Date? {
        try dbQueue.read { db in
            try Date.fetchOne(
                db,
                sql: "SELECT createdAt FROM classification_feedback ORDER BY createdAt ASC, rowid ASC LIMIT 1;"
            )
        }
    }

    func insertClassificationOutcome(_ outcome: ClassificationOutcome) throws {
        let sanitizedOutcome = outcome.sanitizedForPersistence()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO classification_outcomes (
                    identityKey,
                    timestamp,
                    id,
                    contextGeneration,
                    sessionID,
                    bundleID,
                    appName,
                    url,
                    title,
                    intentSummary,
                    relation,
                    mappedLabel,
                    confidence,
                    source,
                    modelVersion,
                    latency,
                    graceStarted,
                    enforcementOccurred,
                    correction,
                    correctedAt
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                );
                """,
                arguments: [
                    sanitizedOutcome.identity.key,
                    sanitizedOutcome.observedAt,
                    sanitizedOutcome.id,
                    sanitizedOutcome.identity.contextGeneration,
                    sanitizedOutcome.identity.sessionID,
                    sanitizedOutcome.identity.contextIdentity.bundleID,
                    sanitizedOutcome.appName,
                    sanitizedOutcome.identity.contextIdentity.sanitizedURL,
                    sanitizedOutcome.identity.contextIdentity.normalizedTitle,
                    sanitizedOutcome.intentSummary,
                    sanitizedOutcome.relation.rawValue,
                    sanitizedOutcome.mappedLabel.rawValue,
                    sanitizedOutcome.confidence,
                    sanitizedOutcome.source.rawValue,
                    sanitizedOutcome.modelVersion,
                    sanitizedOutcome.latency,
                    sanitizedOutcome.graceStarted,
                    sanitizedOutcome.enforcementOccurred,
                    sanitizedOutcome.correction?.rawValue,
                    sanitizedOutcome.correctedAt
                ]
            )
        }
    }

    func updateClassificationOutcomeCorrection(
        identityKey: String,
        correction: ClassificationCorrection,
        correctedAt: Date
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE classification_outcomes
                SET correction = ?, correctedAt = ?
                WHERE identityKey = ?;
                """,
                arguments: [correction.rawValue, correctedAt, identityKey]
            )
        }
    }

    func deleteAllClassificationOutcomes() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM classification_outcomes;")
        }
    }

    func deleteClassificationOutcomes(olderThan cutoffDate: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM classification_outcomes WHERE timestamp < ?;",
                arguments: [cutoffDate]
            )
        }
    }

    func classificationOutcomeCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM classification_outcomes;") ?? 0
        }
    }

    func oldestClassificationOutcomeDate() throws -> Date? {
        try dbQueue.read { db in
            try Date.fetchOne(
                db,
                sql: "SELECT timestamp FROM classification_outcomes ORDER BY timestamp ASC, rowid ASC LIMIT 1;"
            )
        }
    }

    func latestClassificationOutcomeIdentity() throws -> ClassificationOutcome.Identity? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT contextGeneration, sessionID, bundleID, url AS sanitizedURL, title
                FROM classification_outcomes
                ORDER BY timestamp DESC, rowid DESC
                LIMIT 1
                """
            ) else {
                return nil
            }

            return ClassificationOutcome.Identity(
                contextGeneration: row["contextGeneration"],
                sessionID: row["sessionID"],
                contextIdentity: ContextIdentity(
                    bundleID: row["bundleID"],
                    sanitizedURL: row["sanitizedURL"],
                    normalizedTitle: row["title"]
                )
            )
        }
    }

    /// Updates only the local user-authored summary for a completed session.
    /// Empty or oversized input clears the summary rather than persisting invalid text.
    func updateSessionSummary(id: UUID, summary: String?) throws {
        let sanitizedSummary = CommitmentPolicy.sanitizedSessionSummary(summary)
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET sessionSummary = ? WHERE id = ? AND type = ?",
                arguments: [sanitizedSummary, id, SessionEventType.sessionEnd.rawValue]
            )
        }
    }

    func clearAllSessionSummaries() throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE sessions SET sessionSummary = NULL")
        }
    }
    
    func migrateFromJSONIfNeeded(jsonURL: URL) {
        queue.sync {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: jsonURL.path) else {
                return
            }
            
            do {
                let data = try Data(contentsOf: jsonURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let events = try decoder.decode([SessionEvent].self, from: data)
                
                try dbQueue.write { db in
                    for event in events {
                        let persistedEvent = event.persistedCopy()
                        let exists = try SessionEvent.fetchOne(db, key: persistedEvent.id) != nil
                        if !exists {
                            try persistedEvent.insert(db)
                        }
                    }
                }
                
                let migratedURL = jsonURL.deletingPathExtension().appendingPathExtension("json.migrated")
                if fileManager.fileExists(atPath: migratedURL.path) {
                    try fileManager.removeItem(at: migratedURL)
                }
                try fileManager.moveItem(at: jsonURL, to: migratedURL)
                print("SQLiteSessionStore: Successfully migrated JSON sessions to SQLite.")
            } catch {
                print("SQLiteSessionStore Error: Failed to migrate legacy JSON data. \(error.localizedDescription)")
            }
        }
    }
}

private extension SQLiteSessionStore {
    func finishWrite(_ completion: StorageWriteCompletion?, with result: Result<Void, Error>) {
        guard let completion else { return }
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

extension SessionEvent: FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "sessions"
}
