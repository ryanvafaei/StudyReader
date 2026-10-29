# StudyReader — Dependencies and reference code

Researched 2026-10-23. Versions, licenses, and last-commit dates were checked against each repository's source (cloned and inspected).

## 1. Decision: build from scratch on proven libraries

No existing open-source app is a good base to fork. The four closest macOS apps were inspected:

| Repo | What it is | License | Why not fork |
|---|---|---|---|
| [Marvy101/reader-source](https://github.com/Marvy101/reader-source) | Native macOS reading workspace: PDF/EPUB/TXT, highlights, notes, GRDB, local library | MIT | Closest match, but ~25k lines with EPUB, AI chat, Supabase backend, accounts, and a browser built in. Removing that costs more than building our scope; no FTS5 search, spaced repetition, or Google export. Published Sept 2026, single maintainer. |
| [mweingartner/annotate](https://github.com/mweingartner/annotate) | macOS 26 PDF workspace: editing, forms, signatures, OCR, assistant | MIT | Wrong focus (PDF editing), ~32k lines. Useful as a reference for Foundation Models and markers. |
| [basicv8vc/YoPDF](https://github.com/basicv8vc/YoPDF) | Early macOS PDF reader with standard highlight/underline/note annotations, 267 tests | Apache-2.0 | Started Oct 2026; writes annotations into PDFs (we keep them in a database). Excellent reference for PDFKit highlight geometry. |
| [Marvelxy/PDFReader](https://github.com/Marvelxy/PDFReader) | macOS PDF reader with auto-highlight on selection | **GPL-3.0** | GPL would force the whole app to GPL. Look at behavior only; **never copy code**. |

So: our own app code, built on the libraries in §2, with selected files from MIT/Apache repos as references (§3).

## 2. Runtime dependencies (Swift Package Manager)

Only these. Adding any other package needs the user's approval.

| Package | Product | Version | License | Last commit | Used for |
|---|---|---|---|---|---|
| [groue/GRDB.swift](https://github.com/groue/GRDB.swift) | `GRDB` | from 7.11.1 | MIT | 2026-08-08 | SQLite, migrations, `ValueObservation`, FTS5 (system SQLite supports FTS5 on macOS, no custom build) |
| [swiftlang/swift-markdown](https://github.com/swiftlang/swift-markdown) | `Markdown` | from 0.9.0 | Apache-2.0 | 2026-09-24 | Parse Markdown (CommonMark + GFM) into an AST; `HTMLFormatter` for the HTML export fallback |
| [open-spaced-repetition/swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs) | `FSRS` | from 5.0.0 | MIT | 2026-05-25 | FSRS-6 scheduling (default parameters; see §5 and ADR-0021), Swift Testing, concurrency-friendly. Official org listed in [awesome-fsrs](https://github.com/open-spaced-repetition/awesome-fsrs) |
| [google/GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) | `GoogleSignIn` | from 10.1.0 | Apache-2.0 | 2026-10-22 | Google OAuth on macOS (supports macOS 12+), token refresh and Keychain storage. Pulls in AppAuth, GTMAppAuth, gtm-session-fetcher, GoogleUtilities, app-check |

Apple frameworks (no dependency): SwiftUI, AppKit, PDFKit, NaturalLanguage (`NLEmbedding`), FoundationModels (on-device model, Apple Intelligence Macs), Vision (`RecognizeDocumentsRequest`, macOS 26+, optional later), CryptoKit (SHA-256), Network (`NWPathMonitor`), UniformTypeIdentifiers.

Build tool (not linked): [yonaskolb/XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46.0, MIT, last commit 2026-10-13. Install with `brew install xcodegen`.

## 3. Reference repositories (read, adapt, don't depend)

Downloaded into `.references/` (git-ignored) at pinned commits. Each folder has a `.pinned-commit` file.

| Folder | Commit | License |
|---|---|---|
| `.references/YoPDF` | `f498e833aefd` | Apache-2.0 |
| `.references/reader-source` | `491f83ab8846` | MIT |
| `.references/annotate` | `a21b6d7ed4c2` | MIT |

Rules for agents:
- Read only the files listed below for your task. Don't Glob or Grep `.references/` broadly; never Explore it.
- Prefer re-implementing the idea in our architecture. If you copy more than ~20 lines, keep the original copyright line and license name in a comment at the top of the copied block (MIT and Apache-2.0 both require keeping the notice), and add the file to `THIRD_PARTY_NOTICES.md`.
- `reader-source` contains EPUB code. Never read or copy anything under `Formats/` other than `Formats/PDF/`.
- Reference repos are young (2026) and may contain bugs. Copied code is reviewed and tested like our own.

| Task area | Files to read | What to take |
|---|---|---|
| PDF highlight geometry | `YoPDF/macos/YoPDFCore/HighlightService.swift` | `PDFSelection` → per-line rects, one annotation per page for cross-page selections, the note that `quadrilateralPoints` are relative to the annotation bounds |
| PDF highlight editing | `YoPDF/macos/YoPDFCore/MarkupAnnotation.swift`, `MarkupEditing.swift` | Recolor/delete patterns, undo |
| PDFView hosting | `YoPDF/macos/YoPDF/Reader/PDFViewerRepresentable.swift` | `NSViewRepresentable` wrapper, selection and mouse handling |
| Rendering stored highlights, margin notes | `reader-source/Reader/Formats/PDF/PDFKitReadingAdapter.swift` | Adding display-only annotations, mouse handling in a `PDFView` subclass |
| Text anchors | `reader-source/Reader/ReaderCore/ReadingTypes.swift` (`TextAnchor`, `ReaderLocator`) | exact/prefix/suffix anchor shape (matches our §5 design) |
| Library store with GRDB | `reader-source/Reader/Persistence/ReaderLibraryStore.swift` | GRDB record and migration style |
| Import pipeline | `reader-source/Reader/Import/PublicationImportService.swift` | File copy, hashing, error reporting |
| Foundation Models usage | `annotate/Sources/AnnotateCore/DocumentAssistantLanguageModel.swift` | Availability check, session setup, error handling |
| Auto-highlight behavior | [Marvelxy/PDFReader README](https://github.com/Marvelxy/PDFReader) | Behavior only ("highlights apply automatically once a text selection settles"). GPL: don't open its source files |

## 4. Google setup (manual, once, by the user)

Needed before export works; the app builds and runs without it.

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project (e.g. "StudyReader").
2. APIs & Services → Library → enable **Google Drive API**.
3. OAuth consent screen: User type External, app name StudyReader, your email as support/developer contact, publishing status **Testing**, add your Google account under **Test users**. Scope: `.../auth/drive.file`.
4. Credentials → Create credentials → OAuth client ID → Application type **iOS** (Google requires the iOS type for macOS apps using GoogleSignIn). Bundle ID: the app's bundle identifier (default `com.ryanvafaei.StudyReader`).
5. Copy `Config/Google.xcconfig.example` to `Secrets/Google.xcconfig` and fill in:
   ```
   GOOGLE_CLIENT_ID = <client id>.apps.googleusercontent.com
   GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.<client id>
   ```
6. In `project.yml`, set `DEVELOPMENT_TEAM` to your Apple team ID (a free Apple ID "Personal Team" works for running locally). GoogleSignIn needs a signed app with a Keychain access group.
   - Done by the user on 2026-10-24 (ADR-0011): `DEVELOPMENT_TEAM: "597KGSTZWJ"` and `keychain-access-groups` are in `project.yml`, and `Secrets/Google.xcconfig` exists. Agents never read `Secrets/`; the app sees the credentials only as `GIDClientID` (from `GOOGLE_CLIENT_ID`) and the URL scheme (from `GOOGLE_REVERSED_CLIENT_ID`). An empty `GOOGLE_CLIENT_ID` at runtime means "Google export not configured".

Source: [Google Sign-In for iOS and macOS: get started](https://developers.google.com/identity/sign-in/ios/start-integrating) (iOS client type for macOS, `GIDClientID`, reversed client ID URL scheme, keychain access group).

## 5. Verified facts the design relies on

| Fact | Source |
|---|---|
| Drive API converts uploaded Markdown or HTML to Google Docs when the target `mimeType` is a Docs type; `about.importFormats` lists available conversions | [Drive API: upload file data](https://developers.google.com/workspace/drive/api/guides/manage-uploads) |
| A converting `update` replaces the full content of the Doc | same page |
| Google Docs added to Gemini Notebook from Drive auto-sync every few minutes | [Gemini Notebook help: add sources](https://support.google.com/gemininotebook/answer/16215270) |
| Gemini Notebook does not import comments from Google Docs, so notes are exported as body text | same page |
| `RecognizeDocumentsRequest` (Vision) is available on macOS 26+ and returns paragraphs, lists, and tables | [Apple docs](https://developer.apple.com/documentation/vision/recognizedocumentsrequest) |
| Foundation Models needs an Apple Intelligence–capable device; supports guided generation with `@Generable` | [Apple docs](https://developer.apple.com/documentation/foundationmodels) |
| GRDB supports FTS5 with the system SQLite on macOS 10.13+ | GRDB README |
| swift-fsrs implements FSRS-6 with 21 weights; `Card(due:)` is public; `Rating` = manual/again/hard/good/easy. Correction (T01, 2026-10-24; ADR-0021): in 5.0.0 `FSRSDefaults.defaultWv6` doesn't exist and `defaultW` is internal; the weights come from the library's default parameters | swift-fsrs source |

## 6. Considered and rejected

| Option | Why rejected |
|---|---|
| [gonzalezreal/textual](https://github.com/gonzalezreal/textual) 0.5.0 (MIT; successor to MarkdownUI, which is in maintenance mode) | SwiftUI rendering; we need NSTextView-level control of selection ranges and highlight drawing with stable UTF-16 offsets |
| Apple `AttributedString(markdown:)` alone | Weak block-level support (tables, code blocks, lists) and no source map for rich-text extraction |
| [4rays/swift-fsrs](https://github.com/4rays/swift-fsrs) 0.9.2 | Last commit Oct 2024; the open-spaced-repetition package is maintained and implements FSRS-6 |
| [openid/AppAuth-iOS](https://github.com/openid/AppAuth-iOS) directly, or hand-written PKCE flow | More custom security code; GoogleSignIn wraps AppAuth and handles Google's macOS specifics |
| Google Docs `documents.batchUpdate` for export | Building a Doc via structural requests is far more code; Drive Markdown conversion does it in one upload and the update replaces content cleanly |
| Similarity-search libraries | Brute-force cosine over a personal library (thousands of highlights) is fast enough |
| Hand-maintained `.xcodeproj` | Agents editing `project.pbxproj` is error-prone; XcodeGen keeps the project as reviewable YAML |
