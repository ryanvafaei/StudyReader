# StudyReader — Product Specification

Version 1.0 · 2026-10-23 · Owner: Ryan Vafaei

Companion documents:
- `docs/ARCHITECTURE.md`: how it is built (modules, data model, anchoring, services)
- `docs/DEPENDENCIES.md`: chosen libraries, reference repos, and why
- `docs/decisions/`: ADRs for each decision referenced here

---

## 1. Product summary

StudyReader is a native macOS app for studying course material. The user:
1. drops lecture PDFs and Markdown notes into a library,
2. reads them and highlights, comments, tags, and snapshots what matters,
3. reviews those highlights later with spaced repetition and active-recall cards,
4. exports highlights to a Google Doc that Gemini Notebook (formerly NotebookLM) uses as an auto-syncing source.

Single user, single Mac, local-first. Nothing leaves the Mac except an explicit Google Docs export.

### 1.1 Goals
- Make reading and annotating course PDFs fast, with highlights that never drift.
- Turn highlights into a daily review habit without extra effort.
- Feed only *the user's own highlights and notes* to Gemini Notebook and Claude, so AI tools work on the parts that matter.

### 1.2 Non-goals
- EPUB, in any form. Do not add EPUB parsing, rendering, types, or extension points.
- iOS, iPadOS, web, Windows, or any sync server.
- Paid or cloud AI APIs. On-device Apple frameworks only.
- Text-to-speech, RSS, newsletters, browser extension, Kindle/Readwise/Pocket import, sharing, multi-user.
- Writing annotations into the user's PDF files. Annotations live in the app database.

### 1.3 Platform
- macOS 27.0 or later, Apple silicon. No code paths for older macOS.
- App Sandbox on. Network access only for Google export.

---

## 2. Glossary

| Term | Meaning |
|---|---|
| Document | An imported PDF or Markdown file plus its metadata |
| PDF view | Page-faithful PDF rendering via PDFKit |
| Text view | Reflowed plain-text rendering of a PDF, using the reader appearance settings |
| Markdown view | Rendered Markdown document; behaves like the text view for selection and highlights |
| Highlight | A saved selection: text highlight (from PDF view, text view, or Markdown) or image highlight (snapshot) |
| Anchor | The stored position of a highlight inside its document (see ARCHITECTURE §5) |
| Highlight note | Free text attached to one highlight |
| Document note | One free-text note for a whole document |
| Category | A document's content type, e.g. Lecture slides; drives review frequency |
| Review card | The spaced-repetition state for one highlight |
| Passive card | Review card that shows the highlight itself |
| Mastery card | Active-recall card made from a highlight: cloze or question/answer |
| Daily review | The default review session: due cards across the whole library |
| Themed review | A user-defined review session over a filtered set of highlights |
| Export target | A saved Google Docs export (scope + Google file ID) |

---

## 3. Feature specifications

Feature IDs (F-xx) are referenced by task specs and tests. Acceptance criteria (AC) must each map to a test or an explicit visual check.

### F-01 Library

**Behavior**
- Main window: `NavigationSplitView` with sidebar (Library, Highlights, Review, Themed Reviews, Tags, Categories) and content area.
- Library shows documents as a grid (default) or list. Each item: cover, title, author, category, highlight count, reading progress (percent), last opened.
- Sort: date added (default, newest first), last opened, title, author.
- Filter: category, tag, file type (PDF/Markdown), "has highlights".
- Context menu per document: Open, Edit Metadata, Reveal Original in Finder (if still present), Export Highlights…, Delete.
- Delete asks for confirmation and removes the document, its stored file copy, highlights, notes, review cards, embeddings, and search index entries.
- Opening a document opens it as a native macOS window tab in the main window (same tab group; the library stays the first tab). Opening a document that is already open switches to its tab. Tabs can be dragged out into their own window, as macOS allows (ADR-0017).

**AC**
1. Library lists all imported documents with the fields above, after restart. → test `LibraryModelTests/listsPersistedDocuments`
2. Each sort and filter option returns the correct order/subset. → tests `LibraryModelTests/sort*`, `LibraryModelTests/filter*`
3. Deleting a document removes all dependent rows and the stored file. → test `DocumentRepositoryTests/deleteCascades`
4. Documents open as tabs after the library tab; reopening an open document selects its tab; a tab can be dragged out. → visual check

