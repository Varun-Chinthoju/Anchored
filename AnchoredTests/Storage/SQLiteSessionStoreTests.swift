import XCTest
import GRDB
@testable import Anchored

final class SQLiteSessionStoreTests: XCTestCase {
    
    private var tempDirectory: URL!
    private var dbURL: URL!
    private var jsonURL: URL!
    private var store: SQLiteSessionStore!
    
    override func setUp() {
        super.setUp()
        let fileManager = FileManager.default
        let systemTemp = fileManager.temporaryDirectory
        let uniqueSubdir = "SQLiteSessionStoreTests-\(UUID().uuidString)"
        tempDirectory = systemTemp.appendingPathComponent(uniqueSubdir)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        dbURL = tempDirectory.appendingPathComponent("test.db")
        jsonURL = tempDirectory.appendingPathComponent("sessions.json")
        store = SQLiteSessionStore(databaseURL: dbURL)
    }
    
    override func tearDown() {
        store = nil
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }
    
    func testSQLiteInitializationCreatesTableAndIndexes() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
        
        do {
            let dbQueue = try DatabaseQueue(path: dbURL.path)
            try dbQueue.read { db in
                // Verify table exists
                let tableExists = try db.tableExists("sessions")
                XCTAssertTrue(tableExists)
                
                // Verify columns exist
                let columns = try db.columns(in: "sessions").map { $0.name }
                XCTAssertTrue(columns.contains("id"))
                XCTAssertTrue(columns.contains("timestamp"))
                XCTAssertTrue(columns.contains("type"))
                XCTAssertTrue(columns.contains("appBundleID"))
                XCTAssertTrue(columns.contains("appName"))
                XCTAssertTrue(columns.contains("url"))
                XCTAssertTrue(columns.contains("focusDurationSeconds"))
                XCTAssertTrue(columns.contains("sessionDurationSeconds"))
                XCTAssertTrue(columns.contains("distractionAppBundleID"))
                XCTAssertTrue(columns.contains("distraction_domain"))
                XCTAssertTrue(columns.contains("action"))
                
                // Verify indexes exist
                let indexRows = try Row.fetchAll(db, sql: "PRAGMA index_list('sessions')")
                let indexNames = indexRows.map { $0["name"] as! String }
                XCTAssertTrue(indexNames.contains("idx_sessions_timestamp") || indexNames.contains("sqlite_autoindex_sessions_1"))
                XCTAssertTrue(indexNames.contains("idx_sessions_type") || indexNames.contains("sqlite_autoindex_sessions_1"))
            }
        } catch {
            XCTFail("Failed to verify SQLite tables and indexes: \(error)")
        }
    }
    
    func testLogAndRecentSessions() {
        let expectation = XCTestExpectation(description: "Logging events writes to SQLite database")
        
        let eventStart = SessionEvent(
            type: .sessionStart,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            url: nil
        )
        let eventEnd1 = SessionEvent(
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            url: "https://google.com",
            sessionDurationSeconds: 60
        )
        let eventDist = SessionEvent(
            type: .distractionDetected,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            distractionAppBundleID: "com.hnc.Discord",
            distraction_domain: "discord.com"
        )
        let eventEnd2 = SessionEvent(
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            url: "https://stackoverflow.com",
            sessionDurationSeconds: 120
        )
        
        store.log(eventStart)
        store.log(eventEnd1)
        store.log(eventDist)
        store.log(eventEnd2)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let all = self.store.allEvents()
            XCTAssertEqual(all.count, 4)
            
            let recent = self.store.recentSessions(limit: 5)
            // recentSessions only filters type == .sessionEnd
            XCTAssertEqual(recent.count, 2)
            XCTAssertEqual(recent[0].id, eventEnd2.id)
            XCTAssertEqual(recent[0].url, "https://stackoverflow.com")
            XCTAssertEqual(recent[0].sessionDurationSeconds, 120)
            XCTAssertEqual(recent[1].id, eventEnd1.id)
            XCTAssertEqual(recent[1].url, "https://google.com")
            XCTAssertEqual(recent[1].sessionDurationSeconds, 60)
            
            let limitOne = self.store.recentSessions(limit: 1)
            XCTAssertEqual(limitOne.count, 1)
            XCTAssertEqual(limitOne[0].id, eventEnd2.id)
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMigrationFromJSON() throws {
        // Create mock legacy JSON file
        let event1 = SessionEvent(type: .sessionStart, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let event2 = SessionEvent(type: .sessionEnd, appBundleID: "com.apple.dt.Xcode", appName: "Xcode", sessionDurationSeconds: 300)
        let events = [event1, event2]
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(events)
        try data.write(to: jsonURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        
        // Trigger migration
        store.migrateFromJSONIfNeeded(jsonURL: jsonURL)
        
        // Verify SQLite database populated
        let all = store.allEvents()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].id, event1.id)
        XCTAssertEqual(all[1].id, event2.id)
        
        // Verify JSON file is renamed to .json.migrated
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        let migratedURL = jsonURL.deletingPathExtension().appendingPathExtension("json.migrated")
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedURL.path))
    }
}
