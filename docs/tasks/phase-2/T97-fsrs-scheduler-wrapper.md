# T97: Stored FSRS card, ReviewScheduler and ReviewCardFactory

- **Phase:** 2 (E2.1 Scheduler; SPEC F-15, F-18 "reschedule from the last review")
- **Agent:** review-engine
- **Model / effort:** sonnet / high from the first call (the swift-fsrs 5.0.0 API must be read from source; treat as escalated: code-reviewer effort high, two rejections → ask the user)
- **Depends on:** T96
- **ADRs:** ADR-0006, **ADR-0021** (read it first), ADR-0012 (dates)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the unit-test filter in criterion 12.

## Goal
One thin, fully tested wrapper around swift-fsrs. Everything outside `ReviewScheduler.swift` works with our own Codable types, so the stored JSON never depends on the library's encoding (ADR-0021).

## Step 0: read the library API (before writing code)
The pinned version is swift-fsrs **5.0.0**, revision `129e4dc99625ee2dd2ee627fab866f2993e3d7` (`StudyReader.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`). Known facts: `FSRSDefaults` is public but its `defaultW` is internal and `defaultWv6` doesn't exist; `Rating` is public and `CaseIterable` (`PackageLinkTests/fsrsRatingsAvailable`). Read the public API of `FSRS`, `FSRSParameters`, `Card`, `ReviewLog`, `Rating`, `CardState` and the result type of `next(card:now:grade:)`:
- on a Mac: `build/DerivedData/SourcePackages/checkouts/swift-fsrs/Sources/`;
- in a cloud session: `gh api "repos/open-spaced-repetition/swift-fsrs/contents/Sources?ref=129e4dc99625ee2dd2ee627fab866f2993e3d7"` to list files, then `gh api -H "Accept: application/vnd.github.raw" "repos/open-spaced-repetition/swift-fsrs/contents/<path>?ref=129e4dc99625ee2dd2ee627fab866f2993e3d7"` per file.
If you can't read the source, or the library has no way to get its default FSRS-6 weights (21 values) or `w[20]`, report BLOCKED with what you found. Don't copy a weight list by hand. Note the exact API names you used in the report.

## Files to touch
- `StudyReader/Core/Models/StoredFSRSCard.swift` (new: `StoredFSRSCard`, `StoredFSRSLog`, `ReviewRating`; no `import FSRS`)
- `StudyReader/Features/Review/Scheduling/ReviewScheduler.swift` (new: the only app file with `import FSRS`)
- `StudyReader/Features/Review/Scheduling/ReviewCardFactory.swift` (new)
- `StudyReaderTests/ReviewTests/ReviewSchedulerTests.swift` (new)
- `StudyReaderTests/ReviewTests/StoredFSRSCardTests.swift` (new)
- `project.yml` only if a new folder isn't picked up (XcodeGen collects folder sources; run `xcodegen generate` via the build script as usual)

## Interfaces to produce
```swift
// Core/Models/StoredFSRSCard.swift
/// Our JSON for reviewCard.fsrsCard (ADR-0021). Dates encode as Unix seconds, keys sorted.
struct StoredFSRSCard: Codable, Sendable, Equatable {
    var due: Date
    var stability: Double = 0
    var difficulty: Double = 0
    var elapsedDays: Double = 0
    var scheduledDays: Double = 0
    var learningSteps: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var state: ReviewCardState = .new
    var lastReview: Date? = nil

    /// A card never reviewed: state new, all counters 0, lastReview nil, due = due.storageRounded.
    static func new(due: Date) -> StoredFSRSCard
    /// Every key is optional: missing → the defaults above; missing `due` → Date(timeIntervalSince1970: 0). "{}" decodes.
    init(json: String) throws
    /// JSONEncoder, outputFormatting [.sortedKeys], dateEncodingStrategy .secondsSince1970; nil lastReview is omitted.
    func json() throws -> String
}

/// Our JSON for reviewLog.fsrsLog. Fields describe the card BEFORE the review, plus the review time.
struct StoredFSRSLog: Codable, Sendable, Equatable {
    var rating: ReviewRating
    var state: ReviewCardState
    var due: Date
    var stability: Double
    var difficulty: Double
    var elapsedDays: Double
    var lastElapsedDays: Double
    var scheduledDays: Double
    var learningSteps: Int
    var review: Date
    init(json: String) throws      // same coding rules as StoredFSRSCard (missing keys → 0 / .new / .again / 1970)
    func json() throws -> String
}

/// reviewLog.rating raw values = FSRS Rating raw values (ADR-0021). Never `.manual`.
enum ReviewRating: Int, Codable, Sendable, CaseIterable {
    case again = 1, hard = 2, good = 3, easy = 4
}

// Features/Review/Scheduling/ReviewScheduler.swift
import FSRS
struct ScheduledReview: Sendable, Equatable {
    var card: StoredFSRSCard      // after the review; due and lastReview storage-rounded
    var log: StoredFSRSLog        // review = now.storageRounded
}
enum ReviewSchedulerError: Error, Equatable {
    case invalidRetention          // retention not in the open interval (0, 1)
}
struct ReviewScheduler: Sendable {
    static let fsrs6WeightCount = 21
    /// The library's default FSRS-6 weights, read once from its default parameters.
    var weights: [Double]
    var enableFuzz: Bool
    init(enableFuzz: Bool = true)

    /// FSRS(parameters: requestRetention: retention, w: weights, enableFuzz, enableShortTerm: false), next(card:now:grade:).
    func schedule(_ card: StoredFSRSCard, rating: ReviewRating, now: Date, retention: Double) throws -> ScheduledReview
    /// ADR-0021 formula. state == .new or lastReview == nil → card.due unchanged. Otherwise
    /// lastReview + days, days = clamp(round(S / F * (pow(retention, 1 / D) - 1)), 1...36_500), D = -weights[20],
    /// F = pow(0.9, 1 / D) - 1, S = card.stability; one day = 86_400 s (as in FSRS); result storage-rounded. No fuzz.
    /// Invalid retention → card.due.
    func rescheduledDue(_ card: StoredFSRSCard, retention: Double) -> Date
}

// Features/Review/Scheduling/ReviewCardFactory.swift
enum ReviewCardFactory {
    /// id UUID().uuidString, cardType .passive, fsrsCard = StoredFSRSCard.new(due: now).json(), dueAt = now.storageRounded,
    /// state .new, not suspended, introducedAt nil, createdAt = now.storageRounded. Suspension is set by the repository.
    static func passive(highlightId: String, now: Date) throws -> ReviewCard
    /// Same, with cardType .cloze or .qa and the given columns (T115 validates them). cardType .passive throws
    /// ReviewCardFactoryError.notMastery (no precondition or fatalError).
    static func mastery(highlightId: String, cardType: CardType, clozeRanges: [[Int]]?, question: String?,
                        answer: String?, now: Date) throws -> ReviewCard
}
enum ReviewCardFactoryError: Error, Equatable { case notMastery }
```
- Map `ReviewCardState` ↔ FSRS `CardState` case by case (new, learning, review, relearning) and `ReviewRating` ↔ `Rating` by case, not by raw value. Keep the mapping functions `internal` so tests can call them through `@testable import`.
- If a library field is an `Int` where ours is a `Double` (or the other way), convert at the boundary. If the library has a field we don't store, or we store one it lacks, say so in the report; the stored shape above stays.

