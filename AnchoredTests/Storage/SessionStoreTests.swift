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
    
    func testLogAppendsEventsAndCreatesDirectory() {
        let expectation = XCTestExpectation(description: "Logging events writes to disk")
        
        let event1 = SessionEvent(type: .sessionStart, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let event2 = SessionEvent(type: .sessionEnd, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        
        store.log(event1)
        store.log(event2)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let dbURL = self.testFileURL.deletingPathExtension().appendingPathExtension("db")
            XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
            
            let events = self.store.allEvents()
            XCTAssertEqual(events.count, 2)
            XCTAssertEqual(events[0].id, event1.id)
            XCTAssertEqual(events[1].id, event2.id)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRecentSessionsReturnsCorrectFilteredEvents() {
        let expectation = XCTestExpectation(description: "Logged sessionEnd events are filtered and sorted")
        
        let eventStart = SessionEvent(type: .sessionStart, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let eventEnd1 = SessionEvent(type: .sessionEnd, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let eventDistraction = SessionEvent(type: .distractionDetected, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let eventEnd2 = SessionEvent(type: .sessionEnd, appBundleID: "com.apple.dt.Xcode", appName: "Xcode")
        
        store.log(eventStart)
        store.log(eventEnd1)
        store.log(eventDistraction)
        store.log(eventEnd2)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let recent = self.store.recentSessions(limit: 5)
            XCTAssertEqual(recent.count, 2)
            XCTAssertEqual(recent[0].id, eventEnd2.id)
            XCTAssertEqual(recent[1].id, eventEnd1.id)
            
            let limitOne = self.store.recentSessions(limit: 1)
            XCTAssertEqual(limitOne.count, 1)
            XCTAssertEqual(limitOne[0].id, eventEnd2.id)
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetStats() {
        let expectation = XCTestExpectation(description: "Stats calculation works correctly")
        
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
        
        store.log(event2DaysAgo)
        store.log(eventYesterday1)
        store.log(eventYesterday2)
        store.log(eventToday)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let stats = self.store.getStats()
            
            XCTAssertEqual(stats.sessionCountToday, 1)
            XCTAssertEqual(stats.focusedTimeToday, 900)
            XCTAssertEqual(stats.streakDays, 3)
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}
