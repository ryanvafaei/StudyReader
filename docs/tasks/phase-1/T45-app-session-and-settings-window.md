# T45: AppSession, AppSettings, highlight palette and the Settings window (Phase 1 tabs)

- **Phase:** 1 (F-22 subset: General, Reading, Data; F-06 color labels)
- **Agent:** ui-builder
- **Depends on:** T33, T34
- **ADRs:** docs/decisions/0015-settings-and-injected-sleep.md (read in full), docs/decisions/0017-reader-windows-and-commands.md (AppSession owns shared UI state)
- **Visual check needed:** yes

## Goal
One shared main-actor session object for all windows (main, readers, Settings), live settings for SwiftUI, the five highlight colors, and a Settings window (⌘,) with the tabs Phase 1 needs. The Review tab comes in Phase 2 and the Google tab in T72/T73.

## Files to touch
- `StudyReader/App/AppSession.swift` (new)
- `StudyReader/App/AppSettings.swift` (new)
- `StudyReader/App/AppLaunchModel.swift` (modify)
- `StudyReader/App/LaunchView.swift`, `StudyReader/App/RootView.swift`, `StudyReader/App/StudyReaderApp.swift` (modify)
- `StudyReader/Features/Annotations/HighlightPalette.swift` (new)
- `StudyReader/Features/Settings/SettingsView.swift` (new)
- `StudyReader/Features/Settings/SettingsCategoryOptions.swift` (new: pure fallback for the default-category picker)
- `StudyReaderTests/AppTests/AppSettingsTests.swift` (new)
- `StudyReaderTests/AppTests/SettingsCategoryOptionsTests.swift` (new)

## Interfaces to produce
```swift
/// Shared state for every window of this app run. Created on the main actor when the library is ready.
@MainActor @Observable
final class AppSession {
    let environment: AppEnvironment
    let settings: AppSettings
    init(environment: AppEnvironment)          // settings = AppSettings(store: environment.settingsStore)
}

/// Live mirror of SettingsStore (ADR-0015). Every property writes through in didSet.
@MainActor @Observable
final class AppSettings {
    init(store: SettingsStore)                 // reads every value once
    var defaultCategoryId: String
    var autoHighlight: Bool
    var currentColor: HighlightColor
    var invertPDFInDarkMode: Bool
    var googleExportFolderId: String?
    var libraryLayout: LibraryLayout
    var librarySort: LibrarySort
    /// Index = HighlightColor.rawValue (5 entries).
    private(set) var colorLabels: [String]
    func label(for color: HighlightColor) -> String
    func setLabel(_ label: String, for color: HighlightColor)   // store.setColorLabel, then re-read colorLabels
}

enum HighlightPalette {
    static func color(_ color: HighlightColor) -> Color            // SwiftUI
    static func nsColor(_ color: HighlightColor) -> NSColor        // AppKit, opaque; highlight drawing applies alpha 0.35 itself
    // RGB: yellow (1.00, 0.85, 0.20), green (0.40, 0.80, 0.40), blue (0.35, 0.65, 1.00),
    //      pink (1.00, 0.45, 0.65), purple (0.70, 0.50, 0.95)
}

/// Pure helper for the "Default category for imports" picker (Features/Settings/SettingsCategoryOptions.swift).
enum SettingsCategoryOptions {
    /// `saved` if a category with that id is in `categories`; else the first category's id; else nil (empty list).
    static func effectiveSelection(saved: String, in categories: [DocumentCategory]) -> String?
}
```
`AppLaunchModel`: add `private(set) var session: AppSession?`. In `start()` on success: `session = AppSession(environment: environment)` immediately before `state = .ready(environment)`. Keep `State` unchanged so existing tests compile.

