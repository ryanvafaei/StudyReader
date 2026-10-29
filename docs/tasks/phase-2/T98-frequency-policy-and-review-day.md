# T98: FrequencyPolicy and ReviewDay

- **Phase:** 2 (E2.1 Scheduler; SPEC F-19, F-15 "resets at 04:00", F-20 intervals)
- **Agent:** review-engine
- **Depends on:** T97 (order only; no shared files)
- **ADRs:** ADR-0006, **ADR-0021** (suspension rule), **ADR-0022** (review day)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 5.

## Goal
Two pure helpers every later Phase 2 task uses: the frequency → retention mapping with its precedence and suspension rule (F-19, ADR-0021), and the 04:00 review-day boundary (ADR-0022). Both live in `Core/` because repositories use them too.

## Files to touch
- `StudyReader/Core/Models/FrequencyPolicy.swift` (new)
- `StudyReader/Core/Support/ReviewDay.swift` (new)
- `StudyReaderTests/ReviewTests/FrequencyPolicyTests.swift` (new; the suite type must be `struct FrequencyPolicyTests`, not `private`: T101 adds tests to it in an extension)
- `StudyReaderTests/ReviewTests/ReviewDayTests.swift` (new)

## Interfaces to produce
```swift
// Core/Models/FrequencyPolicy.swift
/// SPEC F-19 and ADR-0021. Pure.
enum FrequencyPolicy {
    /// off → nil, low → 0.80, normal → 0.90, high → 0.95.
    static func retention(for frequency: ReviewFrequency) -> Double?
    /// Card override beats the category frequency.
    static func effectiveFrequency(override: ReviewFrequency?, category: ReviewFrequency) -> ReviewFrequency
    /// retention(for: effectiveFrequency(override:category:)).
    static func retention(override: ReviewFrequency?, category: ReviewFrequency) -> Double?
    /// The one suspension rule (ADR-0021), in this order:
    /// 1. cardType == .passive && highlightHasMasteryCards → .mastery
    /// 2. effective frequency == .off → (override == .off ? .user : .frequencyOff)
    /// 3. otherwise nil (not suspended)
    static func suspendedReason(cardType: CardType, highlightHasMasteryCards: Bool,
                                override: ReviewFrequency?, category: ReviewFrequency) -> SuspendedReason?
    /// SPEC F-15/F-17: a new highlight gets a passive card automatically only if this is true:
    /// frequency != .off && autoCreateCards.
    static func createsCardAutomatically(frequency: ReviewFrequency, autoCreateCards: Bool) -> Bool
}

// Core/Support/ReviewDay.swift
/// Review days start at 04:00 local time (SPEC F-15, ADR-0022). Pure; the calendar carries the time zone.
enum ReviewDay {
    static let boundaryHour = 4
    /// 04:00 on the calendar day of (date − 4 h): calendar.startOfDay(for: date.addingTimeInterval(-4 * 3600)),
    /// then calendar.date(bySettingHour: 4, minute: 0, second: 0, of: thatDay). Returns that date (never nil: fall
    /// back to startOfDay + 4 h if the calendar returns nil).
    static func start(containing date: Date, calendar: Calendar) -> Date
    /// The next boundary: calendar.date(byAdding: .day, value: 1, to: start(containing:)) (DST-safe).
    static func start(after date: Date, calendar: Calendar) -> Date
    /// Whole review days from the day containing `from` to the day containing `to` (negative if `to` is earlier):
    /// calendar.dateComponents([.day], from: start(containing: from), to: start(containing: to)).day ?? 0.
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int
    /// Calendar weekday (1 = Sunday … 7 = Saturday) of the review day containing `date`.
    static func weekday(of date: Date, calendar: Calendar) -> Int
}
```

## Acceptance criteria
1. `FrequencyPolicyTests/retentionMapping` (table, SPEC F-19 AC1): off nil, low 0.80, normal 0.90, high 0.95.
2. `FrequencyPolicyTests/precedence` (table over every override × category pair, 5 × 4 = 20 rows incl. override nil): `effectiveFrequency` is the override when set, else the category; `retention(override:category:)` follows.
3. `FrequencyPolicyTests/suspendedReasonRule` (table): passive + mastery → `.mastery` even with override high and category off; cloze/qa never `.mastery`; override off → `.user` (also when the category is high); override nil + category off → `.frequencyOff`; override high + category off → nil; nothing set + category normal → nil. Also `createsCardAutomatically`: (off, true) false, (normal, false) false, (low, true) true.
4. `ReviewDayTests` (build every date with `DateComponents` in the test calendar):
   - `startUsesFourOClock` (UTC calendar): 2026-10-01 03:59 → 2026-09-30 04:00; 04:00 → 2026-10-01 04:00; 23:30 → 2026-10-01 04:00.
   - `startAfterIsTheNextBoundary`: 2026-10-01 10:00 → 2026-10-02 04:00; 2026-10-02 03:00 → 2026-10-02 04:00.
   - `daylightSavingChange` (calendar with time zone `Europe/Berlin`; summer time ends 2026-10-25 03:00 → 02:00): `start(containing:)` 2026-10-25 12:00 local = 2026-10-25 04:00 local; `start(after:)` 2026-10-24 12:00 local = 2026-10-25 04:00 local, 25 h after 2026-10-24 04:00.
   - `daysBetweenCountsReviewDays`: 2026-10-01 23:00 → 2026-10-02 03:00 is 0; → 2026-10-02 05:00 is 1; → 2026-10-08 05:00 is 7; reversed is negative.
   - `weekdayOfReviewDay`: Thursday 2026-10-01 at 02:00 is weekday 4 (Wednesday's review day); at 05:00 weekday 5.
5. `./scripts/test.sh StudyReaderTests/FrequencyPolicyTests StudyReaderTests/ReviewDayTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Writing suspension to the database (T99 `ReviewSuspension`, T101). No GRDB code here.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer review-engine haiku medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met; CI build and full unit tests green (runs 40865474738, 40865852299)
