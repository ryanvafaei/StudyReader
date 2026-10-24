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
