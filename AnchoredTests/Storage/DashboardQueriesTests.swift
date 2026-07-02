import XCTest
import GRDB
@testable import Anchored

final class DashboardQueriesTests: XCTestCase {
    
    private var tempDirectory: URL!
    private var dbURL: URL!
    private var store: SQLiteSessionStore!
    private var calendar: Calendar!
    
    override func setUp() {
        super.setUp()
        let fileManager = FileManager.default
        let systemTemp = fileManager.temporaryDirectory
        let uniqueSubdir = "DashboardQueriesTests-\(UUID().uuidString)"
        tempDirectory = systemTemp.appendingPathComponent(uniqueSubdir)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        dbURL = tempDirectory.appendingPathComponent("test.db")
        store = SQLiteSessionStore(databaseURL: dbURL)
        calendar = Calendar.current
    }
    
    override func tearDown() {
        store = nil
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }
    
    private func logSync(_ event: SessionEvent) {
        store.log(event)
        let expectation = XCTestExpectation(description: "Wait for SQLite write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testTodayTotalFocusTime() {
        let referenceDate = Date()
        let todayStart = calendar.startOfDay(for: referenceDate)
        
        let session1Start = SessionEvent(
            timestamp: todayStart.addingTimeInterval(3600),
            type: .sessionStart,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode"
        )
        let session1End = SessionEvent(
            timestamp: todayStart.addingTimeInterval(5400),
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1800
        )
        
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let yesterdayEnd = SessionEvent(
            timestamp: yesterdayDate.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1200
        )
        
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let tomorrowEnd = SessionEvent(
            timestamp: tomorrowDate.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 2000
        )
        
        logSync(session1Start)
        logSync(session1End)
        logSync(yesterdayEnd)
        logSync(tomorrowEnd)
        
        let focusTime = store.todayTotalFocusTime(for: referenceDate, calendar: calendar)
        XCTAssertEqual(focusTime, 1800.0)
    }
    
    func testTimelineBlockReconstructionFocusOnly() {
        let referenceDate = Date()
        let todayStart = calendar.startOfDay(for: referenceDate)
        
        let sStart = SessionEvent(
            timestamp: todayStart.addingTimeInterval(3600),
            type: .sessionStart,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode"
        )
        let sEnd = SessionEvent(
            timestamp: todayStart.addingTimeInterval(5400),
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1800
        )
        
        logSync(sStart)
        logSync(sEnd)
        
        let blocks = store.timelineBlocks(for: referenceDate, calendar: calendar)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, .focus)
        XCTAssertEqual(blocks[0].startDate, sStart.timestamp)
        XCTAssertEqual(blocks[0].endDate, sEnd.timestamp)
        XCTAssertEqual(blocks[0].appName, "Xcode")
    }
    
    func testTimelineBlockReconstructionWithDistractions() {
        let referenceDate = Date()
        let todayStart = calendar.startOfDay(for: referenceDate)
        
        let sStart = SessionEvent(
            timestamp: todayStart.addingTimeInterval(3600),
            type: .sessionStart,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode"
        )
        let distraction = SessionEvent(
            timestamp: todayStart.addingTimeInterval(4200),
            type: .distractionDetected,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            distractionAppBundleID: "com.hnc.Discord",
            distraction_domain: nil
        )
        let escalation = SessionEvent(
            timestamp: todayStart.addingTimeInterval(4220),
            type: .escalationTriggered,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            distractionAppBundleID: "com.hnc.Discord",
            action: .escalated
        )
        let sEnd = SessionEvent(
            timestamp: todayStart.addingTimeInterval(5400),
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1800
        )
        
        logSync(sStart)
        logSync(distraction)
        logSync(escalation)
        logSync(sEnd)
        
        let blocks = store.timelineBlocks(for: referenceDate, calendar: calendar)
        XCTAssertEqual(blocks.count, 2)
        
        XCTAssertEqual(blocks[0].type, .focus)
        XCTAssertEqual(blocks[0].startDate, sStart.timestamp)
        XCTAssertEqual(blocks[0].endDate, distraction.timestamp)
        XCTAssertEqual(blocks[0].appName, "Xcode")
        
        XCTAssertEqual(blocks[1].type, .distraction)
        XCTAssertEqual(blocks[1].startDate, distraction.timestamp)
        XCTAssertEqual(blocks[1].endDate, sEnd.timestamp)
        XCTAssertEqual(blocks[1].distractionAppBundleID, "com.hnc.Discord")
        XCTAssertNil(blocks[1].distractionDomain)
    }
    
