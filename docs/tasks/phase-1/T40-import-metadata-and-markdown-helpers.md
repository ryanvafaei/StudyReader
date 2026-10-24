# T40: Import helpers: metadata defaults, front matter, Markdown images

- **Phase:** 1 (E1.1/E1.3: F-02, F-03, F-11)
- **Agent:** data-layer
- **Depends on:** T29
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md ("Markdown images"), docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Pure helpers the importer (T41) and the Markdown renderer (T43) share: title/author defaults (F-11), YAML front matter splitting (F-03), and finding, naming and copying relative Markdown images (F-03). No database access.

## Files to touch
- `StudyReader/Features/Library/Import/MetadataDefaults.swift` (new)
- `StudyReader/Features/Reader/Markdown/FrontMatter.swift` (new)
- `StudyReader/Features/Reader/Markdown/MarkdownImages.swift` (new)
- `StudyReader/Core/Files/FileStore.swift` (modify: one builder)
- `StudyReaderTests/LibraryTests/MetadataDefaultsTests.swift`, `StudyReaderTests/MarkdownTests/FrontMatterTests.swift`, `StudyReaderTests/MarkdownTests/MarkdownImagesTests.swift` (new)

## Interfaces to produce
```swift
enum MetadataDefaults {
    /// metadataTitle trimmed, unless it looks like a file name (rules below); else the file name without its
    /// last extension (or the whole name if that is empty).
    static func title(metadataTitle: String?, fileName: String) -> String
    /// Trimmed metadata author, or "".
    static func author(metadataAuthor: String?) -> String
}
```
A trimmed title `t` is rejected (file-name-like) when any of these hold:
- `t` is empty;
- `t.lowercased()` ends with `.pdf`, `.doc`, `.docx`, `.ppt`, `.pptx`, `.key`, `.pages`, `.tex`, `.dvi`, `.txt`, `.md` or `.markdown`;
- `t` contains `/` or `\`;
- `t` contains no letter (`t.unicodeScalars` has no `CharacterSet.letters` member);
- `t.lowercased()` is one of `untitled`, `untitled document`, `document`, `presentation`, `powerpoint presentation`;
- `t.lowercased()` starts with `microsoft word - ` or `microsoft powerpoint - `.

```swift
struct FrontMatter: Sendable, Equatable {
    var title: String?
    var author: String?
}
enum FrontMatterParser {
    /// If the text (after an optional U+FEFF) starts with a line that is exactly "---", and a later line is exactly
    /// "---" or "...", the lines between are front matter and `body` is everything after the closing line's newline.
    /// Otherwise frontMatter is empty and body is the input unchanged.
    /// Lines are "key: value"; keys compared lowercased; values trimmed, one pair of surrounding
    /// "double" or 'single' quotes removed; empty values → nil. Only title and author are kept.
    /// Line endings "\r\n" are treated like "\n".
    static func split(_ markdown: String) -> (frontMatter: FrontMatter, body: String)
}

enum MarkdownImageNaming {
    /// Stored file name for an image source written in Markdown (ADR-0016), or nil when the source isn't
    /// copied: it has a URL scheme (contains "://" or starts with "data:" / "mailto:"), starts with "/" or "#",
    /// is empty, or its lowercased path extension (query/fragment removed) isn't 1–10 of a–z/0–9.
    /// Name = first 16 chars of Hashing.sha256Hex(of: source) + "." + lowercased extension.
    static func storedFileName(forSource source: String) -> String?
    /// true for http/https sources (rendered as a placeholder showing the URL, never fetched).
    static func isRemote(_ source: String) -> Bool
}

enum MarkdownImageCollector {
    /// Image sources (swift-markdown `Image.source`) in document order, without duplicates. Parses `body`
    /// with `Document(parsing:)` and a MarkupWalker that visits `Image` nodes.
    static func imageSources(in markdownBody: String) -> [String]

