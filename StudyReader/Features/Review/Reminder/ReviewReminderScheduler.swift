import Foundation
import Observation
import UserNotifications

/// The part of UNUserNotificationCenter we use. Tests stub it.
protocol ReminderNotificationCenter: Sendable {
    func requestAuthorization() async throws -> Bool
    func scheduleDaily(identifier: String, hour: Int, minute: Int, title: String, body: String) async throws
    func removePending(identifier: String) async
}

/// The system notification center (ADR-0022). Asks for alert and sound permission; repeats the trigger daily.
struct SystemReminderNotificationCenter: ReminderNotificationCenter {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func scheduleDaily(identifier: String, hour: Int, minute: Int, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var time = DateComponents()
        time.hour = hour
        time.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePending(identifier: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// Used by tests, previews and the in-memory library: never asks for permission, never schedules anything.
/// Answers "granted" so the Settings toggle behaves as it does with the real center.
struct NoopReminderNotificationCenter: ReminderNotificationCenter {
    func requestAuthorization() async throws -> Bool { true }
    func scheduleDaily(identifier: String, hour: Int, minute: Int, title: String, body: String) async throws {}
    func removePending(identifier: String) async {}
}

/// Keeps the daily review reminder in step with the settings (ADR-0022, SPEC F-15).
@MainActor @Observable
final class ReviewReminderScheduler {
    static let identifier = "studyreader.review-reminder"

    /// Shown in Settings when the user turned the reminder on but the system denied notifications.
    private(set) var deniedMessage: String?

    @ObservationIgnored private let center: any ReminderNotificationCenter

    init(center: any ReminderNotificationCenter) {
        self.center = center
    }

    /// Off removes the pending notification. On asks for permission, then replaces the pending notification with
    /// one at `minutes` after midnight. Returns false when the reminder is not scheduled although it was requested.
    @discardableResult
    func apply(enabled: Bool, minutes: Int) async -> Bool {
        guard enabled else {
            await center.removePending(identifier: Self.identifier)
            return true
        }
        deniedMessage = nil
        let granted: Bool
        do {
            granted = try await center.requestAuthorization()
        } catch {
            Log.app.error("Notification permission request failed")
            granted = false
        }
        guard granted else {
            await center.removePending(identifier: Self.identifier)
            deniedMessage = String(
                localized: "Notifications are off for StudyReader. Turn them on in System Settings > Notifications."
            )
            return false
        }
        await center.removePending(identifier: Self.identifier)
        do {
            try await center.scheduleDaily(
                identifier: Self.identifier,
                hour: minutes / 60,
                minute: minutes % 60,
                title: String(localized: "Time to review"),
                body: String(localized: "Your StudyReader highlights are waiting.")
            )
        } catch {
            Log.app.error("Scheduling the review reminder failed")
            return false
        }
        return true
    }
}
