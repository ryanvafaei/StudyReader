# T54: PDF dark-mode inversion

- **Phase:** 1 (E1.2: F-04 dark mode)
- **Agent:** pdf-engine
- **Depends on:** T53
- **ADRs:** docs/decisions/0015-settings-and-injected-sleep.md (`AppSettings.invertPDFInDarkMode`)
- **Visual check needed:** yes

## Goal
When the app's effective appearance is dark and "Invert PDF colors in dark mode" is on (default), show PDF pages color-inverted with hues preserved, so white slides become dark without turning red into cyan. The setting applies live. Snapshots and covers are never affected (they render from `PDFPage`, not from the screen).

## Files to touch
- `StudyReader/Features/Reader/PDF/PDFInversion.swift` (new)
- `StudyReader/Features/Reader/PDF/PDFReaderController.swift` (modify)
- `StudyReader/Features/Reader/PDF/PDFReaderView.swift` (modify: pass settings, observe appearance)
- `StudyReaderTests/ReaderTests/PDFInversionTests.swift` (new)

## Interfaces to produce
```swift
enum PDFInversion {
    /// true when the appearance best-matches .darkAqua and the setting is on.
    static func shouldInvert(appearance: NSAppearance, settingEnabled: Bool) -> Bool
    /// CIColorInvert followed by CIHueAdjust (angle .pi): inverts lightness, keeps hue.
    static func filters() -> [CIFilter]
}
extension PDFReaderController {
    /// Applies or removes the filters on the PDF view's document view layer
    /// (wantsLayer = true, layerUsesCoreImageFilters = true, layer.filters = PDFInversion.filters() or nil).
    func setInverted(_ inverted: Bool)
}
```
- Re-evaluate on `viewDidChangeEffectiveAppearance` of `StudyPDFView` and whenever `settings.invertPDFInDarkMode` changes (SwiftUI `.onChange` in `PDFReaderView` calls `setInverted`).
- If layer filters turn out not to apply to the PDF view's tiles on macOS 27, fall back to `PDFView.pageOverlayViewProvider` or a `PDFPage` subclass drawing through a `CIFilter`; explain the choice in your report. Thumbnails may stay uninverted.
- Highlight annotations are drawn inside the page and get inverted with it; that is accepted (they stay visible as darker tints).

## Tests (`PDFInversionTests`)
- `decision`: dark appearance + on → true; dark + off → false; light (`.aqua`) + on → false.
- `hueIsPreserved`: apply `filters()` to a 1 × 1 `CIImage` of pure red (1, 0, 0) and of white with a `CIContext`; red stays red-dominant (R > G and R > B) and darkens or stays saturated; white becomes black (all channels < 0.05).

## Acceptance criteria
1. The inversion decision and filter math are correct. → tests `PDFInversionTests/decision`, `hueIsPreserved`
2. Visual check (user), SPEC F-04 AC3: switch macOS to Dark appearance; an open lecture PDF shows dark pages with light text and red stays red; turn off "Invert PDF colors in dark mode" in Settings > Reading → pages turn white at once; in Light appearance pages are never inverted.
3. Visual check: after T61, take a snapshot in dark mode; its thumbnail shows the original (white-background) colors. (Recorded at T61's check.)

## Out of scope
- Inverting thumbnails, covers or snapshots.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-27, implementer pdf-engine Sonnet high (no reworks), reviewer code-reviewer Sonnet medium: APPROVED (conditional on the full unit run). Layer-filter inversion (colorInvert + hueAdjust π) on the document view, reapplied on document, display mode and appearance changes; PDFInversionTests pass on CI. Look is Mac-only; fallback if filters don't show: pageOverlayViewProvider or a PDFPage subclass.
