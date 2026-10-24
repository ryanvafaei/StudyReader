# T21: Storage-rounded dates so saved records equal fetched records

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` L4)
- **Agent:** data-layer
- **Depends on:** T13
- **ADRs:** docs/decisions/0012-data-layer-conventions.md ("Dates" bullet)
- **Visual check needed:** no

## Goal
Records store dates as REAL Unix seconds. `Date` keeps seconds since 2001, so converting through the 1970 offset loses the last bit for about half of real timestamps. A record saved with `SystemNow()` and fetched back is then `!=` to the original. Add `Date.storageRounded`, which rounds down to a 1/1024-second grid that survives the round trip exactly, and make `SystemNow` return rounded dates. The storage format stays the same: Unix seconds, REAL, and no migration.

Why 1/1024 and not milliseconds: a multiple of 2⁻¹⁰ needs at most 42 significant bits around 2³² seconds, so both `timeIntervalSince1970` and its inverse are exact in a `Double`. Whole milliseconds aren't binary fractions, so they still lose a bit.

## Files to touch
- `StudyReader/Core/Models/StudyRecord.swift` (modify: add the `Date` extension)
- `StudyReader/Core/Support/Now.swift` (modify `SystemNow`)
- `StudyReaderTests/CoreTests/DateStorageTests.swift` (new)

## Interfaces to produce
```swift
extension Date {
    /// Rounded down to a multiple of 1/1024 s. Such dates survive the REAL Unix-seconds round trip exactly
    /// (ADR-0012), so a saved record is == to its fetched copy. Idempotent.
    var storageRounded: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate * 1024).rounded(.down) / 1024)
    }
}
```
```swift
struct SystemNow: Now {
    init() {}
    func callAsFunction() -> Date { Date().storageRounded }
}
```
Update the `SystemNow` doc comment: "The only place in the app that calls `Date()`. Returns storage-rounded dates (ADR-0012)." `FixedNow` (tests) is unchanged. Tests choose their own dates.

## Tests (`@Suite struct DateStorageTests`)
Generate sample dates deterministically, with no randomness:
```swift
private static let samples: [Date] = (0..<10_000).map {
    Date(timeIntervalSinceReferenceDate: 788_918_400 + Double($0) * 9_467.123_456_7)   // 2026-01-01 … ~2029
}
```
- `unroundedDatesCanDrift`: count the samples `d` where `Date(timeIntervalSince1970: d.timeIntervalSince1970) != d`, and expect the count to be `> 0`. This documents the bug. If it is 0, report it; don't delete the test.
- `storageRoundedDatesSurviveUnixSeconds`: for every sample, with `r = d.storageRounded`, expect `Date(timeIntervalSince1970: r.timeIntervalSince1970) == r`. Assert one `#expect` on the failure count `== 0`, not 10,000 separate expectations.
- `storageRoundedIsOnGridAndClose`: for every sample:
  - `r.timeIntervalSinceReferenceDate * 1024` equals its `.rounded()` value;
  - `r <= d`;
  - `d.timeIntervalSince(r) < 1.0 / 1024`;
  - `r.storageRounded == r`.
- `recordRoundTripIsExact`: build `TestData.highlight(documentId:, createdAt: Date(timeIntervalSinceReferenceDate: 815_000_000.123).storageRounded)` with its document, insert both into `AppDatabase.makeInMemory()`, and expect `fetched == highlight`. This is the bug report's failing test, with the fix applied.
- `systemNowIsStorageRounded`: `let date = SystemNow()()`, then `#expect(date == date.storageRounded)`.

Keep `NowTests/systemNowIsCurrent` unchanged. It must still pass (the rounding is less than 1 ms).

## Acceptance criteria
1. Raw dates can drift through Unix seconds (documents the bug). → test `DateStorageTests/unroundedDatesCanDrift`
2. Storage-rounded dates round-trip exactly. → test `DateStorageTests/storageRoundedDatesSurviveUnixSeconds`
3. Rounding is down, under 1/1024 s, on the grid, and idempotent. → test `DateStorageTests/storageRoundedIsOnGridAndClose`
4. A record with a rounded fractional date equals its fetched copy. → test `DateStorageTests/recordRoundTripIsExact`
5. `SystemNow` returns rounded dates. → tests `DateStorageTests/systemNowIsStorageRounded`, `NowTests/systemNowIsCurrent`
6. The full suite passes with no new warnings.

## Out of scope
- Changing the date column format or encoding strategy (still `.timeIntervalSince1970`).
- Rounding inside record initializers or custom GRDB strategies.
- FSRS date handling (Phase 2 review-engine applies `.storageRounded` per ADR-0012).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 143/143, 1/1024 s grid math exact, round trip verified through real storage path.
