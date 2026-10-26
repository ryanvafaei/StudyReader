# T52d: Highlight-color menu swatches show their colours

- **Phase:** 1 (T52 checkpoint fix; SPEC F-06 current colour, F-08 palette)
- **Agent:** ui-builder
- **Depends on:** T52
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md
- **Visual check needed:** no (covered by UI test; the ui-tester also looks at the attached menu screenshot in light and dark mode during its checkpoint pass)

## Goal
Step 27 of `docs/checkpoints/T52-manual-2026-10-25.md`: in the reader toolbar's highlight-colour menu every swatch is black in light mode and white in dark mode. The menu is an `NSMenu`, which draws the SF Symbol `circle.fill` as a template image and ignores `.foregroundStyle`. The fix is a non-template, coloured `NSImage` per colour.

## Files to touch
- `StudyReader/Features/Annotations/HighlightPalette.swift` (modify: add the swatch image)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify: the menu items' icons only)
- `StudyReaderTests/AppTests/HighlightPaletteTests.swift` (new)

## Interfaces to produce
```swift
// HighlightPalette
/// A filled circle in `nsColor(color)` with a 0.5 pt `NSColor.separatorColor` outline, `diameter` points wide.
/// `isTemplate == false`, so menus draw it in its own colour in light and dark mode.
static func swatchImage(_ color: HighlightColor, diameter: CGFloat = 12) -> NSImage
```
Build it with `NSImage(size:flipped:drawingHandler:)` (`NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))`, fill, then stroke), set `isTemplate = false`, set `accessibilityDescription` to `name(color)`.

## What to do
In `ReaderTabContent.toolbarItems`, the `Label`'s icon for each menu item becomes `Image(nsImage: HighlightPalette.swatchImage(color))`. The toolbar button's own label (the current colour) can stay as it is: it renders correctly in the toolbar.

## Acceptance criteria
1. Unit test `HighlightPaletteTests/swatchImageIsColouredAndNotTemplate`: for every `HighlightColor`, the image has `isTemplate == false` and size 12 × 12; drawing it into a 24 × 24 px `NSBitmapImageRep` (through `NSGraphicsContext(bitmapImageRep:)`) and reading the centre pixel with `colorAt(x: 12, y: 12)?.usingColorSpace(.sRGB)` gives `HighlightPalette.nsColor(color)`'s sRGB components within 0.02.
2. UI test `StudyReaderUITests/ReaderChromeTests/testHighlightColorMenuShowsColouredSwatchesAndKeepsTheChoice` (step 27 of the T52 report) turns green: each swatch has saturation > 0.3, the five labels are listed, the choice sticks.
3. `./scripts/build.sh` succeeds; `./scripts/test.sh StudyReaderTests/HighlightPaletteTests` passes.

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md); ui-tester runs it during review. If the name has shifted, use the test in `ReaderChromeTests.swift` covering step 27.

## Out of scope
Settings > Highlight colors rows (U6), the toolbar button design, palette values.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