### F-02 Import: drag-and-drop and file picker

**Behavior**
- Accept drops of `.pdf`, `.md`, `.markdown` files (one or many) onto the library window and onto the Dock icon. Also File > Import… (⌘O) with a file picker.
- Folders dropped: import supported files inside, recursively, max depth 3.
- On import:
  1. Compute SHA-256 of the file. If a document with the same hash exists, skip it and show "Already in library: <title>".
  2. Copy the file into the app container (`Application Support/StudyReader/Documents/<document-uuid>/original.<ext>`). The app never depends on the original location.
  3. Create the document row with metadata defaults (§F-11).
  4. Generate the cover (PDF: first page render; Markdown: generated title card).
  5. Queue background text extraction and search indexing (F-12). The document is openable immediately; search results appear when indexing finishes.
- Unsupported files in a drop are skipped with a summary: "Imported 3, skipped 2 (unsupported type)".
- Files over 500 MB: ask for confirmation before import.
- Encrypted PDFs: if PDFKit can't unlock without a password, prompt for it once; if it fails, skip with an error.
- Damaged PDFs PDFKit can't open: skip with "Couldn't open <name>".

**AC**
1. Dropping a PDF and an `.md` imports both, copies files into the container, and shows them in the library. → test `ImportServiceTests/importsPDFAndMarkdown`
2. Importing the same file twice keeps one document. → test `ImportServiceTests/deduplicatesByHash`
3. Unsupported and damaged files are reported, not imported. → test `ImportServiceTests/reportsUnsupportedAndDamaged`
4. Drag-and-drop onto the window and the Dock icon both work. → visual check

### F-03 Markdown import and rendering

**Behavior**
- Parse with Apple `swift-markdown` (CommonMark + GFM tables, strikethrough, task lists).
- Render: headings H1–H6, paragraphs, emphasis, strong, inline code, code blocks (monospace, no syntax highlighting required), block quotes, ordered/unordered/task lists, tables, links (open in browser), horizontal rules, images.
- Images: on import, relative image paths that exist next to the source file are copied into the document folder. If the sandbox can't read them (a single `.md` file was imported), the app asks once per import and folder for access to the file's folder (a folder picker preselected on it, "Allow access to this folder so StudyReader can copy the images."); on approval the images are copied and the access isn't kept. If the user cancels, those images become placeholders. Missing images render as a placeholder box with the alt text. Remote image URLs are not fetched (privacy); show the placeholder with the URL.
- The rendered text is selectable and highlightable exactly like the PDF text view (F-05, F-06).
- Front matter (YAML between `---` lines at the top) is hidden from the rendered view; `title` and `author` keys, if present, prefill metadata.

**AC**
1. Every element listed above renders with distinct styling. → visual check with `Tests/Fixtures/markdown/all-elements.md`
2. Relative images are copied at import and shown; missing ones show a placeholder. → test `MarkdownImportTests/copiesRelativeImages`
3. Front matter `title`/`author` prefill metadata and are hidden. → test `MarkdownImportTests/frontMatter`
4. Unreadable sibling images trigger one folder-access request per folder and import batch; approval copies them, cancel leaves placeholders. → tests `MarkdownImportTests/folderAccess*` + visual check

### F-04 Reader, PDF view

**Behavior**
- PDFKit `PDFView` hosted in SwiftUI, in the document's tab (F-01).
- Display: continuous scroll (default) or single page; zoom in/out (⌘+ / ⌘−), actual size (⌘0), fit width.
- Page thumbnails sidebar (toggle), page number field, outline (table of contents) if the PDF has one.
- Dark mode: when the app appearance is dark, rendered pages are color-inverted (hue-preserving) so slides are readable. Setting "Invert PDF colors in dark mode" (default on). Image highlights and snapshots always store the *uninverted* rendering.
- Reading position (page + vertical offset) saved per document and restored on open.

