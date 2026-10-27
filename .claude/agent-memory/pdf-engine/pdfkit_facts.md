---
name: pdfkit-facts
description: Empirically verified PDFKit/ImageIO behaviours in this repo (macOS 27) that differ from what specs assume
metadata:
  type: reference
---

- `PDFDocument.write(to:)` on a document unlocked from an encrypted PDF keeps the encryption (copy is still `isLocked`). Passing `[.ownerPasswordOption: "", .userPasswordOption: ""]` gives a copy with `isLocked == false` (but `isEncrypted == true`) that keeps the outline. Building a new `PDFDocument` from copied pages gives a truly unencrypted file but loses outline/metadata.
- `PDFPage.bounds(for:)` ignores `rotation`; swap width/height yourself when `rotation % 180 == 90`. `page.draw(with: .cropBox, to:)` handles rotation and a non-zero crop-box origin in an unflipped bitmap CGContext (scale only).
- Swift Testing `-only-testing:` filters use the Swift type name (`StudyReaderTests/CoverTests`), not the `@Suite("…")` display name; a wrong name runs 0 tests and still prints "TEST SUCCEEDED". Check the log for "Test run with N tests".
- Test PNG pixel reads: draw the CGImage into an RGBA premultipliedLast CGContext; buffer row 0 is the top row.
- `PDFPage.attributedString` fonts are `NSFont`; Helvetica-Bold/Oblique and Menlo map to `.bold`/`.italic`/`.monoSpace` traits exactly per run (verified in T42 tests). `PDFDocument(url:)` is nil for the truncated `damaged()` fixture; `encrypted()` opens with `isLocked == true`.
- ARCHITECTURE §6 header rule taken literally removes digit-varying body lines that sit in a page's first/last 2 lines (e.g. "Body text on page N, line 1."); T42 counts a candidate only if its digit-normalized form occurs once on that page. Tests with short raw pages need distinct text in top/bottom-2 lines.
- T53 (PDFReaderController): in `@MainActor` Swift Testing tests, `RunLoop.run(until:)` does NOT run `DispatchQueue.main` blocks (the test is itself a main-queue block); use `try await Task.sleep` to let layout/notifications happen. A borderless unshown `NSWindow` with `contentView = pdfView` is enough for PDFView layout, `go(to:)`, `currentDestination`, clip-view scroll notifications (found via `documentView?.enclosingScrollView`). `go(to: lastPage)` can't put the last page's top at the view top, so `currentDestination.page` may be the previous page: test with a middle page. Observers: selector-based on an NSObject subclass (Notification isn't Sendable).
- T56: `PDFAnnotation` subclass must declare `required init?(coder:)` (return nil before initializing stored props). `selection.pages`/`selectionsByLine()`/`range(at:on:)` work on `PDFDocument(data:)` in tests without a view; fixture `plainMultiPage` page text "Page N line L: ..." works with `page.selection(for: NSRange)`.