    func testTopDistractionsRankingSortingAndCounting() {
        let referenceDate = Date()
        let todayStart = calendar.startOfDay(for: referenceDate)
        
        let s1Start = SessionEvent(timestamp: todayStart, type: .sessionStart, appBundleID: "Xcode", appName: "Xcode")
        let s1Dist = SessionEvent(timestamp: todayStart.addingTimeInterval(600), type: .distractionDetected, appBundleID: "Xcode", appName: "Xcode", distractionAppBundleID: "com.hnc.Discord")
        let s1End = SessionEvent(timestamp: todayStart.addingTimeInterval(900), type: .sessionEnd, appBundleID: "Xcode", appName: "Xcode", sessionDurationSeconds: 900)
        
        let s2Start = SessionEvent(timestamp: todayStart.addingTimeInterval(3600), type: .sessionStart, appBundleID: "Xcode", appName: "Xcode")
        let s2Dist1 = SessionEvent(timestamp: todayStart.addingTimeInterval(4200), type: .distractionDetected, appBundleID: "Xcode", appName: "Xcode", distractionAppBundleID: "com.google.Chrome", distraction_domain: "youtube.com")
        let s2End = SessionEvent(timestamp: todayStart.addingTimeInterval(5400), type: .sessionEnd, appBundleID: "Xcode", appName: "Xcode", sessionDurationSeconds: 1800)
        
        logSync(s1Start)
        logSync(s1Dist)
        logSync(s1End)
        logSync(s2Start)
        logSync(s2Dist1)
        logSync(s2End)
        
        let startWindow = todayStart
        let endWindow = todayStart.addingTimeInterval(7200)
        let ranks = store.topDistractions(since: startWindow, to: endWindow)
        
        XCTAssertEqual(ranks.count, 2)
        
        XCTAssertEqual(ranks[0].name, "youtube.com")
        XCTAssertEqual(ranks[0].domain, "youtube.com")
        XCTAssertEqual(ranks[0].count, 1)
        XCTAssertEqual(ranks[0].totalDurationSeconds, 1200)
        
        XCTAssertEqual(ranks[1].name, "Discord")
        XCTAssertEqual(ranks[1].bundleID, "com.hnc.Discord")
        XCTAssertEqual(ranks[1].count, 1)
        XCTAssertEqual(ranks[1].totalDurationSeconds, 300)
    }
    
    func testWeeklyStreakCalculation() {
        let referenceDate = Date()
        let todayStart = calendar.startOfDay(for: referenceDate)
        
        let event2DaysAgo = SessionEvent(
            timestamp: calendar.date(byAdding: .day, value: -2, to: todayStart)!.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1000
        )
        
        let eventYesterday = SessionEvent(
            timestamp: calendar.date(byAdding: .day, value: -1, to: todayStart)!.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1000
        )
        
        let eventToday = SessionEvent(
            timestamp: todayStart.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1000
        )
        
        logSync(event2DaysAgo)
        logSync(eventYesterday)
        logSync(eventToday)
        
        let streak = store.weeklyStreak(for: referenceDate, calendar: calendar)
        XCTAssertEqual(streak, 3)
    }
    
    func testWeeklyStreakCalculationWithGap() {
        let referenceDate = Date()
        let todayStart = calendar.startOfDay(for: referenceDate)
        
        let event3DaysAgo = SessionEvent(
            timestamp: calendar.date(byAdding: .day, value: -3, to: todayStart)!.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1000
        )
        
        let eventYesterday = SessionEvent(
            timestamp: calendar.date(byAdding: .day, value: -1, to: todayStart)!.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1000
        )
        
        let eventToday = SessionEvent(
            timestamp: todayStart.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1000
        )
        
        logSync(event3DaysAgo)
        logSync(eventYesterday)
        logSync(eventToday)
        
        let streak = store.weeklyStreak(for: referenceDate, calendar: calendar)
        XCTAssertEqual(streak, 2)
    }
}
