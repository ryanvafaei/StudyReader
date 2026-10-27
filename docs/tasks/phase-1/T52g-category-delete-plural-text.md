# T52g: Category delete confirmation agrees with the document count

- **Phase:** 1 (T52 checkpoint fix; SPEC F-01 categories, built in T50)
- **Agent:** ui-builder
- **Depends on:** T52
- **ADRs:** none
- **Visual check needed:** no (covered by UI test and a unit test)

## Goal
Step 24 of `docs/checkpoints/T52-manual-2026-10-25.md`: deleting a category with one document shows "Its 1 document move to Other." The verb must agree with the count. Cause: `CategoryManagerView`'s confirmation message is `Text("Its \(TagUsageFormat.documents(row.documentCount)) move to Other.")`. That puts the count wording into a `%@` slot, and the verb after it is fixed (catalog key `"Its %@ move to Other."`). Fix: build the whole sentence from one String Catalog entry with plural variations (one/other), so every count reads correctly.

Other count strings were checked and are correct, so they stay as they are. The tag delete message ("It is removed from N highlight(s) and N document(s). They aren't deleted.") reads correctly for every count. The tag merge message has no count. `TagUsageFormat.documents` and `LibraryItemFormat.highlights` already pick singular or plural by count.

## Files to touch
- `StudyReader/Features/Library/Categories/CategoryManagerModel.swift` (modify: one static function)
- `StudyReader/Features/Library/Categories/CategoryManagerView.swift` (modify: the confirmation `message:` only)
- `StudyReader/Resources/Localizable.xcstrings` (modify: remove one key, add one plural entry)
- `StudyReaderTests/LibraryTests/CategoryManagerModelTests.swift` (modify: one test)

## Interfaces to produce
```swift
// CategoryManagerModel
/// Message of the delete confirmation: "Its 1 document moves to Other." / "Its N documents move to Other."
/// Built from one String Catalog entry with plural variations, so the noun and the verb agree with the count.
nonisolated static func deleteConfirmationMessage(documentCount: Int) -> String
```

## What to do
1. Add `deleteConfirmationMessage(documentCount:)` to `CategoryManagerModel`. Its body is exactly `String(localized: "Its \(documentCount) documents move to Other.")`. The interpolated `Int` makes the catalog key `"Its %lld documents move to Other."`. Don't branch on the count in code; the catalog does it.
2. `CategoryManagerView`: change the confirmation's `message:` closure to `Text(CategoryManagerModel.deleteConfirmationMessage(documentCount: row.documentCount))`. Leave everything else in the view unchanged. `CategoryRow` keeps using `TagUsageFormat.documents`.
3. `Localizable.xcstrings`: delete the entry `"Its %@ move to Other." : { },`. Add this entry in alphabetical key order, next to where the old one was. The file is JSON: keep its 2-space indentation and the `" : "` spacing.
   ```json
   "Its %lld documents move to Other." : {
     "localizations" : {
       "en" : {
         "variations" : {
           "plural" : {
             "one" : {
               "stringUnit" : {
                 "state" : "translated",
                 "value" : "Its %lld document moves to Other."
               }
             },
             "other" : {
               "stringUnit" : {
                 "state" : "translated",
                 "value" : "Its %lld documents move to Other."
               }
             }
           }
         }
       }
     }
   },
   ```
   Check that the whole file is still valid JSON: no trailing comma before a closing `}`, and commas between all entries.
4. Add the unit test below.

## Acceptance criteria
1. Unit test `CategoryManagerModelTests/deleteMessageAgreesWithCount`: `deleteConfirmationMessage(documentCount:)` returns these exact strings for 0, 1, 2 and 21: "Its 0 documents move to Other.", "Its 1 document moves to Other.", "Its 2 documents move to Other.", "Its 21 documents move to Other.". Unit tests run inside the app (`TEST_HOST`), so `String(localized:)` reads the app's compiled catalog. If the test shows the catalog isn't used (for example "Its 1 documents move to Other."), report BLOCKED. Don't add a code branch on the count.
2. Existing `CategoryManagerModelTests` keep passing (`deleteResetsDefaultCategory`, `deleteKeepsOtherDefaults`, `errorsAreShown`): `./scripts/test.sh StudyReaderTests/CategoryManagerModelTests`.
3. UI test `StudyReaderUITests/CategoryManagerTests/testCreateRenameAssignAndDeleteACategory` (steps 22–24) turns green. It fails today at line ~75 with "Delete confirmation text is wrong." and expects the static text exactly `Its 1 document moves to Other.` in the confirmation dialog. `CategoryManagerTests/testDeletingTheDefaultCategoryResetsSettingsToLectureSlides` (step 25) keeps passing.
4. `grep "Its %@ move to Other."` finds nothing in `StudyReader/`. `./scripts/build.sh` succeeds.

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md); ui-tester runs the named UI tests during review. If names have shifted, use the test in `CategoryManagerTests.swift` covering step 24.

## Out of scope
The tag delete and merge messages, `TagUsageFormat`, `LibraryItemFormat`, the category row text, other languages (the catalog only has `en`), and any change to `CategoryRepository` or the delete flow.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-26, code-reviewer sonnet medium: APPROVED. Plural variations (one/other, %lld) in Localizable.xcstrings via CategoryManagerModel.deleteConfirmationMessage; unit test 0/1/2/21 and CategoryManagerTests 3/3 pass on CI. Test assumes the en locale (app is English-only).
- 2026-10-27, implementer record (backfill): ui-builder, Haiku per agent file (.claude/agents/ui-builder.md; model not verified at run time), effort medium; no rework.