    struct CopyResult: Sendable, Equatable {
        var copied: Int
        var missing: Int        // the copy failed with CocoaError .fileReadNoSuchFile or .fileNoSuchFile
        var unreadable: Int     // the copy failed with any other error (in practice the sandbox denying access)
        var alreadyPresent: Int // destination existed already (skipped; counts as copied for the caller)
    }
    /// For each source with a storedFileName: resolve `sourceFolder.appending(path: source.removingPercentEncoding ?? source)`,
    /// copy to imagesFolder/storedFileName (creating imagesFolder when the first copy happens). If the destination
    /// already exists, count alreadyPresent and skip (so a second call after folder access only retries the failures).
    /// Classify failures by the thrown error, never with fileExists (the sandbox can hide existence).
    /// Remote and invalid sources are skipped and not counted.
    static func copyImages(sources: [String], from sourceFolder: URL, to imagesFolder: URL) -> CopyResult
}
```
`FileStore` addition (validated builder; nothing else may build these paths):
```swift
/// Documents/<id>/images/<storedFileName>. storedFileName must match ^[0-9a-f]{16}\.[a-z0-9]{1,10}$,
/// else FileStoreError.invalidFileExtension(storedFileName).
func markdownImageURL(documentId: String, storedFileName: String) throws -> URL
```
Use `imagesFolderURL(documentId:)` for the folder.

## Tests
- `MetadataDefaultsTests/usesMetadataTitle`: `("Neural Networks", "lec3.pdf")` → "Neural Networks"; `("  Gradient Descent\n", "x.pdf")` → "Gradient Descent".
- `MetadataDefaultsTests/fallsBackToFileName`: each rejected form above (one example each: `nil`, `""`, `"slides.pptx"`, `"C:\\docs\\a"`, `"1234"`, `"Untitled"`, `"PowerPoint Presentation"`, `"Microsoft Word - notes.docx"`) with file name `"Lecture 3.PDF"` → `"Lecture 3"`; file name `"README"` → `"README"`; file name `".pdf"` → `".pdf"`.
- `MetadataDefaultsTests/author`: `"  Ada "` → `"Ada"`; nil → `""`.
- `FrontMatterTests/parsesTitleAndAuthor`: `MarkdownFixtures.string("front-matter")` → title "Gradient Descent Notes", author "Ada Lovelace"; body starts with `"\n# Gradient Descent"` (the blank line after the closing `---` stays) and doesn't contain "course:".
- `FrontMatterTests/variants`: quoted values (`title: "A: B"` → `A: B`), `...` closer, CRLF input, BOM prefix, no closing line (unchanged body, empty front matter), `---` not on the first line (unchanged), empty value → nil.
- `MarkdownImagesTests/naming`: `"images/diagram.png"` → 16 hex + ".png" and stable across calls; `"IMG/A.JPG"` → ends with ".jpg"; `"https://example.com/remote.png"` → nil and `isRemote` true; `"/abs/x.png"`, `"#frag"`, `"noext"`, `"data:image/png;base64,AAA"` → nil; `"images/a.png?x=1"` → ends ".png".
- `MarkdownImagesTests/collectsAndCopies`: `MarkdownFixtures.makeFolderWithImages()` (notes.md + images/diagram.png); `imageSources(in:)` of its body == `["images/diagram.png", "images/missing.png", "https://example.com/remote.png"]`; `copyImages` into a temp folder → `CopyResult(copied: 1, missing: 1, unreadable: 0, alreadyPresent: 0)` and the file `storedFileName(forSource: "images/diagram.png")` exists with the same bytes. A second identical call → `copied: 0, missing: 1, alreadyPresent: 1`. Remove temp folders in `defer`.
- `MarkdownImagesTests/permissionErrorIsUnreadable`: make `images/diagram.png` unreadable (`FileManager.setAttributes([.posixPermissions: 0o000])`, restore 0o644 in `defer` before removal); `copyImages` → `unreadable: 1`, `missing: 1`.
- `MarkdownImagesTests/fileStoreBuilderValidates`: valid name → URL under `images/`; `"../x.png"`, `"ABCDEF0123456789.png"` (uppercase), `"short.png"` → throw.

## Acceptance criteria
1. Title and author defaults follow the rules. → tests `MetadataDefaultsTests/*` (SPEC F-11 AC1)
2. Front matter is split and title/author extracted. → tests `FrontMatterTests/*`
3. Relative images are named deterministically and copied; failures are classified as missing or unreadable by error; remote ones are never touched. → tests `MarkdownImagesTests/*`
4. Full suite passes.

## Out of scope
- Rendering (T43), the import flow and its summary (T41).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