**AC**
1. Opening a document restores the last page and offset. → test `ReadingPositionTests/restoresPosition`
2. Zoom, fit width, display mode work from menu and shortcuts. → visual check
3. Dark mode inversion applies and can be turned off; snapshots stay uninverted. → visual check + test `SnapshotServiceTests/capturesUninverted`

### F-05 Reader, text view and appearance

**Behavior**
- Toggle PDF view ⇄ text view with ⌘⇧T (PDF documents only). Markdown documents always use the Markdown view.
- Text view content comes from PDF text extraction (ARCHITECTURE §6): paragraphs reconstructed, hyphenation at line ends joined, headers/footers repeated on most pages removed, page boundaries shown as subtle "Page N" separators.
- Appearance popover (toolbar "Aa"), applies to text view and Markdown view:
  - Font: Serif (New York) / Sans (SF Pro) / Mono (SF Mono)
  - Font size: 12–28 pt, step 1, default 16
  - Line spacing: 1.2 / 1.4 (default) / 1.6 / 1.8
  - Content width: Narrow 560 pt / Medium 720 pt (default) / Wide 900 pt
  - Theme: System (default) / Light / Dark / Sepia
  - Layout: Continuous scroll (default) / Paged (one screen per page, ← → and Space to turn, page indicator)
- Settings are global, persisted, and apply live.
- Reading position in text view is saved separately (character offset of the first visible line).

**AC**
1. Text view shows reflowed text with joined hyphenation and removed repeated headers/footers. → tests `TextExtractionTests/joinsHyphenation`, `TextExtractionTests/removesRepeatedHeaders`
2. Each appearance setting applies live and persists across restarts. → test `AppearanceSettingsTests/persists` + visual check
3. Paged layout turns pages with ←, →, Space and shows a page indicator. → visual check

### F-06 Highlights

