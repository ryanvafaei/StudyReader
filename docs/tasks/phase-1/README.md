# Phase 1 — Study loop

Epics (SPEC §6): E1.1 Import + library (F-01, F-02, F-11), E1.2 PDF reader (F-04), E1.3 Markdown reader (F-03), E1.4 Highlights (F-06 without the PDF text view, F-07 for Markdown, F-08), E1.5 Notes + tags (F-09, F-10), E1.6 Search (F-12), E1.7 Highlights browser (F-13 without Similar/Mastery), E1.8 Google export (F-21).

Done when (SPEC §6): import a lecture PDF, highlight it, add notes/tags, search it, export highlights to a Google Doc, and add that Doc to Gemini Notebook.

New ADRs: [0015 settings and injected sleep](../../decisions/0015-settings-and-injected-sleep.md), [0016 import pipeline and stored files](../../decisions/0016-import-pipeline-and-stored-files.md), [0017 reader windows and commands](../../decisions/0017-reader-windows-and-commands.md), [0018 Google export seams, statuses and signing](../../decisions/0018-google-export-seams-and-status.md). Amended: ADR-0011 (fourth test-host signal for Xcode Previews, T31; signing already set up by the user), ARCHITECTURE §6 rule 5 (soft hyphen at line end, backlog L3) and §9.1 (image placeholder text follows SPEC F-21).

## No schema change in Phase 1 (no `v3`)
The registered migrations are `v1` and `v2` (`AppDatabase.migrator`, `SchemaSnapshotTests/registeredMigrationsInOrder`), so the next one would be `v3`. Every Phase 1 feature fits the v2 schema: settings live in `UserDefaults` (ADR-0015), Markdown image names are derived (ADR-0016), export statuses are free-text values (ADR-0018), counts and tags are queried. So no task adds `v3`. If an implementer finds a real need for a schema change, they report BLOCKED; the architect then plans one dedicated `v3` task (golden `Fixtures/schema/v3.sql`, upgrade test from `V1FixtureDatabase`, `registeredMigrationsInOrder` extended).

Backlog L5 and L6 were meant to ship with the first `v3`. They ship now as T32, without a migration: the "refuse newer library" check only helps if it's already in the older build, so it must land before any `v3` exists (open question Q4).

## Task order

Run in this order, one at a time (CLAUDE.md workflow). "Agent" shows a per-call model/effort override where the spec sets one.

