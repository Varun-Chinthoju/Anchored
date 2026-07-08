import XCTest
import GRDB
@testable import Anchored

final class SQLiteMigrationTests: XCTestCase {
    private var tempDirectory: URL!
    private var dbURL: URL!

    override func setUp() {
        super.setUp()

        let fileManager = FileManager.default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("SQLiteMigrationTests-\(UUID().uuidString)")
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        dbURL = tempDirectory.appendingPathComponent("legacy.db")
    }

    override func tearDown() {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testLegacyDatabaseMigratesAndSanitizesSessionUrls() throws {
        try createLegacyDatabase()

        let firstStore = SQLiteSessionStore(databaseURL: dbURL)
        XCTAssertNil(firstStore.migrationError)

        let events = firstStore.allEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].url, "https://example.com/path")

        try firstStore.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("context_observations"))
            let observationColumns = try db.columns(in: "context_observations").map(\.name)
            XCTAssertTrue(observationColumns.contains("timestamp"))
            XCTAssertTrue(observationColumns.contains("bundleID"))
            XCTAssertTrue(observationColumns.contains("appName"))
            XCTAssertTrue(observationColumns.contains("url"))
            XCTAssertTrue(observationColumns.contains("title"))
            XCTAssertTrue(observationColumns.contains("source"))
            XCTAssertTrue(observationColumns.contains("domain"))
            XCTAssertTrue(observationColumns.contains("sessionState"))

            let columns = try db.columns(in: "sessions").map(\.name)
            XCTAssertTrue(columns.contains("category"))
            XCTAssertTrue(columns.contains("sessionGoal"))
        }

        let secondStore = SQLiteSessionStore(databaseURL: dbURL)
        XCTAssertNil(secondStore.migrationError)
        XCTAssertEqual(secondStore.allEvents().count, 1)
        XCTAssertEqual(secondStore.allEvents()[0].url, "https://example.com/path")
    }

    private func createLegacyDatabase() throws {
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE sessions (
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
                action TEXT
            );
            """)

            try db.execute(
                sql: """
                INSERT INTO sessions (
                    id, timestamp, type, appBundleID, appName, url,
                    focusDurationSeconds, sessionDurationSeconds,
                    distractionAppBundleID, distraction_domain, action
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    Date(timeIntervalSinceReferenceDate: 10_000),
                    SessionEventType.sessionEnd.rawValue,
                    "com.apple.dt.Xcode",
                    "Xcode",
                    "https://user:pass@example.com/path?token=secret#fragment",
                    nil as Int?,
                    900,
                    nil as String?,
                    nil as String?,
                    nil as String?
                ]
            )
        }
    }
}