Views:
- `LaunchView` `.ready`: `if let session = model.session { RootView(session: session) }`.
- `RootView.init(session: AppSession)`; it still creates `RootModel(environment: session.environment)` (keep `RootModel` unchanged) and keeps `session` for child views.
- `StudyReaderApp`: add `Settings { SettingsRootView(launchModel: launchModel) }` which shows `SettingsView(session:)` when `launchModel.session` is non-nil, else a `ProgressView`.
- `SettingsView`: `TabView` with
  - **General**: "Default category for imports" (`Picker` over categories from `session.environment.categoryRepository.observeAll()`). The picker binds an `Optional<String>` selection whose getter is `SettingsCategoryOptions.effectiveSelection(saved: settings.defaultCategoryId, in: categories)` and whose setter writes `settings.defaultCategoryId` only when the user picks a non-nil value (merely rendering the fallback never writes the setting). The picker is disabled while the category list is empty; "Highlight automatically when I select text" (`Toggle`, `autoHighlight`); "Highlight colors": five rows, each a color swatch (`HighlightPalette.color`) and a `TextField` bound through `label(for:)` / `setLabel(_:for:)` (commit on submit and on focus loss).
  - **Reading**: "Invert PDF colors in dark mode" (`Toggle`, `invertPDFInDarkMode`).
  - **Data**: "Library location" with the read-only path `session.environment.fileStore.rootURL.path(percentEncoded: false)` (selectable text) and a "Reveal in Finder" button (`NSWorkspace.shared.activateFileViewerSelecting([rootURL])`).
  - Fixed frame width 520; every control has an accessibility label (SPEC §4).
- All user-facing strings use `String(localized:)` / `Text("…")` literals so they land in the String Catalog.

## Tests (`AppSettingsTests`, `@MainActor`, `TestSettings.make()` + remove)
- `readsStoreValues`: set values in the store first; a new `AppSettings` shows them.
- `writesThrough`: change every property on `AppSettings`; a fresh `SettingsStore(suiteName:)` over the same suite (as settled in T33) reads the new values; `setLabel("Exam prep", for: .green)` → `label(for: .green) == "Exam prep"` and `colorLabels[1] == "Exam prep"`; `setLabel("", for: .green)` → "Exam".
- `sessionCreatedOnReady`: `AppLaunchModel(makeEnvironment: { try AppEnvironment.inMemory() })`; `await start()`; `session != nil`, `session?.environment.fileStore == <the ready environment's fileStore>`; remove the folder.

`SettingsCategoryOptionsTests` (pure; categories built in the test with their ids):
- `savedIdPresent`: saved id is in the list → returns it.
- `savedIdMissingFallsBackToFirst`: saved id not in the list (e.g. a deleted custom category) → the first category's id.
- `emptyListGivesNil`: `[]` → nil.

## Acceptance criteria
1. Settings changes persist immediately and are visible app-wide. → tests `AppSettingsTests/readsStoreValues`, `writesThrough`
2. The launch model creates exactly one session when ready. → test `AppSettingsTests/sessionCreatedOnReady`
2a. The default-category picker falls back as specified and never writes the setting unless the user picks. → tests `SettingsCategoryOptionsTests/*` + code review of the picker binding
3. Visual check (user): run the app, press ⌘,. The Settings window shows General, Reading and Data tabs. Change the default category, toggle auto-highlight, rename the green label to "Exam prep", toggle PDF inversion; quit and relaunch; all four values are kept. Data shows the library path and "Reveal in Finder" opens it.
4. Existing `AppLaunchModelTests`, `RootModelTests` pass unchanged.

## Out of scope
- Review and Google tabs, "Rebuild search index", "Recompute embeddings" (later phases / T72).
- Using the settings in readers (T54, T59, T60).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (code-reviewer, effort medium): APPROVED after user visual check (9 steps, light/dark, persistence). Follow-ups from the check: NoteEditorModel weak-self warning fixed, picker falls back to first category (SettingsCategoryOptions.effectiveSelection, 8 tests), DEAD_CODE_STRIPPING already in project.yml. 301 tests pass, 0 warnings. Picker-fallback visual check (no invalid-selection warning) still with the user.
