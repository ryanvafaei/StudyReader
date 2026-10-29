# T106: Review settings and the Settings > Review tab

- **Phase:** 2 (E2.2 Daily review; SPEC F-15 limits and rating buttons, F-17 per-category auto-create, F-19 category frequencies, F-22 Review tab)
- **Agent:** ui-builder
- **Depends on:** T101 (category writes), T104 (`DailyLimits`)
- **ADRs:** ADR-0015 (settings), **ADR-0022**
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none in this task (T112 adds one for the tab). Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
Store the review preferences per Mac (`SettingsStore`, mirrored live by `AppSettings`) and show the Settings > Review tab: daily limit, new per day, four rating buttons, reminder on/off and time (stored only; T113 schedules it), and per category its frequency and "create cards automatically".

## Files to touch
- `StudyReader/Core/Support/SettingsStore.swift` (modify: five keys)
- `StudyReader/App/AppSettings.swift` (modify: five properties, `dailyLimits`)
- `StudyReader/Features/Settings/ReviewSettingsView.swift` (new: the tab and `ReviewSettingsModel`)
- `StudyReader/Features/Settings/SettingsView.swift` (modify: add the tab between Reading and Data; update the doc comment)
- `StudyReaderTests/CoreTests/SettingsStoreTests.swift`, `StudyReaderTests/AppTests/AppSettingsTests.swift` (modify: add tests)
- `StudyReaderTests/AppTests/ReviewSettingsModelTests.swift` (new; next to `SettingsCategoryOptionsTests`)

## Interfaces to produce
```swift
// SettingsStore (keys "settings.<name>", ADR-0015). Out-of-range stored or assigned values are clamped.
var reviewDailyLimit: Int          // default 15, 1...500
var reviewNewPerDay: Int           // default 5, 0...100
var showFourRatingButtons: Bool    // default false
var reviewReminderEnabled: Bool    // default false
var reviewReminderMinutes: Int     // minutes after local midnight, default 540 (09:00), 0...1439
static let reviewDailyLimitRange = 1...500
static let reviewNewPerDayRange = 0...100

// AppSettings: one stored property per key above, same names, `didSet` writes through (existing pattern), plus
var dailyLimits: DailyLimits { get }   // DailyLimits(dailyLimit: reviewDailyLimit, newPerDay: reviewNewPerDay)

// Features/Settings/ReviewSettingsView.swift
@MainActor @Observable
final class ReviewSettingsModel {
    init(categories: CategoryRepository)
    private(set) var categories: [DocumentCategory] = []
    private(set) var errorMessage: String?
    func observe() async                                   // categories.observeAll() until cancelled
    func setFrequency(_ frequency: ReviewFrequency, for categoryId: String) async   // CategoryRepository.setFrequency
    func setAutoCreateCards(_ enabled: Bool, for categoryId: String) async          // CategoryRepository.setAutoCreateCards
}
```
- Tab label "Review", system image `rectangle.stack` (same as the sidebar). Order: General, Reading, Review, Data, Google (F-22 lists Google before Data, but Phase 1 shipped Data before Google and `SettingsTests` relies on the toolbar buttons by name only, so keep Data, Google at the end).
- Content (`Form`, `.formStyle(.grouped)`, scrolls if needed inside the 520-wide window):
  - Section "Daily review": `Stepper` "Daily limit: N" (range above), `Stepper` "New cards per day: N", `Toggle` "Show four rating buttons (Again, Hard, Good, Easy)".
  - Section "Reminder": `Toggle` "Remind me to review", `DatePicker` "Time" (`.hourAndMinute`), disabled while the toggle is off. The binding converts `reviewReminderMinutes` ↔ a `Date` on today's local date (calendar from the environment); nothing is scheduled in this task.
  - Section "Categories": one row per category in `fetchAll()` order: name, a `Picker` (Off, Low, Normal, High; labels `String(localized:)`) and a `Toggle` "Create cards automatically". A footer line: "Off suspends the category's cards. Cards for new highlights are created only when this is on and the frequency isn't Off."
  - `errorMessage` ("The category couldn't be changed.") under the section when a write fails.
- Accessibility labels: "Daily limit", "New cards per day", "Show four rating buttons", "Remind me to review", "Reminder time", "Frequency for <name>", "Create cards automatically for <name>".
- **Constraint (HANDOFF standing rule):** not triggered: the Settings window isn't the main window.

## Acceptance criteria
1. `SettingsStoreTests/reviewDefaultsAndClamping` (own suite via `TestSettings.make()`/`remove`): defaults 15, 5, false, false, 540; assigning 0 / 900 to the daily limit stores 1 / 500; −1 / 101 new per day → 0 / 100; minutes −5 / 2000 → 0 / 1439; a stored out-of-range value written directly to the defaults is clamped on read.
2. `AppSettingsTests/reviewSettingsWriteThrough`: each property writes through to the store; a new `AppSettings` on the same store reads the values back; `dailyLimits` reflects them.
3. `ReviewSettingsModelTests/frequencyAndAutoCreateWrites` (in-memory environment, `.timeLimit(.minutes(1))`): after `observe()` emits the five built-ins, `setFrequency(.off, for: notes)` and `setAutoCreateCards(false, for: paper)` show up in the next emission and in `CategoryRepository.fetch`.
4. `ReviewSettingsModelTests/failedWriteShowsMessage`: `setFrequency` for an unknown id sets `errorMessage`.
5. Existing `SettingsStoreTests`, `AppSettingsTests` pass unchanged.
6. `./scripts/test.sh StudyReaderTests/SettingsStoreTests StudyReaderTests/AppSettingsTests StudyReaderTests/ReviewSettingsModelTests` passes; `./scripts/build.sh` succeeds.
7. Report "Visual check needed: yes" with this Mac row. **T106 Settings > Review** (light and dark): ⌘, → Review tab between Reading and Data; daily limit and new-per-day steppers stop at their bounds; four-buttons toggle; reminder time picker disabled until the toggle is on; one row per category (five built-ins plus custom ones) with frequency picker and auto-create toggle, nothing truncated at 520 pt; set Notes to Off and back, reopen Settings: values kept; quit and relaunch: values kept.

## Out of scope
- Scheduling the reminder (T113). The review screen reading these values (T108/T109).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met; CI build and full unit tests green, 838 tests (runs 40888963072, 40889288456). Visual check pending (Mac row in VISUAL_CHECKS.md)
