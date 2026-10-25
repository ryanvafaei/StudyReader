---
name: tag-field-and-manager-notes
description: T49 lessons: nonisolated static default args under MainActor, String Catalog keys added by hand, tag model test patterns
metadata:
  type: feedback
---

Default argument values in a `@MainActor` class's static functions must be `nonisolated static`.
A plain `static let` referenced as a default argument (`limit: Int = suggestionLimit`) fails to build with
"main actor-isolated default value in a nonisolated context". Fix: mark the constant `nonisolated static let`.

**Why:** Swift 6 strict concurrency; the default argument is evaluated in a nonisolated context.
**How to apply:** Any pure helper on a `@MainActor` model that is used with a default argument.

The String Catalog (`StudyReader/Resources/Localizable.xcstrings`) is NOT updated by `./scripts/build.sh`.
New UI strings must be added by hand as empty entries (`"Key" : {` with a blank body, the same shape as the
existing ones), and interpolations use `%@` / `%lld` keys (e.g. `"Add tag %@"`, `"%lld documents"`).
Check for duplicate keys after editing (a quick Python `object_pairs_hook` check works).

**Why:** Earlier catalog entries were added by Xcode-style extraction; the CLI build leaves the file unchanged.
**How to apply:** Every task that adds `Text`, `Button`, `Label`, `TextField`, or `.accessibilityLabel` strings.

Test pattern used for tag models: pure static helpers are tested without the view; model tests use
`AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))` and `TestFileStore.remove` in `defer`.
Test filters take the struct names: `./scripts/test.sh StudyReaderTests/TagFieldModelTests ...`.