## Acceptance criteria
Tests use `ReviewScheduler(enableFuzz: false)`, fixed dates (`TestData.referenceDate` and offsets from it) and a UTC calendar where a calendar is needed. Table-driven where marked.
1. `ReviewSchedulerTests/usesFSRS6Weights`: `weights.count == ReviewScheduler.fsrs6WeightCount`.
2. `ReviewSchedulerTests/newCardMatchesLibraryEmptyCard`: `StoredFSRSCard.new(due: d)` mapped to `FSRS.Card` equals `FSRS.Card(due: d)` field by field, and maps back to itself.
3. `ReviewSchedulerTests/firstReviewTable` (table over all four ratings at retention 0.9): from `StoredFSRSCard.new(due: t)` rated at `t`: `state != .new`, `reps == 1`, `lastReview == t`, `due > t`, `due == due.storageRounded`, `log.rating == rating`, `log.state == .new`, `log.review == t`. Also: due(again) ≤ due(hard) ≤ due(good) ≤ due(easy). Pin the exact `scheduledDays` for each rating as observed from the library on the first passing run (a characterization table guarding library upgrades); list the values in the report.
4. `ReviewSchedulerTests/repeatedForgetting`: a card reviewed good twice, then again three times (each at its due date): `lapses` grows by 1 per again in review state, and each again interval ≤ the preceding good interval.
5. `ReviewSchedulerTests/longIntervals`: six goods, each on the due date: intervals never shrink, the last is > 30 days, and no due exceeds `now + 36_500` days.
6. `ReviewSchedulerTests/retentionPerFrequency` (table 0.80 / 0.90 / 0.95, same card, rating good): interval(0.80) ≥ interval(0.90) ≥ interval(0.95), with interval(0.80) > interval(0.95).
7. `ReviewSchedulerTests/fuzzOffIsDeterministic`: the same input twice gives equal `ScheduledReview`s.
8. `ReviewSchedulerTests/rejectsInvalidRetention`: 0, 1 and 1.2 throw `.invalidRetention`.
9. `ReviewSchedulerTests/rescheduledDueFollowsRetention`: a review-state card with stability 10 and lastReview L: at 0.9 the result is `L + 10 days`; 0.95 is earlier, 0.80 later; a new card and a card with lastReview nil keep `due`.
10. `StoredFSRSCardTests/jsonRoundTrip`, `StoredFSRSCardTests/emptyJSONDecodesAsNewCard` (`"{}"` → state new, counters 0, due 1970), `StoredFSRSCardTests/jsonKeysAreStable`: a card with due 1_790_000_000, stability 10.5, difficulty 5, reps 2, lastReview 1_789_000_000, state review encodes exactly as `{"difficulty":5,"due":1790000000,"elapsedDays":0,"lapses":0,"lastReview":1789000000,"learningSteps":0,"reps":2,"scheduledDays":0,"stability":10.5,"state":"review"}`; the same three tests for `StoredFSRSLog` (key test with your own fixed value).
11. `StoredFSRSCardTests/factoryPassiveCard`: `ReviewCardFactory.passive` gives cardType passive, state new, dueAt == createdAt == now, `StoredFSRSCard(json: fsrsCard) == .new(due: now)`; `mastery(cardType: .passive, …)` throws `.notMastery`.
12. `./scripts/test.sh StudyReaderTests/ReviewSchedulerTests StudyReaderTests/StoredFSRSCardTests StudyReaderTests/PackageLinkTests StudyReaderTests/NameClashTests` passes; `./scripts/build.sh` succeeds.
13. Reviewer Grep: `import FSRS` appears in app code only in `ReviewScheduler.swift`.

## Out of scope
- Repositories, frequency policy (T98), sessions. No GRDB code in this task.
- Changing `PackageLinkTests` or `NameClashTests`.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
