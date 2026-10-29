import Testing
import Foundation
@testable import StudyReader

/// 04:00 review-day boundary (T98, SPEC F-15, ADR-0022). Fixed dates, no clock.
@Suite struct ReviewDayTests {

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// Builds a date in `calendar` from its local components.
    private static func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func startUsesFourOClock() {
        let cases: [(input: Date, expected: Date)] = [
            (Self.date(Self.utc, 2026, 10, 1, 3, 59), Self.date(Self.utc, 2026, 9, 30, 4)),
            (Self.date(Self.utc, 2026, 10, 1, 4, 0), Self.date(Self.utc, 2026, 10, 1, 4)),
            (Self.date(Self.utc, 2026, 10, 1, 23, 30), Self.date(Self.utc, 2026, 10, 1, 4)),
        ]
        for testCase in cases {
            #expect(ReviewDay.start(containing: testCase.input, calendar: Self.utc) == testCase.expected)
        }
    }

    @Test func startAfterIsTheNextBoundary() {
        let cases: [(input: Date, expected: Date)] = [
            (Self.date(Self.utc, 2026, 10, 1, 10), Self.date(Self.utc, 2026, 10, 2, 4)),
            (Self.date(Self.utc, 2026, 10, 2, 3), Self.date(Self.utc, 2026, 10, 2, 4)),
        ]
        for testCase in cases {
            #expect(ReviewDay.start(after: testCase.input, calendar: Self.utc) == testCase.expected)
        }
    }

    @Test func daylightSavingChange() {
        // Summer time ends 2026-10-25 at 03:00 → 02:00, so the review day is 25 hours long.
        let noon = Self.date(Self.berlin, 2026, 10, 25, 12)
        #expect(ReviewDay.start(containing: noon, calendar: Self.berlin)
                == Self.date(Self.berlin, 2026, 10, 25, 4))

        let previousNoon = Self.date(Self.berlin, 2026, 10, 24, 12)
        let previousStart = Self.date(Self.berlin, 2026, 10, 24, 4)
        let next = ReviewDay.start(after: previousNoon, calendar: Self.berlin)
        #expect(next == Self.date(Self.berlin, 2026, 10, 25, 4))
        #expect(next.timeIntervalSince(previousStart) == 25 * 3600)
    }

    @Test func daysBetweenCountsReviewDays() {
        let from = Self.date(Self.utc, 2026, 10, 1, 23)
        let cases: [(to: Date, expected: Int)] = [
            (Self.date(Self.utc, 2026, 10, 2, 3), 0),
            (Self.date(Self.utc, 2026, 10, 2, 5), 1),
            (Self.date(Self.utc, 2026, 10, 8, 5), 7),
            (Self.date(Self.utc, 2026, 9, 30, 12), -1),
        ]
        for testCase in cases {
            #expect(ReviewDay.daysBetween(from, testCase.to, calendar: Self.utc) == testCase.expected)
        }
        #expect(ReviewDay.daysBetween(Self.date(Self.utc, 2026, 10, 8, 5), from, calendar: Self.utc) < 0)
    }

    @Test func weekdayOfReviewDay() {
        // 2026-10-01 is a Thursday (weekday 5). Before 04:00 it is still Wednesday's review day (weekday 4).
        #expect(ReviewDay.weekday(of: Self.date(Self.utc, 2026, 10, 1, 2), calendar: Self.utc) == 4)
        #expect(ReviewDay.weekday(of: Self.date(Self.utc, 2026, 10, 1, 5), calendar: Self.utc) == 5)
    }
}