| # | Task | Agent | Depends on | Visual check |
|---|---|---|---|---|
| 1 | [T29 FileStore stores lowercase extensions, only resolvable relative paths](T29-filestore-stored-extensions.md) (backlog L4) | data-layer | none | no |
| 2 | [T30 Rename the ADR-0014 file to an English-only name](T30-rename-adr-0014-file.md) | orchestrator (needs `git mv`; fallback data-layer) | none | no |
| 3 | [T31 Guard Xcode Previews; confirm a normal launch opens the real library](T31-preview-guard-and-launch-check.md) (backlog T27-F1) | ui-builder | none | yes |
| 4 | [T32 Refuse newer libraries; disk-full and busy messages](T32-newer-library-and-error-mapping.md) (backlog L5, L6) | data-layer | none | no |
| 5 | [T33 Core support: Hashing, Sleeper, Debouncer, SettingsStore](T33-core-support-hashing-sleep-settings.md) | data-layer | T29 | no |
| 6 | [T34 Document and category repositories](T34-document-and-category-repositories.md) | data-layer | T29, T33 | no |
| 7 | [T35 HighlightRepository](T35-highlight-repository.md) | data-layer | T34 | no |
| 8 | [T36 TagRepository](T36-tag-repository.md) | data-layer | T34 | no |
| 9 | [T37 Document notes, #tag parsing, note autosave model](T37-notes-and-tag-parsing.md) | data-layer | T33, T35, T36 | no |
| 10 | [T38 HighlightService](T38-highlight-service.md) | data-layer | T35, T36, T37 | no |
| 11 | [T39 PDF import inspection, covers, CoverService](T39-pdf-inspection-and-covers.md) | pdf-engine | T34 | no |
| 12 | [T40 Import helpers: metadata defaults, front matter, Markdown images](T40-import-metadata-and-markdown-helpers.md) | data-layer | T29 | no |
| 13 | [T41 ImportService](T41-import-service.md) | data-layer (model sonnet, effort high) | T33, T34, T39, T40 | no |
| 14 | [T42 PDFTextExtractor](T42-pdf-text-extractor.md) (backlog L3) | pdf-engine | none | no |
| 15 | [T43 MarkdownRenderer](T43-markdown-renderer.md) | pdf-engine | T40 | no |
| 16 | [T44 ExtractionService, DocumentTextRepository, launch maintenance](T44-extraction-service-and-launch-maintenance.md) | data-layer | T41, T42, T43 | no |
| 17 | [T45 AppSession, AppSettings, palette, Settings window](T45-app-session-and-settings-window.md) | ui-builder | T33, T34 | yes |
| 18 | [T46 LibraryModel](T46-library-model.md) | ui-builder | T33, T34, T44 | no |
| 19 | [T47 Library view](T47-library-view.md) | ui-builder | T44, T45, T46 | yes (empty state now; full check with T48) |
| 20 | [T48 Import UI](T48-import-ui.md) | ui-builder | T44, T47 | yes |
| 21 | [T49 Tag field and tag manager](T49-tag-field-and-tag-manager.md) | ui-builder | T36, T45 | yes (empty state now; full check with T50) |
| 22 | [T50 Metadata sheet and category manager](T50-metadata-sheet-and-category-manager.md) | ui-builder | T39, T47, T49 | yes |
| 23 | [T51 ReaderModel and ReaderRouter](T51-reader-model-and-router.md) | ui-builder | T38, T45 | no |
| 24 | [T52 Reader tabs, toolbar, commands](T52-reader-window-and-commands.md) | ui-builder | T47, T48, T51 | yes |
| 25 | [T53 PDF reader view](T53-pdf-reader-view.md) | pdf-engine | T52 | yes |
| 26 | [T54 PDF dark-mode inversion](T54-pdf-dark-mode-inversion.md) | pdf-engine | T53 | yes |
| 27 | [T55 TextReaderView and the Markdown reader](T55-text-reader-view-markdown.md) | pdf-engine | T43, T52 | yes |
| 28 | [T56 PDF highlight anchoring and annotations](T56-pdf-highlight-anchoring.md) | pdf-engine | T53 | no |
| 29 | [T57 Text anchoring and re-anchoring](T57-text-anchoring-and-reanchoring.md) | pdf-engine | none | no |
| 30 | [T58 Markdown rich text and escaping](T58-markdown-rich-text.md) | pdf-engine | T43 | no |
| 31 | [T59 PDF highlight interaction](T59-pdf-highlight-interaction.md) | pdf-engine | T51, T56, T58 | yes |
| 32 | [T60 Markdown highlight interaction](T60-markdown-highlight-interaction.md) | pdf-engine | T51, T55, T57, T58 | yes |
| 33 | [T61 Snapshot service and tool](T61-snapshot-service-and-tool.md) | pdf-engine | T59 | yes |
| 34 | [T62 Highlight popover and selection toolbar](T62-highlight-popover-and-selection-toolbar.md) | ui-builder | T37, T49, T59, T60 | yes |
| 35 | [T63 Reader side panel](T63-reader-side-panel.md) | ui-builder | T62 | yes |
| 36 | [T64 SearchQueryParser](T64-search-query-parser.md) | data-layer | none | no |
| 37 | [T65 SearchService](T65-search-service.md) | data-layer (model sonnet, effort high) | T44, T64 | no |
| 38 | [T66 Global search UI](T66-global-search-ui.md) | ui-builder | T52, T65 | yes |
| 39 | [T67 In-document find and search-hit navigation](T67-in-document-find-and-search-hits.md) | pdf-engine | T59, T60, T66 | yes |
| 40 | [T68 Highlight browse query](T68-highlight-browse-query.md) | data-layer | T35, T36 | no |
| 41 | [T69 Highlights browser](T69-highlights-browser.md) | ui-builder | T49, T63, T68 | yes |
| 42 | [T70 ExportRepository, ExportRenderer, Drive folder links](T70-export-repository-and-renderer.md) | integrations | T36, T37, T58 | no |
| 43 | [T71 GoogleExportService](T71-google-export-service.md) | integrations | T70 | no |
| 44 | [T72 Google sign-in and session restore](T72-google-sign-in-and-session-restore.md) | integrations | T45, T71 | yes |
| 45 | [T73 Export UI](T73-export-ui.md) | ui-builder | T69, T72 | yes |
| 46 | [T74 ExportSyncScheduler](T74-export-sync-scheduler.md) | integrations | T73 | no |

Task numbers continue after Phase 0's last commit (T28). Tasks with "none" or early dependencies (T42, T57, T64) may run earlier if a chain is blocked, but keep one implementer at a time.

## Points of care for the orchestrator
- **T30** is done and committed.
- **T31** ends with a manual Console check by the user before import work (T41+) starts. If a normal launch logs "Using the in-memory library", stop the phase.
- **Combined visual checks:** T47's full check happens at T48 (documents can only be imported then) and T49's at T50 (tags can first be created there). Commit T47 and T49 after review plus their small "empty state" check.
- **T41 and T65** run as data-layer with model `sonnet`, effort `high` from the first call. Treat them as escalated: review with code-reviewer effort `high`; two rejections → ask the user.
- **Shared files touched by many tasks, in order:** `AppEnvironment.swift` (T31, T33, T35–T38, T44, T65, T70–T72, T74), `AppSession.swift` (T45, T48, T51, T66), `RootView.swift` (T45, T47, T48, T49, T50, T66, T69), `AppCommands.swift` (T48, T50, T52, T66, T73), `ReaderWindowView.swift` (T52, T53, T55, T62, T63), `StudyPDFView.swift`/`PDFReaderController.swift` (T53, T54, T59, T61, T67). One command per shortcut: ⇧⌘M (T50, extended by T52) and ⌘F (T52, extended by T66) each stay a single command.
- **Signing is done by the user** (ADR-0011 amendment): `DEVELOPMENT_TEAM: "597KGSTZWJ"`, no `CODE_SIGN_IDENTITY` override, `keychain-access-groups` in the app's entitlements, and the scripts pass `-allowProvisioningUpdates`. No Phase 1 task changes signing, `project.yml` signing keys or entitlements.
- **Document tabs (T52):** native window tabbing only. If T52 reports BLOCKED because tabbing can't be controlled, ask the user; don't accept a custom tab bar.
- **Google credentials are done by the user** (`Secrets/Google.xcconfig`, included by `Config/Base.xcconfig`). Agents never read `Secrets/`. Specs use only the `GOOGLE_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` build settings and `GIDClientID` from Info.plist; when `GOOGLE_CLIENT_ID` is empty at runtime, the app shows "Google export not configured" (T71–T73). Everything before T72 is tested with stubs.
- **Every test that writes FTS-indexed tables ends with `FTSIntegrity.check`** (ARCHITECTURE §15). Backlog L7 stays opportunistic; no Phase 1 task edits those three suites.
- **Backlog L2** isn't triggered: all `FixedNow` dates in Phase 1 tests (`TestData.referenceDate`, 2026-09) are in the past. It stays in the backlog until Phase 2.
- Reviewers reject: full `update(db)` for position/progress/color/status/anchor saves, any `upsert(`, a bare `Date` in SQL, `URLSession.shared`, `Date()` or `Task.sleep` in logic, PDFKit objects crossing actors, `PDFDocument.write` outside `PDFImportInspector.writeUnlockedCopy`, any EPUB mention.

## Shared interfaces (where they're defined)
| Name | Task |
|---|---|
| `FileType.storedFileExtension`, `FileType(fileExtension:)`, `FileStore.originalFileURL(documentId:fileType:)` | T29 |
| `AppDatabaseError.newerVersion/.storageFailure/.busy` | T32 |
| `Hashing`, `Sleeper`/`SystemSleeper`, `Debouncer`, `SettingsStore`, `LibraryLayout`, `LibrarySort`; tests: `ImmediateSleeper`, `ManualSleeper`, `TestSettings` | T33 |
| `LibraryItem`, `RepositoryError`, `DocumentEditError`, `CategoryError`, `CategoryUsage` | T34 |
| `HighlightRepository` | T35 |
| `TagRepository`, `TagError`, `TagUsage` | T36 |
| `NotesRepository`, `TagParsing`, `NoteEditorModel` | T37 |
| `NewTextHighlight`, `NewImageHighlight`, `HighlightService` | T38 |
| `PDFImportInspector`, `PDFInfo`, `CoverRenderer`, `CoverService` | T39 |
| `MetadataDefaults`, `FrontMatter(Parser)`, `MarkdownImageNaming`, `MarkdownImageCollector`, `FileStore.markdownImageURL` | T40 |
| `ImportService`, `ImportInteraction`, `ExtractionQueue`, `ImportReport` | T41 |
| `PDFTextExtractor`, `ExtractedPage` | T42 |
| `MarkdownRenderer`, `RenderedMarkdown`, `MarkdownSourceMap`, `InlineTraits` | T43 |
| `ExtractionService`, `DocumentTextRepository`, `LibraryMaintenance`, `AppEnvironment.startBackgroundWork()` | T44 |
| `AppSession`, `AppSettings`, `HighlightPalette` | T45 |
| `ReaderLocation`, `ReaderRouter`, `ReaderModel`, `HighlightPopoverRequest`, `SelectionToolbarRequest`, `ReaderEngineActions`, `ReaderPanelTab` | T51 |
| `ReaderActions`, `ReaderWindowState`, `ReaderTabbing`, `WindowAccessor`, `LibraryActions` (T47) | T52 |
| `StudyPDFView`, `PDFReaderController` | T53 |
| `TextReaderView`, `TextReaderController` | T55 |
| `PDFAnchorBuilder`, `StudyHighlightAnnotation`, `PDFHighlightGeometry` | T56 |
| `TextAnchoring` | T57 |
| `RichTextMarkdown` | T58 |
| `SnapshotService` | T61 |
| `RichTextView`, `HighlightPopoverModel` | T62 |
| `SearchQueryParser` | T64 |
| `SearchService`, `SearchResults`, `SearchFilters` | T65 |
| `HighlightBrowserFilter`, `HighlightBrowserSort`, `HighlightListItem` | T68 |
| `ExportStatus`, `ExportContent`, `ExportRepository`, `ExportRenderer`, `DriveFolderLink` | T70 |
| `HTTPClient`, `GoogleAuthProviding`, `ExportOutcome`, `GoogleExportService` | T71 |
| `GoogleSignInAuth`, `GoogleAccountModel` | T72 |
| `ExportSyncScheduler`, `NetworkPathMonitoring`, `ExportPerforming` | T74 |

## Module map after Phase 1
```
StudyReader/App/                       StudyReaderApp, AppDelegate, AppCommands, ReaderTabbing, AppEnvironment, AppLaunchModel, AppSession,
                                       AppSettings, LaunchView, RootView, RootModel, SidebarItem, MainWindowLayout
StudyReader/Core/Support/              Now, Logging, Hashing, Sleeper, Debounce, SettingsStore, HTTPClient
StudyReader/Core/Files/                FileStore (+ storedFileExtension, markdownImageURL)
StudyReader/Core/Models/               (Phase 0 records) + LibraryItem
StudyReader/Core/Database/             unchanged schema (v1, v2) + AppDatabaseError cases
StudyReader/Core/Repositories/         Category, Document, DocumentText, Highlight (+ HighlightBrowseQuery), Tag, Notes, Export
StudyReader/Features/Library/          LibraryModel/View, item views, covers (CoverRenderer, CoverService, DocumentCoverView),
                                       Import/ (ImportService, PDFImportInspector, MetadataDefaults, ImportCoordinator),
                                       Metadata/, Categories/
StudyReader/Features/Extraction/       PDFTextExtractor, ExtractionService, LibraryMaintenance
StudyReader/Features/Reader/           ReaderModel, ReaderRouter, ReaderTypes, ReaderWindowView, ReaderActions
StudyReader/Features/Reader/PDF/       StudyPDFView, PDFReaderController/View, PDFInversion, PDFAnchorBuilder,
                                       StudyHighlightAnnotation, PDFHighlightController, SnapshotService/Tool, PDFFind*
StudyReader/Features/Reader/Text/      TextReaderView/Controller, TextBlockDecorations, TextAnchoring, TextHighlightController
StudyReader/Features/Reader/Markdown/  MarkdownRenderer, MarkdownStyle, MarkdownSourceMap, FrontMatter, MarkdownImages,
                                       MarkdownReaderView
StudyReader/Features/Reader/Chrome/    HighlightsPanel*, DocumentNotePanelView
StudyReader/Features/Annotations/      HighlightService, HighlightPalette, RichTextMarkdown, RichTextView, TagParsing,
                                       NoteEditorModel, HighlightPopover*, SelectionToolbarView, Tags/
StudyReader/Features/Search/           SearchQueryParser, SearchService, SearchResults, SearchModel, SearchResultsView
StudyReader/Features/HighlightsBrowser/ HighlightsBrowserModel/View, HighlightDetailView
StudyReader/Features/Export/           ExportContent, ExportRenderer, DriveFolderLink, DriveUploadRequest, GoogleAuthProviding,
                                       GoogleSignInAuth, GoogleExportService, ExportSheet*, ExportTargetsModel,
                                       ExportSyncScheduler, NetworkPathMonitoring
StudyReader/Features/Settings/         SettingsView, GoogleSettingsView
StudyReaderTests/                      + LibraryTests, ExtractionTests, MarkdownTests, ReaderTests, AnnotationsTests,
                                       SearchTests, HighlightsBrowserTests, ExportTests; Support/ + TestSleepers, TestSettings,
                                       StubHTTPClient, StubGoogleAuth, StubNetworkPath; Fixtures/golden/export/*.md
```

## User decisions (2026-10-24)
- **Q1 (T39, T41):** password-protected PDFs: store a decrypted copy made by PDFKit after the user types the password once. Confirmed (ADR-0016).
- **Q2 (T51, T52, changed):** documents open as **native macOS window tabs** in the main window's tab group; the library stays the first tab; opening an open document selects its tab; tabs can be dragged out. AppKit `tabbingMode`/`tabbingIdentifier` if SwiftUI can't; BLOCKED rather than a custom tab bar (ADR-0017, SPEC F-01 AC4).
- **Q3 (T71, T73):** "Export selection" creates a new Google Doc each time and saves no target. Confirmed (ADR-0018).
- **Q4 (T32):** L5 and L6 ship now without a migration. Confirmed.
- **Q5 (T40, T41, T48, changed):** when a single imported `.md` file's relative images can't be read, the import asks once per folder per batch for folder access (NSOpenPanel preselected on the file's folder, behind `ImportInteraction.requestFolderAccess`); approval copies the images, no bookmark is kept; cancel leaves placeholders (ADR-0016, SPEC F-03 AC4).
- **Q6 (T42):** PDF text extraction is built in Phase 1. Confirmed.
- **Q7 (T65, T70):** tag filter semantics as specified. Confirmed.

## Phase done when
- All 46 tasks are approved and committed (`TNN: <title>`), and every visual check is confirmed by the user.
- The full suite passes via test-runner, and `./scripts/check-fresh-clone.sh` passes.
- The SPEC §6 "done when" flow works on the user's Mac with a real lecture PDF and Gemini Notebook.
- bug-hunter has run; critical/high findings (and mediums that get more expensive later) are fixed; the rest are in `docs/bugs/backlog.md`.
