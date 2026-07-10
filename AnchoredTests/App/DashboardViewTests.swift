import XCTest
import AppKit
import SwiftUI
@testable import Anchored

final class DashboardViewTests: XCTestCase {
    func testDayRangeUsesLast24HoursCaption() {
        XCTAssertEqual(DashboardRange.day.trendAxisCaption, "Focus time by hour")
        XCTAssertEqual(DashboardRange.day.trendAxisLabels, ["0", "6", "12", "18", "24"])
    }

    func testDashboardChromeUsesRequestedMainAndTileColors() {
        XCTAssertEqual(hexValue(for: DashboardChrome.main), 0x2A2522)
        XCTAssertEqual(hexValue(for: DashboardChrome.tile), 0x403A35)
        XCTAssertEqual(hexValue(for: DashboardChrome.control), 0x2A2522)
        XCTAssertEqual(hexValue(for: DashboardChrome.cardTop), 0x403A35)
    }

    func testControlRoomThemeUsesRequestedMainAndTileColors() {
        XCTAssertEqual(hexValue(for: ControlRoomTheme.main), 0x2A2522)
        XCTAssertEqual(hexValue(for: ControlRoomTheme.tile), 0x403A35)
        XCTAssertEqual(hexValue(for: ControlRoomTheme.shellMid), 0x2A2522)
        XCTAssertEqual(hexValue(for: ControlRoomTheme.cardTop), 0x403A35)
    }

    func testWeekRangeUsesDailyQueryAndStartOfDayWindow() throws {
        let querying = DashboardQueryingSpy()
        let store = makeStore()
        let model = DashboardDataModel(querying: querying, store: store)

        model.refresh(range: .week)

        let load = expectation(description: "week load")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(querying.hourlyCalls, 0)
            XCTAssertEqual(querying.dailyCalls, 1)

            guard let endDate = querying.lastDailyEndDate,
                  let startDate = querying.lastDailyStartDate else {
                XCTFail("Missing daily query window")
                load.fulfill()
                return
            }

            let expectedStart = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: endDate))
            XCTAssertEqual(startDate, expectedStart)

            if case .loaded(let buckets) = model.trendState {
                XCTAssertEqual(buckets.count, 1)
                XCTAssertEqual(buckets.first?.duration, 5400)
            } else {
                XCTFail("Expected loaded trend state")
            }

            load.fulfill()
        }

        wait(for: [load], timeout: 1.0)
    }

    func testMonthRangeUsesFirstSessionDateAndTracksAllTimeSummary() throws {
        let querying = DashboardQueryingSpy()
        let store = makeStore()
        let model = DashboardDataModel(querying: querying, store: store)
        let calendar = Calendar.current
        let now = Date()
        let firstUse = calendar.date(byAdding: .day, value: -4, to: now)!
        let secondUse = calendar.date(byAdding: .day, value: -3, to: now)!

        logSync(
            SessionEvent(
                timestamp: firstUse,
                type: .sessionEnd,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                sessionDurationSeconds: 900
            ),
            store: store
        )
        logSync(
            SessionEvent(
                timestamp: secondUse,
                type: .sessionEnd,
                appBundleID: "com.apple.Safari",
                appName: "Safari",
                sessionDurationSeconds: 1800
            ),
            store: store
        )

        querying.earliestDate = firstUse
        let summary = DashboardRangeSummary(sessionCount: 2, totalFocusDuration: 2700, longestSessionDuration: 1800)
        querying.rangeSummaryToReturn = summary
        querying.allTimeSummaryToReturn = summary

        model.refresh(range: .month)

        let load = expectation(description: "month load")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(querying.hourlyCalls, 0)
            XCTAssertEqual(querying.dailyCalls, 1)
            XCTAssertEqual(
                querying.lastDailyStartDate?.timeIntervalSince1970 ?? 0,
                firstUse.timeIntervalSince1970,
                accuracy: 0.001
            )

            XCTAssertEqual(model.rangeSummary.sessionCount, 2)
            XCTAssertEqual(model.rangeSummary.totalFocusDuration, 2700, accuracy: 0.1)
            XCTAssertEqual(model.rangeSummary.longestSessionDuration, 1800, accuracy: 0.1)

            XCTAssertEqual(model.allTimeSummary.sessionCount, 2)
            XCTAssertEqual(model.allTimeSummary.totalFocusDuration, 2700, accuracy: 0.1)
            XCTAssertEqual(model.allTimeSummary.longestSessionDuration, 1800, accuracy: 0.1)

            if case .loaded(let buckets) = model.trendState {
                XCTAssertEqual(buckets.count, 1)
            } else {
                XCTFail("Expected loaded trend state")
            }

            load.fulfill()
        }

        wait(for: [load], timeout: 1.0)
    }

    func testDayRangeUsesHourlyQuery() throws {
        let querying = DashboardQueryingSpy()
        let store = makeStore()
        let model = DashboardDataModel(querying: querying, store: store)

        model.refresh(range: .day)

        let load = expectation(description: "day load")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(querying.hourlyCalls, 1)
            XCTAssertEqual(querying.dailyCalls, 0)

            if case .loaded(let buckets) = model.trendState {
                XCTAssertEqual(buckets.count, 1)
                XCTAssertEqual(buckets.first?.duration, 1800)
            } else {
                XCTFail("Expected loaded trend state")
            }

            load.fulfill()
        }

        wait(for: [load], timeout: 1.0)
    }

    private func logSync(_ event: SessionEvent, store: SQLiteSessionStore) {
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

    private func makeStore() -> SQLiteSessionStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardViewTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SQLiteSessionStore(databaseURL: directory.appendingPathComponent("test.sqlite"))
    }

    private func hexValue(for color: Color) -> UInt32 {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        let red = UInt32((resolved.redComponent * 255.0).rounded())
        let green = UInt32((resolved.greenComponent * 255.0).rounded())
        let blue = UInt32((resolved.blueComponent * 255.0).rounded())
        return (red << 16) | (green << 8) | blue
    }
}

