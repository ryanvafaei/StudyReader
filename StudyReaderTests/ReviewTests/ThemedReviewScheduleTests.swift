import Testing
import Foundation
@testable import StudyReader

/// Themed review intervals with the 04:00 review-day boundary (T121, SPEC F-20 AC2, ADR-0022). Fixed dates, no clock.
@Suite struct ThemedReviewScheduleTests {

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-01 is a Thursday. Calendar weekdays: 2 Monday … 5 Thursday.
    private static func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private static let monday = 2
    private static let wednesday = 4
    private static let thursday = 5

    private static func review(_ interval: ReviewInterval, completed: Date?) -> ThemedReview {
        ThemedReview(
            id: "t-1",
            name: "Test",
            interval: interval,
            lastCompletedAt: completed,
            createdAt: TestData.referenceDate
        )
    }

    @Test func neverCompleted() {
        // Monday 2026-10-05, Tuesday 2026-10-06.
        let cases: [(label: String, interval: ReviewInterval, now: Date, expected: Bool)] = [
            ("daily", .daily, Self.date(8, 10), true),
            ("every 3 days", .everyNDays(3), Self.date(8, 10), true),
            ("weekdays Mon on Monday", .weekdays([Self.monday]), Self.date(5, 10), true),
            ("weekdays Mon on Tuesday", .weekdays([Self.monday]), Self.date(6, 10), false),
        ]
        for testCase in cases {
            let due = ThemedReviewSchedule.isDue(
                Self.review(testCase.interval, completed: nil),
                now: testCase.now,
                calendar: Self.utc
            )
            #expect(due == testCase.expected, "\(testCase.label)")
        }
    }

    @Test func intervalsWithCompletion() {
        let cases: [(label: String, interval: ReviewInterval, completed: Date, now: Date, expected: Bool)] = [
            // Daily: review days start at 04:00.
            ("daily, completed yesterday 23:00, due today 05:00", .daily, Self.date(7, 23), Self.date(8, 5), true),
            ("daily, completed today 04:30, not due at 10:00", .daily, Self.date(8, 4, 30), Self.date(8, 10), false),
            ("daily, completed today 03:00 is yesterday's review day, due at 05:00", .daily, Self.date(8, 3), Self.date(8, 5), true),
            ("daily, completed today 04:30, not due at 23:59", .daily, Self.date(8, 4, 30), Self.date(8, 23, 59), false),

            // Every N days: counted in review days.
            ("every 3 days, completed 2 review days ago", .everyNDays(3), Self.date(6, 10), Self.date(8, 10), false),
            ("every 3 days, completed 3 review days ago", .everyNDays(3), Self.date(5, 10), Self.date(8, 10), true),
            ("every 3 days, completed 3 review days ago before 04:00", .everyNDays(3), Self.date(6, 3), Self.date(8, 5), true),
            ("every 1 day, completed earlier today", .everyNDays(1), Self.date(8, 5), Self.date(8, 10), false),
            ("every 0 days counts as 1, completed yesterday", .everyNDays(0), Self.date(7, 10), Self.date(8, 10), true),
            ("nil n counts as 1, completed earlier today", ReviewInterval(kind: .everyNDays, n: nil, weekdays: nil), Self.date(8, 5), Self.date(8, 10), false),

            // Weekdays: a listed weekday of the review day, and not completed today.
            ("weekdays Mon/Thu on Thursday, not completed today", .weekdays([Self.monday, Self.thursday]), Self.date(6, 10), Self.date(8, 10), true),
            ("weekdays Mon/Thu on Thursday, completed earlier that review day", .weekdays([Self.monday, Self.thursday]), Self.date(8, 5), Self.date(8, 10), false),
            ("weekdays Mon/Thu on Wednesday", .weekdays([Self.monday, Self.thursday]), Self.date(6, 10), Self.date(7, 10), false),
            ("weekdays Mon/Thu, Thursday 02:00 is still Wednesday's review day", .weekdays([Self.monday, Self.thursday]), Self.date(1, 10), Self.date(8, 2), false),
        ]
        for testCase in cases {
            let due = ThemedReviewSchedule.isDue(
                Self.review(testCase.interval, completed: testCase.completed),
                now: testCase.now,
                calendar: Self.utc
            )
            #expect(due == testCase.expected, "\(testCase.label)")
        }
    }

    @Test func weekdayTableUsesReviewDayNotCalendarDay() {
        // Wednesday 02:00 belongs to Tuesday's review day, so a Tuesday-only review is due then.
        let tuesday = 3
        let due = ThemedReviewSchedule.isDue(
            Self.review(.weekdays([tuesday]), completed: nil),
            now: Self.date(7, 2),
            calendar: Self.utc
        )
        #expect(due)
        #expect(!ThemedReviewSchedule.isDue(
            Self.review(.weekdays([Self.wednesday]), completed: nil),
            now: Self.date(7, 2),
            calendar: Self.utc
        ))
    }
}
