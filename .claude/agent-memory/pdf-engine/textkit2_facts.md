---
name: textkit2-facts
description: Verified TextKit 2 / NSTextView facts from T55 (CI macOS 27)
metadata:
  type: reference
---

- NSTextView subclass with TK2: build `NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer`, set `layoutManager.textContainer`, then `super.init(frame:textContainer:)`; keep the storage/manager as stored properties. Never touch `textView.layoutManager` (downgrades to TK1).
- `NSTextLayoutManagerDelegate` conformance on a `@MainActor` class fails with `#ConformanceIsolation`; use `@preconcurrency NSTextLayoutManagerDelegate`.
- In `@MainActor` tests use `Task.sleep` to let layout settle. A borderless unshown NSWindow with `contentView = scrollView` lays out; `textLayoutFragment(for: point)`, `ensureLayout(for:)`, `enumerateTextSegments` all work there.
- Scroll tests: the last line of a short document can't reach the top (clamped); concatenate the rendered string 3x. Saved text offsets are rendered-string offsets, not Markdown source offsets (test bug in T55).
- Test log values: put them in the `#expect` comment string; failures otherwise omit them (grep `build/ci/<run>/test.log`).

## T60 (highlight drawing/interaction)
- Highlights drawn with `NSTextLayoutManager.addRenderingAttribute(.backgroundColor,...)`; remove by re-walking the ranges drawn last time (don't clear the whole document: other users of rendering attributes). Verified in tests with `enumerateRenderingAttributes(from:reverse:using:)`.
- `textView.undoManager` is non-nil for the (allowsUndo == false) reader view in a borderless test window; `undo()` works outside a run-loop group.
- Swift Testing `-only-testing` filters use the struct name (`TextHighlightControllerTests`), not the `@Suite` display name; a wrong name runs 0 tests and still prints TEST SUCCEEDED. Check for "Test run with N tests" in the log.
- Re-anchoring writes reach `model.highlights` only through the DB observation: wait until `model.highlights == fetchForDocument` before drawing/revealing (see MarkdownReaderCoordinator.waitForReanchoredRows).
