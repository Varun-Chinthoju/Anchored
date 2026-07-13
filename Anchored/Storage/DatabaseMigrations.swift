import Foundation
import GRDB

enum SQLiteDatabaseMigrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_sessions_schema") { db in
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

            let columns = try db.columns(in: "sessions")
            let hasCategory = columns.contains { $0.name == "category" }
            if !hasCategory {
                try db.execute(sql: "ALTER TABLE sessions ADD COLUMN category TEXT;")
                try db.execute(sql: "ALTER TABLE sessions ADD COLUMN sessionGoal TEXT;")
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_sessions_timestamp ON sessions(timestamp);")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_sessions_type ON sessions(type);")
        }

        migrator.registerMigration("v2_create_context_observations") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS context_observations (
                id TEXT PRIMARY KEY,
                timestamp DATETIME NOT NULL,
                bundleID TEXT NOT NULL,
                appName TEXT NOT NULL,
                url TEXT,
                title TEXT,
                source TEXT NOT NULL,
                domain TEXT,
                sessionState TEXT NOT NULL DEFAULT 'idle'
            );
            """)

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_context_observations_timestamp ON context_observations(timestamp);")
        }

        migrator.registerMigration("v3_add_context_observation_metadata") { db in
            let columns = try db.columns(in: "context_observations")
            let hasDomain = columns.contains { $0.name == "domain" }
            let hasSessionState = columns.contains { $0.name == "sessionState" }

            if !hasDomain {
                try db.execute(sql: "ALTER TABLE context_observations ADD COLUMN domain TEXT;")
            }

            if !hasSessionState {
                try db.execute(sql: "ALTER TABLE context_observations ADD COLUMN sessionState TEXT NOT NULL DEFAULT 'idle';")
            }
        }

        migrator.registerMigration("v4_sanitize_legacy_session_urls") { db in
            let rows = try Row.fetchAll(db, sql: """
            SELECT id, url
            FROM sessions
            WHERE url IS NOT NULL
            """)

            for row in rows {
                let id: String = row["id"]
                let rawURL: String = row["url"]
                let sanitized = ContextSanitizer.sanitizePersistedURL(URL(string: rawURL))

                if sanitized != rawURL {
                    if let sanitized {
                        try db.execute(
                            sql: "UPDATE sessions SET url = ? WHERE id = ?",
                            arguments: [sanitized, id]
                        )
                    } else {
                        try db.execute(
                            sql: "UPDATE sessions SET url = NULL WHERE id = ?",
                            arguments: [id]
                        )
                    }
                }
            }
        }

        migrator.registerMigration("v5_create_classification_feedback") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS classification_feedback (
                id TEXT PRIMARY KEY,
                createdAt DATETIME NOT NULL,
                bundleID TEXT NOT NULL,
                domain TEXT,
                originalLabel TEXT NOT NULL,
                correctedLabel TEXT NOT NULL,
                correction TEXT NOT NULL,
                source TEXT NOT NULL
            );
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_classification_feedback_createdAt ON classification_feedback(createdAt);")
        }

        return migrator
    }
}
