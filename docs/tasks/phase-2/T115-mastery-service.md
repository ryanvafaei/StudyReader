# T115: MasteryService

- **Phase:** 2 (E2.3 Mastery; SPEC F-16 AC1, AC2)
- **Agent:** review-engine
- **Depends on:** T107 (`ClozeText`, `ClozeRange`, `ReviewCardContent`), T114, T105 (tests rate through `ReviewService`)
- **ADRs:** **ADR-0021**, ARCHITECTURE §10.3
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 8.

## Goal
Create, change and delete a highlight's Mastery cards (cloze and question & answer) from editor drafts. Each new card starts with a fresh FSRS state and is scheduled on its own; existing cards keep their schedule when edited.

## Files to touch
- `StudyReader/Features/Review/Mastery/MasteryService.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: `let masteryService: MasteryService`)
- `StudyReaderTests/ReviewTests/MasteryServiceTests.swift` (new)

## Interfaces to produce
```swift
struct MasteryDraft: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        case cloze(ranges: [ClozeRange])
        case qa(question: String, answer: String)
    }
    var id: String                   // existing card id, or a new UUID string for an unsaved draft
    var isSaved: Bool                // true when `id` is an existing card
    var kind: Kind
}

enum MasteryError: Error, Equatable, LocalizedError {
    case highlightMissing            // "This highlight no longer exists."
    case emptyCloze                  // "Select at least one word to hide."
    case emptyQuestion               // "Write a question."
    case emptyAnswer                 // "Write an answer."
    case clozeOnImage                // "Image highlights can't have cloze cards."
}

actor MasteryService {
    init(cards: ReviewCardRepository, highlights: HighlightRepository, now: any Now)

    /// editedText ?? text for a text highlight; "" for an image highlight. Missing → .highlightMissing.
    func clozeSourceText(highlightId: String) async throws -> String
    /// The highlight's cloze and qa cards as saved drafts, in cards(forHighlight:) order. Cloze ranges come from
    /// ClozeText.normalized(card.clozeRanges ?? [], in: card.answer ?? "").
    func drafts(highlightId: String) async throws -> [MasteryDraft]
    /// Applies the editor's list:
    /// - validate every draft first (nothing is written if one fails): cloze needs ≥ 1 range valid in the source text
    ///   (`ClozeText.normalized`), not on an image highlight; qa needs a non-empty trimmed question and answer;
    /// - unsaved drafts → ReviewCardFactory.mastery(…) with fresh state at now(); cloze: clozeRanges = normalized
    ///   pairs, answer = the current source text (ADR-0021), question nil; qa: question and answer trimmed;
    ///   inserted together with cards.insertMasteryCards;
    /// - saved drafts whose content changed → cards.updateMasteryCard (a cloze keeps its stored text in `answer`;
    ///   its ranges are validated against that stored text, not the current highlight text);
    /// - saved cards of this highlight missing from `drafts` → cards.deleteMasteryCard.
    func save(_ drafts: [MasteryDraft], highlightId: String) async throws
}
```
- `AppEnvironment.init`: `self.masteryService = MasteryService(cards: reviewCardRepository, highlights: highlightRepository, now: now)`.
- The three write kinds may run as separate repository calls (insert, updates, deletes); each is atomic on its own. Do inserts first, then updates, then deletes, so the passive card is never briefly restored while cards are being replaced.

## Acceptance criteria
Tests use an in-memory `AppEnvironment(…, now: FixedNow(r))`, documents and highlights through repositories, and end with `FTSIntegrity.check`.
1. `MasteryServiceTests/createsClozeAndQA` (SPEC F-16 AC1): save one cloze (ranges over "ATP") and one qa → two cards with types cloze and qa, state new, `dueAt == r`, the cloze's `answer` is the highlight's text and `clozeRanges` the normalized pairs; `drafts(highlightId:)` returns both as saved drafts.
2. `MasteryServiceTests/suspendsPassive` (SPEC F-16 AC2): the passive card is `.mastery` after the save; saving an empty list deletes both Mastery cards and the passive card is active again.
3. `MasteryServiceTests/reviewedWithHiddenAnswers`: `ReviewCardContent.make` of the stored cloze card has `needsReveal`, a front without "ATP" and a back with "**ATP**"; the qa card's front is the question and its back the answer.
4. `MasteryServiceTests/scheduledIndependently`: with a `ReviewService(…, scheduler: ReviewScheduler(enableFuzz: false), calendar: utc)` on the same environment, the daily plan contains both Mastery cards as new cards and not the suspended passive card; rating the cloze card good changes only that card's `fsrsCard`/`dueAt` (the qa card is unchanged).
5. `MasteryServiceTests/editKeepsScheduleAndText`: after rating the cloze card, edit the highlight's `editedText`, then save the cloze draft with a second range → ranges updated, `answer` still the original text, `fsrsCard`/`dueAt` unchanged.
6. `MasteryServiceTests/validation` (table): cloze with no or only invalid ranges → `.emptyCloze`; qa with "  " question → `.emptyQuestion`, empty answer → `.emptyAnswer`; cloze on an image highlight → `.clozeOnImage`; deleted highlight → `.highlightMissing`; in each case no card changed.
7. `MasteryServiceTests/sourceText`: edited text wins over `text`; an image highlight gives "".
8. `./scripts/test.sh StudyReaderTests/MasteryServiceTests StudyReaderTests/AppEnvironmentTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- The editor (T117), the Apple Intelligence suggestion (Phase 3, ADR-0010).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