**Behavior**
- Colors: Yellow (default), Green, Blue, Pink, Purple. Each color has an editable label in Settings (defaults: Key concept, Exam, Connection, Question, Don't understand).
- Creating: select text in PDF view, text view, or Markdown view.
  - Auto-highlight on (default): releasing the mouse after a selection creates a highlight in the current color immediately. Pressing ⌘Z right after removes it.
  - Auto-highlight off: a floating toolbar appears over the selection: 5 color dots, Note, Tag, Copy.
  - Keyboard: with a selection, press 1–5 to highlight in that color, H for the current color.
- Selections across lines and columns become one highlight with multiple rectangles. Selections across pages in PDF view become one highlight spanning pages.
- Clicking an existing highlight opens its popover: color, note, tags, Mastery…, Similar, Copy, Delete.
- Overlapping highlights are allowed; the most recent one is drawn on top and clicking selects the topmost.
- Highlights made in PDF view appear only in PDF view; highlights made in text view appear only in text view (same as Readwise Reader). Both appear in the document's highlights panel, labelled "PDF" or "Text".
- Document highlights panel (right sidebar, toggle ⌘⌥H): list of the document's highlights in reading order with color, text excerpt, note, tags; click scrolls to it.
- Rich text: highlights keep bold, italic, inline code, and links from the source (F-07).
- Every highlight stores: document, view type, anchor, plain text, rich text, color, note, tags, created/updated dates, page number (PDF view and PDF text view).

**AC**
1. Selecting text with auto-highlight on creates a highlight in the current color; ⌘Z removes it. → test `HighlightServiceTests/autoHighlightUndo` + visual check
2. Multi-line and cross-page selections produce one highlight with the right rectangles per page. → test `PDFAnchorTests/multiLineAndCrossPage`
3. Highlights redraw in exactly the same place after zoom, window resize, and app restart. → test `PDFAnchorTests/roundTrip` + visual check
4. Text-view and Markdown highlights re-anchor after restart even if whitespace normalization changed. → test `TextAnchorTests/reanchorWithPrefixSuffix`
5. Popover actions (color, note, tags, delete) persist immediately. → test `HighlightRepositoryTests/updates`

### F-07 Rich-text highlighting

**Behavior**
- Highlight rich text is stored as a Markdown subset: `**bold**`, `*italic*`, `` `code` ``, `[text](url)`. No other formatting.
- Markdown documents: derived from the swift-markdown AST nodes inside the selected range.
- PDF view / text view: derived from the attributed string of the selection; font traits map bold/italic, monospaced fonts map to code, link annotations map to links.
- Shown rendered (not raw Markdown) everywhere highlights are listed and in review.

**AC**
1. Selecting "a **bold** and *italic* word with `code`" in a Markdown doc stores exactly that Markdown. → test `RichTextTests/markdownSelection`
2. PDF selection with bold/italic fonts produces the matching Markdown. → test `RichTextTests/pdfAttributedSelection` (fixture PDF generated in test)

### F-08 Image highlights (snapshot)

**Behavior**
- Snapshot tool: toolbar button (camera icon) or ⌃⌘S, PDF view only. The cursor becomes a crosshair; drag a rectangle on a page; release saves it.
- Saved as PNG rendered from the PDF page at 2× scale, uninverted, plus page index and rectangle in page coordinates.
- An image highlight has color, note, and tags like a text highlight, and shows a thumbnail in lists and the full image in review.
- Rectangles outside the page are clipped to the page; rectangles smaller than 10×10 pt are ignored.

**AC**
1. Dragging a rectangle saves a PNG of exactly that region at 2× scale. → test `SnapshotServiceTests/rendersRegion`
2. Image highlights show in the document panel, highlights browser, and review. → visual check

### F-09 Notes

**Behavior**
- Highlight note: plain text with Markdown rendering (same subset as F-07 plus line breaks and lists), edited in the highlight popover and in the highlights browser. Autosaves 500 ms after typing stops.
- Document note: one note per document, edited in a "Notes" tab of the right sidebar. Same format and autosave.
- Both are full-text searchable and included in exports.

**AC**
1. Notes autosave and survive restart. → test `NotesRepositoryTests/autosaveAndRestore`
2. Notes appear in search results and exports. → tests `SearchServiceTests/findsNotes`, `ExportRendererTests/includesNotes`

### F-10 Tags

**Behavior**
- Tags apply to highlights and to documents. Tag names: 1–40 chars, case-insensitive unique, stored as typed.
- Add via tag field with autocomplete; typing a new name creates it. In a highlight note, `#tagname` also adds the tag.
- Tag manager (sidebar "Tags"): list with counts; rename, merge (move all uses into another tag), delete (removes from items, keeps items).
- Filtering by tag in library, highlights browser, search, themed reviews, and export scopes.

**AC**
1. Tags are case-insensitively unique; renaming and merging update every use. → tests `TagRepositoryTests/uniqueness`, `TagRepositoryTests/renameMerge`
2. `#tag` in a highlight note adds the tag. → test `TagParsingTests/hashTags`

### F-11 Document metadata

**Behavior**
- Editable fields: Title, Author, Cover image, Category.
- Defaults at import: Title from PDF metadata title (if non-empty and not a file-name-like string) else file name without extension; Author from PDF metadata or Markdown front matter, else empty; Category = default category (Lecture slides) unless changed in Settings; Cover = first-page render (PDF) or generated card (Markdown).
- Cover: choose an image file, use the current page as cover, or reset to default.
- Categories: built-ins Lecture slides, Paper, Book chapter, Notes, Other. User can add, rename, and delete custom categories; deleting reassigns documents to Other.
- Edit Metadata sheet: ⇧⌘M or context menu.

**AC**
1. Defaults are applied at import as described. → test `MetadataDefaultsTests/*`
2. Edits persist and update library, search, and exports. → test `DocumentRepositoryTests/metadataUpdate`

### F-12 Full-text search

**Behavior**
- Global search field (⌘F in library, ⌘⇧F anywhere). In-document find (⌘F while reading) searches only the open document and steps through matches.
- Indexed: document text (per page for PDFs, per section for Markdown), highlight text, highlight notes, document notes, titles, authors.
- Results grouped: Documents (with page and snippet), Highlights, Notes. Snippets show the match in bold. Ranked by FTS5 bm25.
- Query syntax: words (AND), `"exact phrase"`, prefix `word*`, and `-word` to exclude. Filters: tag, category, document type.
- Clicking a result opens the document at the location (page, highlight, or note).
- Target: results in under 200 ms for a library of 500 documents / 20,000 pages on an M-series Mac.

**AC**
1. Each indexed field is searchable and returns the right location. → tests `SearchServiceTests/*`
2. Phrase, prefix, and exclusion queries work. → test `SearchQueryParserTests/*`
3. Index stays in sync on create/update/delete of documents, highlights, and notes. → test `SearchIndexSyncTests/*`

### F-13 Highlights browser

**Behavior**
- Sidebar "Highlights": every highlight across the library in a list.
- Columns/cards: color, rich text (or thumbnail), note, tags, document title, page, created date.
- Filters: document, category, tag (any/all), color, has note, view type, date range, Mastery status.
- Sort: created (default newest first), document then position, color.
- Multi-select: add/remove tags, change color, delete, export selection.
- Detail pane: full highlight, editable note and tags, "Open in document", Similar highlights (F-14), Mastery (F-16).

**AC**
1. Every filter and sort works and combines. → tests `HighlightsBrowserModelTests/*`
2. Bulk actions apply to all selected highlights. → test `HighlightsBrowserModelTests/bulkActions`

### F-14 Find Similar Highlights

**Behavior**
- In the highlight popover and browser detail: "Similar" shows the top 5 highlights from other documents (and other places in the same document) by semantic similarity, with similarity score hidden.
- Computed on-device with Apple NaturalLanguage sentence embeddings (ADR-0008). Embeddings are computed in the background on create/edit and stored.
- Minimum similarity threshold (cosine ≥ 0.55, tunable constant) so unrelated items aren't shown; empty state says "No similar highlights yet".
- Image highlights: use their note text if present; otherwise excluded.

**AC**
1. Similar results are ordered by cosine similarity and exclude the highlight itself. → test `SimilarityServiceTests/ordersAndExcludesSelf`
2. Embeddings update when highlight text or note changes. → test `EmbeddingSyncTests/recomputesOnEdit`

### F-15 Spaced-repetition review (daily review)

**Behavior**
- Algorithm: FSRS-6 via `open-spaced-repetition/swift-fsrs` (ADR-0006). Long-term scheduler only (no intra-day learning steps): `enableShortTerm = false`, `enableFuzz = true`.
- Every highlight gets a passive review card when created, if its category's frequency isn't Off. New cards enter the review queue at most *N new per day* (default 5).
- Daily review session (sidebar "Review", badge shows the count due):
  1. Due cards (`due ≤ now`), most overdue first, up to the daily limit (default 15).
  2. Then new cards up to the new-per-day limit, oldest highlight first.
- Card front: the highlight (rich text or image), document title, page, and color label. Reveal shows the note and tags. Passive cards are self-rated without a hidden answer (show everything at once); Mastery cards hide the answer until revealed (F-16).
- Rating:
  - Default two buttons: **Forgot** (FSRS `again`, key 1) and **Remembered** (FSRS `good`, key 2).
  - Setting "Show four rating buttons": Again/Hard/Good/Easy (keys 1–4).
- Review actions on each card (F-18).
- Session ends with a summary: reviewed count, remembered %, next due count tomorrow.
- Daily review count resets at 04:00 local time.
- Optional reminder notification at a chosen time (default off).

**AC**
1. Ratings update the card with the FSRS-6 result and log the review. → tests `ReviewSchedulerTests/*` (table-driven, injected clock)
2. Session composition respects due-first, limits, and new-per-day. → test `DailyReviewBuilderTests/*`
3. A full session works end to end and persists across restart. → visual check

### F-16 Mastery (active recall cards)

**Behavior**
- From a highlight: "Mastery…" opens an editor to create one or more active-recall cards:
  - **Cloze**: select words in the highlight text to hide; each cloze group becomes one card. Front shows the text with `[…]`; back shows the full text.
  - **Question & answer**: user writes a question; the answer defaults to the highlight text and is editable.
- **Suggest with Apple Intelligence** button (shown only when the on-device model is available, ADR-0010): proposes one cloze and one Q&A from the highlight and its note via the Foundation Models framework with guided generation. The user edits and accepts or discards; nothing is created automatically.
- Once a highlight has Mastery cards, its passive card is suspended; the Mastery cards take its place in review with their own FSRS state.
- Mastery status shown in browser and popover (badge "Mastery").

**AC**
1. Cloze and Q&A cards are created, reviewed with hidden answers, and scheduled independently. → tests `MasteryServiceTests/*`
2. Creating Mastery cards suspends the passive card; deleting them all restores it. → test `MasteryServiceTests/suspendsPassive`
3. Suggest is hidden when the model is unavailable and never creates cards without confirmation. → test `MasterySuggestionTests/availabilityGate`

### F-17 Flashcards from highlights

Definition for this app: every highlight becomes a flashcard automatically as a passive card (F-15). Mastery cards (F-16) are the "real" flashcards with hidden answers.

**Behavior**
- Setting per category: "Create review cards for new highlights automatically" (default on for all built-in categories).
- "Flashcards" view inside Review: browse all cards (passive and Mastery) with filters (document, tag, category, state New/Learning/Review/Suspended, due date), preview, and edit Mastery cards.
- Bulk action from the highlights browser: "Create review cards" for selected highlights that have none.

**AC**
1. New highlights get a passive card only when their category allows it. → test `CardCreationTests/respectsCategorySetting`
2. Flashcards view filters and edits cards. → test `FlashcardsModelTests/*`

### F-18 Review actions

**Behavior** (available on every card during review and in the flashcards view)
- **Forgot / Remembered** (or four buttons, F-15).
- **Add/edit note**: edits the highlight note inline.
- **Edit highlight**: edit the displayed text of the highlight (stored as `edited_text`; the original anchored text is kept for re-anchoring and shown on "Show original").
- **Change frequency** for this card: Off (suspend), Low, Normal, High → overrides the category's desired retention (F-19).
- **Open in document**.
- **Skip** (moves the card to the end of the session without rating).
- Actions persist immediately; frequency changes reschedule from the last review.

**AC**
1. Each action persists and affects the next scheduled date as specified. → tests `ReviewActionsTests/*`

### F-19 Review frequency per content type

**Behavior**
- Each category has a frequency: Off, Low, Normal, High. Defaults: Lecture slides = High, Paper = Normal, Book chapter = Normal, Notes = Low, Other = Normal.
- Frequency maps to FSRS desired retention (`requestRetention`): Low 0.80, Normal 0.90, High 0.95. Off = no new cards and existing cards suspended.
- Precedence: card override (F-18) > category frequency.
- Changing a category's frequency applies to future scheduling of its cards (next rating), and Off/on suspends/unsuspends immediately.

**AC**
1. Retention mapping and precedence are applied when scheduling. → test `FrequencyPolicyTests/*`
2. Setting a category to Off suspends its cards; setting it back unsuspends. → test `FrequencyPolicyTests/offSuspends`

### F-20 Themed reviews

**Behavior**
- User creates named themed reviews (sidebar "Themed Reviews"): e.g. "ML1 exam week".
- Definition: filter (tags any/all, documents, categories, colors), cards per session (5–100, default 20), interval (every day / every N days / specific weekdays), and order (due first then least recently reviewed (default), or random).
- A themed review is "due" when its interval has elapsed since its last completed session; due themed reviews show a badge.
- Running a themed review rates the same cards as daily review (one FSRS state per card); it just selects a different set. Cards rated in a themed session aren't shown again in daily review the same day.
- Edit, duplicate, delete themed reviews.

**AC**
1. Selection matches the filter, volume, and order rules. → tests `ThemedReviewBuilderTests/*`
2. Due logic follows the interval definition. → test `ThemedReviewScheduleTests/*`

### F-21 Export to Google Docs (Gemini Notebook source)

**Behavior**
- Settings > Google: Sign in with Google (GoogleSignIn, ADR-0007) / Sign out. Shows the signed-in email. Scope: `https://www.googleapis.com/auth/drive.file` only.
- Export scopes: one document, one tag, one category, a themed review's filter, or All highlights.
- Export options: include highlight notes (default on), include document notes (default on), include image highlights as a text placeholder "[Image highlight, page N]" with note (default on), group by document (default) or by tag.
- Output: a Markdown file uploaded to Google Drive with conversion to a Google Doc (Drive API import, Markdown → Docs). Format in ARCHITECTURE §9.
- Doc title: `StudyReader – <scope name>`. Created in the user's My Drive root, or a folder chosen once in Settings (by pasting a folder link; stored as folder ID).
- The first export creates the Doc and saves an export target (scope, options, Google file ID). Re-exporting replaces the Doc's full content (Drive `files.update` with media upload), keeping the same file ID, so the Gemini Notebook Drive source stays linked and auto-syncs.
- Per target "Keep in sync" toggle (default off): when on, re-export runs automatically 60 s after the last relevant change while the app is open.
- Export targets list in Settings > Google: last exported time, status, "Open in Google Docs", "Export now", "Remove" (removes the target only, never deletes the Doc).
- Errors: offline (queue and retry when online), expired session (refresh silently, else ask to sign in), Doc deleted or access revoked (offer to create a new Doc), rate limit (retry with backoff, max 3).

**AC**
1. Export renderer produces the exact Markdown format for each scope and option. → tests `ExportRendererTests/*` (golden files)
2. First export creates a Doc and stores its ID; re-export updates the same ID. → test `GoogleExportServiceTests/createThenUpdate` (mocked network)
3. Error cases behave as specified. → tests `GoogleExportServiceTests/errors*`
4. Real export appears in Google Docs and can be added to Gemini Notebook. → visual check (manual, needs Google setup)

### F-22 Settings

Settings window (⌘,), tabs:
- **General**: default category for imports, auto-highlight on/off, highlight color labels.
- **Reading**: appearance defaults (F-05), invert PDF in dark mode.
- **Review**: daily limit, new per day, four rating buttons, reminder time, category frequencies (F-19), per-category auto-create cards (F-17).
- **Google**: account, export folder, export targets (F-21).
- **Data**: library location (read-only path + Reveal), "Rebuild search index", "Recompute embeddings".

---

## 4. Non-functional requirements

| Area | Requirement |
|---|---|
| Performance | Open a 200-page PDF and show page 1 in < 1 s. Highlight creation feels instant (< 50 ms to draw). Search < 200 ms at 500 docs. Import never blocks the UI; extraction/indexing/embedding run in background tasks with progress in the library item. |
| Reliability | SQLite in WAL mode; all multi-row changes in transactions. Crash during import leaves no half-imported document (cleanup on next launch). |
| Privacy | No analytics, no network calls except Google export after explicit sign-in. Tokens only in Keychain. Remote Markdown images never fetched. |
| Accessibility | All controls have labels; full keyboard use for reading, highlighting (1–5/H), and review (1–4, Space to reveal); respects Reduce Motion and Increase Contrast. |
| Localization | English UI only; strings in a String Catalog so translation is possible later. English content only. Other scripts are not supported or tested. |
| Data location | `~/Library/Containers/<bundle-id>/Data/Library/Application Support/StudyReader/` (database `StudyReader.sqlite`, `Documents/`). |
| Security | App Sandbox: user-selected read-only files, network client, keychain sharing group required by GoogleSignIn. No hardened-runtime exceptions. |

---

## 5. Keyboard shortcuts (summary)

| Action | Shortcut |
|---|---|
| Import | ⌘O |
| Global search | ⌘⇧F |
| Find in document | ⌘F (reader) |
| Toggle PDF/Text view | ⌘⇧T |
| Highlights panel | ⌘⌥H |
| Highlight in color 1–5 / current | 1–5 / H (with selection) |
| Snapshot tool | ⌃⌘S |
| Edit metadata | ⇧⌘M |
| Zoom in / out / actual / fit width | ⌘+ / ⌘− / ⌘0 / ⌘9 |
| Review: reveal / rate | Space / 1–2 (or 1–4) |
| Settings | ⌘, |

---

## 6. Build phases

Each phase ends with all its AC passing, bug-hunter run, and critical/high bugs fixed. The architect turns each epic into task specs (`docs/tasks/phase-N/`).

### Phase 0 — Bootstrap
| Epic | Content | Agent |
|---|---|---|
| E0.1 Project | XcodeGen `project.yml`, app + test targets, SPM dependencies from DEPENDENCIES.md, entitlements, Info.plist, String Catalog, empty app shell that launches | ui-builder |
| E0.2 Database | GRDB setup, migration v1 with full schema (ARCHITECTURE §4), repositories skeleton, test helpers (in-memory DB) | data-layer |
| E0.3 Fixtures | Test fixture builders: generated PDFs (multi-page, multi-column, bold/italic, repeated header/footer), Markdown fixtures | data-layer |

### Phase 1 — Study loop
| Epic | Features | Agent(s) |
|---|---|---|
| E1.1 Import + library | F-01, F-02, F-11 | data-layer, ui-builder |
| E1.2 PDF reader | F-04 | pdf-engine |
| E1.3 Markdown reader | F-03 (rendering engine) + reader chrome | pdf-engine (text engine), ui-builder (chrome) |
| E1.4 Highlights (PDF + Markdown) | F-06 (except text view), F-07 for Markdown, F-08 | pdf-engine, data-layer, ui-builder |
| E1.5 Notes + tags | F-09, F-10 | data-layer, ui-builder |
| E1.6 Search | F-12 | data-layer, ui-builder |
| E1.7 Highlights browser | F-13 (without Similar/Mastery) | ui-builder |
| E1.8 Google export | F-21 | integrations, ui-builder |

E1.8 signing note (ADR-0011, amended 2026-10-24): the user already set `DEVELOPMENT_TEAM: 597KGSTZWJ` and `keychain-access-groups` and configured Google credentials. E1.8 doesn't change signing; its sign-in task verifies that a Google sign-in survives an app restart.

Done when: import a lecture PDF, highlight it, add notes/tags, search it, export highlights to a Google Doc, and add that Doc to Gemini Notebook.

### Phase 2 — Review
| Epic | Features | Agent(s) |
|---|---|---|
| E2.1 Scheduler | FSRS wrapper, frequency policy (F-19), card creation (F-17) | review-engine |
| E2.2 Daily review | F-15, F-18 | review-engine, ui-builder |
| E2.3 Mastery | F-16 (manual cloze/Q&A) | review-engine, ui-builder |
| E2.4 Themed reviews | F-20 | review-engine, ui-builder |
| E2.5 Flashcards view | F-17 view | ui-builder |

Done when: a daily review and a themed review run end to end with persisted FSRS scheduling.

### Phase 3 — Extras
| Epic | Features | Agent(s) |
|---|---|---|
| E3.1 PDF text view | F-05 text view, text-view highlights, F-07 for PDF | pdf-engine |
| E3.2 Appearance | F-05 appearance + paged layout | ui-builder, pdf-engine |
| E3.3 Similar highlights | F-14 | integrations, ui-builder |
| E3.4 Mastery suggestions | F-16 Apple Intelligence suggest | integrations |
| E3.5 Settings + polish | F-22 complete, keyboard shortcuts, accessibility pass | ui-builder |

Done when: every AC in this spec passes.

---

## 7. Known risks and mitigations

| Risk | Mitigation |
|---|---|
| PDF text view quality on slides, math, tables, multi-column | Heuristic extraction (ARCHITECTURE §6); accept imperfect output; Vision document recognition as a later optional improvement, not a blocker |
| Highlight positions drift in PDF view | Store quads in page space; round-trip tests; visual checks with screenshots for every PDF-view task |
| Haiku agents produce wrong code in tricky areas | PDF/text engines and integrations run on Sonnet; escalation rule in CLAUDE.md |
| Google OAuth setup | Manual steps documented in DEPENDENCIES.md §4; export code fully testable with mocked network |
| Apple Intelligence unavailable | Mastery suggestion hidden; every other feature works without it |
| Young reference repos may contain bugs | They're references only, never dependencies; copied code must be reviewed and tested like our own |
