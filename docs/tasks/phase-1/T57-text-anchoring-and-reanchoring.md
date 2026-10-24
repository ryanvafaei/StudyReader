# T57: Text anchoring and re-anchoring

- **Phase:** 1 (E1.4: F-06 Markdown highlights; reused by the Phase 3 text view)
- **Agent:** pdf-engine
- **Depends on:** none
- **ADRs:** docs/decisions/0004-highlight-anchoring.md, ARCHITECTURE §5.2–§5.3 (read in full)
- **Reference:** `.references/reader-source/Reader/ReaderCore/ReadingTypes.swift` (`TextAnchor`, `ReaderLocator`: exact/prefix/suffix shape). Read only this file.
- **Visual check needed:** no

## Goal
Create `TextAnchor`s from an `NSRange` in a rendered string, and find them again when the string changed (new `MarkdownRenderer.version`, or the text at the stored range differs), tolerant of whitespace changes. Pure Swift on `String`/`NSString`; no AppKit.

## Files to touch
- `StudyReader/Features/Reader/Text/TextAnchoring.swift` (new)
- `StudyReaderTests/ReaderTests/TextAnchorTests.swift` (new)

## Interfaces to produce
```swift
enum TextAnchoring {
    static let contextLength = 32       // UTF-16 units, widened so no composed character is split
    static let nearbyWindow = 2_000     // ARCHITECTURE §5.3 step 1

    /// text = substring at range; prefix/suffix = up to contextLength UTF-16 units before/after, adjusted outward
    /// to composed-character boundaries (NSString.rangeOfComposedCharacterSequences(for:)).
    static func anchor(for range: NSRange, in text: String, sourceVersion: Int) -> TextAnchor

    enum Resolution: Equatable, Sendable {
        case unchanged                       // same version and the stored range still holds anchor.text
        case moved(TextAnchor)               // found: new start/length, sourceVersion = currentVersion, same text/prefix/suffix
        case orphaned                        // not found anywhere
    }
    static func resolve(_ anchor: TextAnchor, in text: String, currentVersion: Int) -> Resolution

    /// positionKey for text/Markdown highlights (ARCHITECTURE §5.5).
    static func positionKey(for anchor: TextAnchor) -> Double   // Double(anchor.start)
}
```
Resolution algorithm (ARCHITECTURE §5.3, made whitespace-tolerant):
1. If `anchor.sourceVersion == currentVersion` and the range is in bounds and the substring equals `anchor.text` → `.unchanged`. If only the version differs but the substring still equals `anchor.text` → `.moved` with the same start/length and the new version.
2. Normalize for matching: collapse every run of whitespace/newline characters to one space in `text`, `anchor.text`, `prefix` and `suffix`, keeping a map from normalized UTF-16 offsets back to original offsets. Matching is case-sensitive.
3. Find all occurrences of normalized `anchor.text` within ±`nearbyWindow` of the (mapped) old start. If none, search the whole normalized text.
4. Score each occurrence: length of the common suffix of (normalized prefix, normalized text before the match) + length of the common prefix of (normalized suffix, text after the match). Highest score wins; ties → closest to the old start; then the earlier one.
5. Map the winner back to an original `NSRange` (start of first matched char to end of last). Empty `anchor.text` or no occurrence → `.orphaned`.

## Tests (`TextAnchorTests`)
- `anchorCapturesContext`: in `"The quick brown fox jumps over the lazy dog"`, range of "brown fox" → prefix `"The quick "`, suffix `" jumps over the lazy dog"` (shorter than 32 at the ends); a 100-character text gives 32-unit prefix/suffix.
- `composedCharactersNotSplit`: an emoji with skin tone (surrogate pairs + modifier) right at the 32-unit boundary is either fully inside the prefix or fully outside.
- `unchangedWhenSame`: same version, same text → `.unchanged`.
- `reanchorWithPrefixSuffix` (SPEC F-06 AC4): old text `"Intro.\n\nGradient descent minimizes the loss.  It is iterative.\n\nGradient descent minimizes the loss again."`, anchor on the first "Gradient descent minimizes the loss" (prefix "Intro.\n\n"). New text with whitespace normalized differently and 50 characters inserted at the start (`"New preface paragraph… \nIntro. Gradient descent minimizes the loss. It is iterative. Gradient descent minimizes the loss again."`) and a new version → `.moved` whose range in the new text is the first occurrence (the prefix decides), and the substring at the new range equals "Gradient descent minimizes the loss".
- `prefersNearbyOccurrence`: two identical occurrences with no prefix/suffix difference → the one closest to the old start.
- `farMoveUsesWholeText`: the text moved by 5,000 characters → still found.
- `orphanedWhenGone`: text removed → `.orphaned`.
- `multilineSelectionAcrossChangedWhitespace`: anchor text containing `"\n\n"` matches new text where it became a single space; the mapped range covers the new characters exactly.

## Acceptance criteria
1. Text and Markdown highlights re-anchor after restart even if whitespace normalization changed. → test `TextAnchorTests/reanchorWithPrefixSuffix`
2. Anchor creation, tie-breaking, far moves and orphaning behave as specified. → tests `anchorCapturesContext`, `composedCharactersNotSplit`, `unchangedWhenSame`, `prefersNearbyOccurrence`, `farMoveUsesWholeText`, `orphanedWhenGone`, `multilineSelectionAcrossChangedWhitespace`

## Out of scope
- Applying resolutions to the database and drawing (T60).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
