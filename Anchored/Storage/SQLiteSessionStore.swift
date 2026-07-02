import Foundation
import GRDB

class SQLiteSessionStore {
    static let shared = SQLiteSessionStore()
    
    let dbQueue: DatabaseQueue
    let queue = DispatchQueue(label: "com.varun.Anchored.SQLiteSessionStore", qos: .utility)
    private let databaseURL: URL
    
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
            try setupDatabase()
        } catch {
            fatalError("Failed to initialize SQLite database: \(error)")
        }
    }
    
    private func setupDatabase() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                timestamp DATETIME NOT NULL,
                type TEXT NOT NULL,
                appBundleID TEXT NOT NULL,
                appName TEXT NOT NULL,
                url TEXT,
                focusDurationSeconds INTEGER,
                sessionDurationSeconds INTEGER,
                distractionAppBundleID TEXT,
                distraction_domain TEXT,
                action TEXT,
                category TEXT,
                sessionGoal TEXT
            );
            """)
            
            // Perform schema migration if columns are missing
            let columns = try db.columns(in: "sessions")
            let hasCategory = columns.contains { $0.name == "category" }
            if !hasCategory {
                try db.execute(sql: "ALTER TABLE sessions ADD COLUMN category TEXT;")
                try db.execute(sql: "ALTER TABLE sessions ADD COLUMN sessionGoal TEXT;")
            }
            
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_sessions_timestamp ON sessions(timestamp);")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_sessions_type ON sessions(type);")
        }
    }
    
    func log(_ event: SessionEvent) {
        queue.async {
            do {
                try self.dbQueue.write { db in
                    try event.insert(db)
                }
            } catch {
                print("SQLiteSessionStore Error: Failed to log event. \(error.localizedDescription)")
            }
        }
    }
    
    func recentSessions(limit: Int) -> [SessionEvent] {
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
                        let exists = try SessionEvent.fetchOne(db, key: event.id) != nil
                        if !exists {
                            try event.insert(db)
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

extension SessionEvent: FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "sessions"
}