private final class DashboardQueryingSpy: DashboardQuerying {
    var hourlyCalls = 0
    var dailyCalls = 0
    var lastDailyStartDate: Date?
    var lastDailyEndDate: Date?
    var earliestDate: Date?
    var rangeSummaryToReturn: DashboardRangeSummary?
    var allTimeSummaryToReturn: DashboardRangeSummary?
    var topDistractionsToReturn: [DistractionRank] = []

    func fetchFocusTimePerHourForLast24Hours(
        relativeTo referenceDate: Date,
        calendar: Calendar,
        completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void
    ) {
        hourlyCalls += 1
        completion(.success([DashboardTimeBucket(date: referenceDate, duration: 1800)]))
    }

    func fetchFocusTimePerDay(
        since startDate: Date,
        to endDate: Date,
        calendar: Calendar,
        completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void
    ) {
        dailyCalls += 1
        lastDailyStartDate = startDate
        lastDailyEndDate = endDate
        completion(.success([DashboardTimeBucket(date: startDate, duration: 5400)]))
    }

    func fetchAppDomainFocusDistribution(
        since startDate: Date,
        to endDate: Date,
        completion: @escaping (Result<[DashboardAppDistribution], DashboardQueryError>) -> Void
    ) {
        completion(.success([]))
    }

    func fetchRangeSummary(
        since startDate: Date,
        to endDate: Date,
        completion: @escaping (Result<DashboardRangeSummary, DashboardQueryError>) -> Void
    ) {
        if let summary = rangeSummaryToReturn {
            if startDate == Date.distantPast || startDate.timeIntervalSince1970 < 0 {
                completion(.success(allTimeSummaryToReturn ?? summary))
            } else {
                completion(.success(summary))
            }
        } else {
            completion(.success(DashboardRangeSummary(sessionCount: 0, totalFocusDuration: 0, longestSessionDuration: 0)))
        }
    }

    func fetchTopDistractions(
        since startDate: Date,
        to endDate: Date,
        completion: @escaping (Result<[DistractionRank], DashboardQueryError>) -> Void
    ) {
        completion(.success(topDistractionsToReturn))
    }

    func fetchEarliestSessionDate(
        completion: @escaping (Result<Date?, DashboardQueryError>) -> Void
    ) {
        completion(.success(earliestDate))
    }
}
