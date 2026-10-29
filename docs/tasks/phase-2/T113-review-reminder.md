# T113: Daily review reminder notification

- **Phase:** 2 (E2.2; SPEC F-15 "Optional reminder notification at a chosen time (default off)", F-22 Review tab)
- **Agent:** ui-builder
- **Depends on:** T106 (reminder settings), T112 (order only)
- **ADRs:** **ADR-0022** (reminder: UserNotifications, fixed text, repeating daily), ADR-0015
- **Visual check needed:** yes (Mac row below; notifications can't be checked on CI)
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 5.
- **Open question:** README Q7. If the user defers the reminder to Phase 3, skip this task.

## Goal
When "Remind me to review" is on, the Mac shows one local notification every day at the chosen time. Turning it off removes it. Changing the time reschedules it. Nothing else in the app changes.

## Files to touch
- `StudyReader/Features/Review/Reminder/ReviewReminderScheduler.swift` (new: the protocol seam, the live adapter, the scheduler)
- `StudyReader/App/AppSession.swift` (modify: own the scheduler, apply settings at start and on change)
- `StudyReader/Features/Settings/ReviewSettingsView.swift` (modify: show the "notifications are off" message)
- `StudyReaderTests/ReviewTests/ReviewReminderSchedulerTests.swift` (new)
- `StudyReaderTests/Support/StubNotificationCenter.swift` (new)

## Interfaces to produce
```swift
/// The part of UNUserNotificationCenter we use. Tests stub it.
protocol ReminderNotificationCenter: Sendable {
    func requestAuthorization() async throws -> Bool          // [.alert, .sound]
    func scheduleDaily(identifier: String, hour: Int, minute: Int, title: String, body: String) async throws
    func removePending(identifier: String) async
}
struct SystemReminderNotificationCenter: ReminderNotificationCenter { … }   // UNUserNotificationCenter.current(),
                                                                          // UNCalendarNotificationTrigger(repeats: true)

@MainActor @Observable
final class ReviewReminderScheduler {
    static let identifier = "studyreader.review-reminder"
    init(center: any ReminderNotificationCenter)
    /// Shown in Settings when the user turned the reminder on but the system denied notifications.
    private(set) var deniedMessage: String?
    /// enabled == false → removePending. enabled == true → requestAuthorization; denied → removePending,
    /// deniedMessage = "Notifications are off for StudyReader. Turn them on in System Settings > Notifications.",
    /// returns false; granted → removePending then scheduleDaily(hour: minutes / 60, minute: minutes % 60,
    /// title: "Time to review", body: "Your StudyReader highlights are waiting."), deniedMessage = nil, returns true.
    @discardableResult
    func apply(enabled: Bool, minutes: Int) async -> Bool
}
```
- `AppSession`: `let reminder: ReviewReminderScheduler`, built with `SystemReminderNotificationCenter()` only when the environment is the user's library; tests, previews and the in-memory library get a no-op center (add `static func noop()` or a `NoopReminderNotificationCenter` in the same file) so CI and UI tests never ask for notification permission. Decide "user's library" the same way `runsExportSync` does (`environment.runsExportSync`), and say so in a comment.
- Apply once when the session is created (`Task { await reminder.apply(enabled:minutes:) }`) and whenever `settings.reviewReminderEnabled` or `settings.reviewReminderMinutes` changes. The simplest place: `ReviewSettingsView` calls `apply` from `.onChange` of both values; plus the one call at session start.
- If `apply` returns false because permission was denied, set `settings.reviewReminderEnabled = false` and show `deniedMessage` under the toggle.
- Clicking the notification only brings the app to the front (system default). No navigation.

## Acceptance criteria
1. `ReviewReminderSchedulerTests/enablingSchedulesDaily` (stub center records calls): `apply(true, 545)` → one `requestAuthorization`, then `removePending` and `scheduleDaily(identifier, 9, 5, …)`.
2. `ReviewReminderSchedulerTests/disablingRemoves`: `apply(false, 545)` → only `removePending`; no authorization request.
3. `ReviewReminderSchedulerTests/deniedTurnsOffAndExplains`: stub denies → returns false, `deniedMessage` set, nothing scheduled.
4. `ReviewReminderSchedulerTests/timeChangeReschedules`: `apply(true, 540)` then `apply(true, 1200)` → the last `scheduleDaily` is 20:00 and each schedule is preceded by a `removePending`.
5. `./scripts/test.sh StudyReaderTests/ReviewReminderSchedulerTests StudyReaderTests/AppSessionTests` passes; `./scripts/build.sh` succeeds.
6. Report "Visual check needed: yes" with this Mac row. **T113 Reminder** (Mac, real library): Settings > Review > Remind me to review → macOS asks for notification permission once; set the time two minutes ahead → a "Time to review" notification appears at that time; change the time → only one notification at the new time the next day; turn it off → none; deny permission in System Settings, turn it on → the toggle turns itself off and the message shows.

## Out of scope
- A due count in the notification text (it would need a background refresh).
- Opening the Review section from the notification.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met (startup apply placed in AppLaunchModel instead of AppSession init: accepted); CI build and full unit tests green, 871 tests (runs 40919381593, 40919875100). Visual check pending (Mac row in VISUAL_CHECKS.md)
