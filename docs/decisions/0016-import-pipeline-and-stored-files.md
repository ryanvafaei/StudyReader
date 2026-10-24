# ADR-0016: Import pipeline and stored files

- Status: Accepted, except the encrypted-PDF bullet, which is proposed until the user confirms it (Phase 1 open question Q1)
- Date: 2026-10-24 (Phase 1 planning)

## Context
SPEC F-02, F-03 and F-11 describe what import does, but not the order of steps, how a crash is cleaned up, how stored files are named, what happens to password-protected PDFs, or how Markdown images are found again at render time. The app is sandboxed with user-selected read-only access.

## Decision
- **Order per file:** classify by extension → large-file confirmation → SHA-256 → duplicate lookup by `fileHash` → open check (PDF: open, unlock, metadata; Markdown: read UTF-8, front matter) → create `Documents/<id>/`, copy the original, copy Markdown images → insert the `document` row → cover → enqueue extraction. Any failure after the folder exists deletes the folder. A crash can leave only a folder without a row; `LibraryMaintenance` removes such folders at launch, before the library window appears and before any import can start.
- **Stored original:** `Documents/<id>/original.<FileType.storedFileExtension>` (`pdf` or `md`), never the source's `pathExtension` (backlog L4). `storedPath` comes from `FileStore.relativePath(for:)`.
- **Encrypted PDFs (proposed):** prompt for the password once. If it unlocks the file, store a decrypted copy written by PDFKit (`PDFDocument.write(to:)` on the unlocked document) as `original.pdf`. The user's file is never modified. `fileHash` is the hash of the user's original bytes, so re-importing the same file is still a duplicate.
- **Markdown images:** only relative sources (no URL scheme, not starting with `/`) are resolved against the source file's folder (percent-decoded). Each is copied to `Documents/<id>/images/<name>`, where `name` = the first 16 lowercase hex characters of SHA-256 of the source string exactly as written in the Markdown, plus `.` and its lowercased extension (`MarkdownImageNaming`). The renderer computes the same name. Remote images are never fetched. In the sandbox, a single dropped `.md` file doesn't grant access to its folder; unreadable images count as missing, render as placeholders, and the import summary says so.
- **Covers:** PDFs get `cover.png` (first page, longest side 600 px) at import; `coverPath = "<id>/cover.png"`, `coverSource = default`. Markdown documents keep `coverPath = NULL` and the library draws a generated title card. A custom image or "current page" is converted to the same `cover.png` with `coverSource` `custom` or `page`. Reset re-renders page 1 (PDF) or deletes `cover.png` (Markdown).
- **Extraction** runs in `ExtractionService` (actor, one document at a time). Import enqueues through the `ExtractionQueue` protocol. At launch, documents with status `pending`, or `done` with an older extraction version, are enqueued again.

## Alternatives considered
- Keep encrypted PDFs encrypted and ask on every open (background extraction can't unlock), or store the password in the Keychain (needs team signing before E1.8).
- A manifest file or column mapping Markdown image paths: needs a schema change or another file format.
- Render Markdown covers to PNG: extra files that go stale when the title changes.

## Consequences
- Phase 1 needs no schema change. Import is crash-safe without temporary staging folders.
- Single-file Markdown imports in the sandbox lose sibling images; importing the folder keeps them.
