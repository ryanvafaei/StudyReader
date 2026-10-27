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
