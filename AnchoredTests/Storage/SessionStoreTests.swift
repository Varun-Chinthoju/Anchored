import XCTest
@testable import Anchored

final class SessionStoreTests: XCTestCase {
    
    private var testFileURL: URL!
    private var store: SessionStore!
    
    override func setUp() {
        super.setUp()
        let tempDirectory = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        testFileURL = tempDirectory.appendingPathComponent("AnchoredTests-\(uuid)/sessions.json")
        store = SessionStore(fileURL: testFileURL)
    }
    
    override func tearDown() {
        store = nil
        let directoryURL = testFileURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        super.tearDown()
    }

    private func logAndWait(_ event: SessionEvent, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = expectation(description: "SessionStore write completed")
        var result: Result<Void, Error>?
        store.log(event) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        guard let result else {
            XCTFail("Missing SessionStore write result", file: file, line: line)
            return
        }

        if case .failure(let error) = result {
            XCTFail("SessionStore write failed: \(error)", file: file, line: line)
        }
    }
    
    func testLogAppendsEventsAndCreatesDirectory() {
        let event1 = SessionEvent(type: .sessionStart, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let event2 = SessionEvent(type: .sessionEnd, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")

        logAndWait(event1)
        logAndWait(event2)

        let dbURL = testFileURL.deletingPathExtension().appendingPathExtension("db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))

        let events = store.allEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].id, event1.id)
        XCTAssertEqual(events[1].id, event2.id)
    }
    
    func testRecentSessionsReturnsCorrectFilteredEvents() {
        let eventStart = SessionEvent(type: .sessionStart, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let eventEnd1 = SessionEvent(type: .sessionEnd, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let eventDistraction = SessionEvent(type: .distractionDetected, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let eventEnd2 = SessionEvent(type: .sessionEnd, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")

        logAndWait(eventStart)
        logAndWait(eventEnd1)
        logAndWait(eventDistraction)
        logAndWait(eventEnd2)

        let recent = store.recentSessions(limit: 5)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].id, eventEnd2.id)
        XCTAssertEqual(recent[1].id, eventEnd1.id)

        let limitOne = store.recentSessions(limit: 1)
        XCTAssertEqual(limitOne.count, 1)
        XCTAssertEqual(limitOne[0].id, eventEnd2.id)
    }
    
    func testGetStats() {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        
        let event2DaysAgo = SessionEvent(
            timestamp: twoDaysAgo,
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1200
        )
        
        let eventYesterday1 = SessionEvent(
            timestamp: yesterday,
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1500
        )
        let eventYesterday2 = SessionEvent(
            timestamp: yesterday,
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1800
        )
        
        let eventToday = SessionEvent(
            timestamp: now,
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 900
        )

        logAndWait(event2DaysAgo)
        logAndWait(eventYesterday1)
        logAndWait(eventYesterday2)
        logAndWait(eventToday)

        let stats = store.getStats()

        XCTAssertEqual(stats.sessionCountToday, 1)
        XCTAssertEqual(stats.focusedTimeToday, 900)
        XCTAssertEqual(stats.streakDays, 3)
    }
}
