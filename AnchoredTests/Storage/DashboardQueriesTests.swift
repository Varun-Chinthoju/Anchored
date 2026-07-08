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
        let expectation = expectation(description: "Wait for SQLite write")
        var result: Result<Void, Error>?
        store.log(event) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("SQLite write failed: \(error)")
        case nil:
            XCTFail("Missing SQLite write result")
        }
    }

    private func insertEvents(_ events: [SessionEvent]) throws {
        try store.dbQueue.write { db in
            for event in events {
                try event.insert(db)
            }
        }
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

    func testFetchFocusTimePerHourReturnsOnMainQueue() {
        let referenceDate = Date()
        let todayStart = calendar.startOfDay(for: referenceDate)

        let session1 = SessionEvent(
            timestamp: todayStart.addingTimeInterval(3600),
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 1800
        )
        let session2 = SessionEvent(
            timestamp: todayStart.addingTimeInterval(7200),
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 900
        )

        logSync(session1)
        logSync(session2)

        let expected = store.focusTimePerHourForLast24Hours(relativeTo: referenceDate, calendar: calendar)

        let expectation = expectation(description: "Async hourly query")
        var completedSynchronously = true

        store.fetchFocusTimePerHourForLast24Hours(relativeTo: referenceDate, calendar: calendar) { result in
            XCTAssertTrue(Thread.isMainThread)
            switch result {
            case .success(let buckets):
                XCTAssertEqual(buckets.count, expected.count)
                for (bucket, pair) in zip(buckets, expected) {
                    XCTAssertEqual(bucket.date, pair.0)
                    XCTAssertEqual(bucket.duration, pair.1)
                }
            case .failure(let error):
                XCTFail("Unexpected dashboard query failure: \(error.localizedDescription)")
            }
            completedSynchronously = false
            expectation.fulfill()
        }

        XCTAssertTrue(completedSynchronously)
        wait(for: [expectation], timeout: 1.0)
    }

    func testFetchFocusTimePerDayPreservesDaylightSavingBoundaries() {
        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let march7 = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        let march8Morning = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30))!
        let march8AfterJump = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30))!
        let march9Morning = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 1, minute: 30))!

        let march8Start = dstCalendar.startOfDay(for: march8Morning)
        let march9End = dstCalendar.date(bySettingHour: 23, minute: 59, second: 59, of: dstCalendar.startOfDay(for: march9Morning))!

        let sessions = [
            SessionEvent(
                timestamp: march8Morning,
                type: .sessionEnd,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                sessionDurationSeconds: 1800
            ),
            SessionEvent(
                timestamp: march8AfterJump,
                type: .sessionEnd,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                sessionDurationSeconds: 1800
            ),
            SessionEvent(
                timestamp: march9Morning,
                type: .sessionEnd,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                sessionDurationSeconds: 900
            )
        ]

        do {
            try insertEvents(sessions)
        } catch {
            XCTFail("Failed to seed DST fixture: \(error)")
            return
        }

        let expectation = expectation(description: "Async daily query")
        store.fetchFocusTimePerDay(since: march7, to: march9End, calendar: dstCalendar) { result in
            XCTAssertTrue(Thread.isMainThread)
            switch result {
            case .success(let buckets):
                XCTAssertEqual(buckets.count, 3)
                XCTAssertEqual(buckets[1].date, march8Start)
                XCTAssertEqual(buckets[1].duration, 3600)
                XCTAssertEqual(buckets[2].duration, 900)
            case .failure(let error):
                XCTFail("Unexpected dashboard query failure: \(error.localizedDescription)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testFetchAppDomainDistributionHandlesLargeFixtureAsynchronously() {
        let referenceDate = Date()
        let dayStart = calendar.startOfDay(for: referenceDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!.addingTimeInterval(-1)

        let expectation = expectation(description: "Async large fixture query")
        var completedSynchronously = true

        do {
            try store.dbQueue.write { db in
                for index in 0..<100_000 {
                    let session = SessionEvent(
                        timestamp: dayStart.addingTimeInterval(TimeInterval(index % 3600)),
                        type: .sessionEnd,
                        appBundleID: "com.apple.dt.Xcode",
                        appName: "Xcode",
                        url: index.isMultiple(of: 2) ? "https://example.com/path" : nil,
                        sessionDurationSeconds: 60
                    )
                    try session.insert(db)
                }
            }
        } catch {
            XCTFail("Failed to seed large fixture: \(error)")
            return
        }

        store.fetchAppDomainFocusDistribution(since: dayStart, to: dayEnd) { result in
            XCTAssertTrue(Thread.isMainThread)
            switch result {
            case .success(let distributions):
                XCTAssertEqual(distributions.count, 1)
                XCTAssertEqual(distributions[0].bundleID, "com.apple.dt.Xcode")
                XCTAssertEqual(distributions[0].duration, 6_000_000)
                XCTAssertEqual(distributions[0].domains.first?.domain, "example.com")
            case .failure(let error):
                XCTFail("Unexpected dashboard query failure: \(error.localizedDescription)")
            }
            completedSynchronously = false
            expectation.fulfill()
        }

        XCTAssertTrue(completedSynchronously)
        wait(for: [expectation], timeout: 5.0)
    }

    func testFetchRangeSummaryReturnsStoredSessionTotals() throws {
        let referenceDate = Date()
        let startDate = referenceDate.addingTimeInterval(-3600)
        let sessions = [
            SessionEvent(
                timestamp: referenceDate.addingTimeInterval(-1800),
                type: .sessionEnd,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                sessionDurationSeconds: 900
            ),
            SessionEvent(
                timestamp: referenceDate.addingTimeInterval(-900),
                type: .sessionEnd,
                appBundleID: "com.apple.Safari",
                appName: "Safari",
                sessionDurationSeconds: 1800
            ),
            SessionEvent(
                timestamp: referenceDate.addingTimeInterval(-300),
                type: .distractionDetected,
                appBundleID: "com.apple.Safari",
                appName: "Safari"
            )
        ]
        try insertEvents(sessions)

        let expectation = expectation(description: "Async range summary")
        store.fetchRangeSummary(since: startDate, to: referenceDate) { result in
            XCTAssertTrue(Thread.isMainThread)
            switch result {
            case .success(let summary):
                XCTAssertEqual(summary.sessionCount, 2)
                XCTAssertEqual(summary.totalFocusDuration, 2700)
                XCTAssertEqual(summary.longestSessionDuration, 1800)
            case .failure(let error):
                XCTFail("Unexpected dashboard query failure: \(error.localizedDescription)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
