import XCTest
@testable import Anchored

final class FocusScheduleTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testScheduleIsActiveOutsideLunchAndInactiveDuringLunch() {
        let schedule = FocusSchedule(
            enabled: true,
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            lunchBreakEnabled: true,
            lunchStartMinute: 12 * 60,
            lunchEndMinute: 13 * 60
        )

        let morning = date(year: 2026, month: 7, day: 13, hour: 11, minute: 30)
        let lunch = date(year: 2026, month: 7, day: 13, hour: 12, minute: 30)
        let afternoon = date(year: 2026, month: 7, day: 13, hour: 13, minute: 30)

        XCTAssertTrue(schedule.isActive(at: morning, calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: lunch, calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: afternoon, calendar: calendar))
    }

    func testScheduleNextTransitionFollowsWorkAndLunchBoundaries() {
        let schedule = FocusSchedule(
            enabled: true,
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            lunchBreakEnabled: true,
            lunchStartMinute: 12 * 60,
            lunchEndMinute: 13 * 60
        )

        let beforeLunch = date(year: 2026, month: 7, day: 13, hour: 11, minute: 30)
        let duringLunch = date(year: 2026, month: 7, day: 13, hour: 12, minute: 30)
        let afterHours = date(year: 2026, month: 7, day: 13, hour: 18, minute: 0)

        XCTAssertEqual(schedule.nextTransition(after: beforeLunch, calendar: calendar), date(year: 2026, month: 7, day: 13, hour: 12, minute: 0))
        XCTAssertEqual(schedule.nextTransition(after: duringLunch, calendar: calendar), date(year: 2026, month: 7, day: 13, hour: 13, minute: 0))
        XCTAssertEqual(schedule.nextTransition(after: afterHours, calendar: calendar), date(year: 2026, month: 7, day: 14, hour: 9, minute: 0))
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
