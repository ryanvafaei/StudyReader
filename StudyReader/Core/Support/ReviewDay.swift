import Foundation

/// Review days start at 04:00 local time (SPEC F-15, ADR-0022). Pure; the calendar carries the time zone.
enum ReviewDay {
    static let boundaryHour = 4

    /// 04:00 on the calendar day of (date − 4 h). Never nil: falls back to startOfDay + 4 h.
    static func start(containing date: Date, calendar: Calendar) -> Date {
        let shifted = date.addingTimeInterval(-Double(boundaryHour) * 3600)
        let day = calendar.startOfDay(for: shifted)
        return calendar.date(bySettingHour: boundaryHour, minute: 0, second: 0, of: day)
            ?? day.addingTimeInterval(Double(boundaryHour) * 3600)
    }

    /// The next boundary after the review day containing `date` (DST-safe).
    static func start(after date: Date, calendar: Calendar) -> Date {
        let current = start(containing: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: current)
            ?? current.addingTimeInterval(86_400)
    }

    /// Whole review days from the day containing `from` to the day containing `to` (negative if `to` is earlier).
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        let fromStart = start(containing: from, calendar: calendar)
        let toStart = start(containing: to, calendar: calendar)
        return calendar.dateComponents([.day], from: fromStart, to: toStart).day ?? 0
    }

    /// Calendar weekday (1 = Sunday … 7 = Saturday) of the review day containing `date`.
    static func weekday(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.weekday, from: start(containing: date, calendar: calendar))
    }
}
