import Foundation

public struct FocusSchedule: Codable, Equatable {
    public var enabled: Bool
    public var startMinute: Int
    public var endMinute: Int
    public var lunchBreakEnabled: Bool
    public var lunchStartMinute: Int
    public var lunchEndMinute: Int

    public init(
        enabled: Bool = false,
        startMinute: Int = 9 * 60,
        endMinute: Int = 17 * 60,
        lunchBreakEnabled: Bool = false,
        lunchStartMinute: Int = 12 * 60,
        lunchEndMinute: Int = 13 * 60
    ) {
        self.enabled = enabled
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.lunchBreakEnabled = lunchBreakEnabled
        self.lunchStartMinute = lunchStartMinute
        self.lunchEndMinute = lunchEndMinute
    }

    public func normalized() -> FocusSchedule {
        var schedule = self
        schedule.startMinute = Self.clampMinute(schedule.startMinute)
        schedule.endMinute = Self.clampMinute(schedule.endMinute)
        schedule.lunchStartMinute = Self.clampMinute(schedule.lunchStartMinute)
        schedule.lunchEndMinute = Self.clampMinute(schedule.lunchEndMinute)

        if schedule.endMinute <= schedule.startMinute {
            schedule.endMinute = min(schedule.startMinute + 60, Self.maxMinute)
        }

        if schedule.lunchBreakEnabled {
            schedule.lunchStartMinute = max(schedule.startMinute, min(schedule.lunchStartMinute, schedule.endMinute - 1))
            schedule.lunchEndMinute = max(schedule.lunchStartMinute + 1, min(schedule.lunchEndMinute, schedule.endMinute))

            if schedule.lunchEndMinute <= schedule.lunchStartMinute {
                schedule.lunchBreakEnabled = false
            }
        }

        return schedule
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let schedule = normalized()
        let minute = Self.minuteOfDay(for: date, calendar: calendar)

        guard minute >= schedule.startMinute, minute < schedule.endMinute else {
            return false
        }

        guard schedule.lunchBreakEnabled else {
            return true
        }

        return !(minute >= schedule.lunchStartMinute && minute < schedule.lunchEndMinute)
    }

    public func nextTransition(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        let schedule = normalized()
        let minute = Self.minuteOfDay(for: date, calendar: calendar)

        if minute < schedule.startMinute {
            return Self.date(on: date, minute: schedule.startMinute, calendar: calendar)
        }

        if minute >= schedule.endMinute {
            return Self.date(on: date, minute: schedule.startMinute, calendar: calendar, dayOffset: 1)
        }

        if schedule.lunchBreakEnabled {
            if minute < schedule.lunchStartMinute {
                return Self.date(on: date, minute: schedule.lunchStartMinute, calendar: calendar)
            }

            if minute < schedule.lunchEndMinute {
                return Self.date(on: date, minute: schedule.lunchEndMinute, calendar: calendar)
            }
        }

        return Self.date(on: date, minute: schedule.endMinute, calendar: calendar)
    }

    private static let maxMinute = 23 * 60 + 59

    private static func clampMinute(_ minute: Int) -> Int {
        max(0, min(maxMinute, minute))
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func date(on date: Date, minute: Int, calendar: Calendar, dayOffset: Int = 0) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let baseDate = dayOffset == 0 ? startOfDay : calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay
        return calendar.date(byAdding: .minute, value: minute, to: baseDate) ?? date
    }
}
