# T95: One link filter for every clickable link from imported Markdown and notes

- **Phase:** 1 (bug hunt `docs/bugs/phase-1.md` M5; SPEC F-03 "links" as amended 2026-10-28)
- **Agent:** pdf-engine. Why: the owner of the Markdown renderer (`MarkdownRenderer`, T43), the reader's link filter (`TextReaderView.clicked(onLink:at:)`, T55/T60) and rich-text extraction (`RichTextMarkdown`, T58) is pdf-engine. The SwiftUI side is one modifier in two small views (`RichTextView`, `NoteMarkdownView`), spelled out below.
- **Escalation (CLAUDE.md):** Sonnet agent. 1st rejection → same agent, effort `high`, with the spec and the review report. 2nd rejection → stop and ask the user. Reviews after an escalation run code-reviewer with effort `high`.
- **Depends on:** T94 (order only)
- **ADRs:** ADR-0005 (text rendering)
- **Visual check needed:** yes (Mac row "T95" in VISUAL_CHECKS.md "Needs a Mac", added by the orchestrator from the report; the bug hunt's "click the smb/file link in the popover" check)
- **UI tests:** none. Verify with `./scripts/build.sh` and unit-test filters only.

## Goal
The Markdown reader opens only `http`, `https` and `mailto` links (`TextReaderView.openableLinkSchemes` + `isOpenable`). A highlight copies a link into `richText`, and a note can contain any link; both are shown as SwiftUI `Text` with links in the highlight popover, the reader's Highlights panel, the Highlights browser rows and detail pane, and note previews (`NoteMarkdownView`). There, SwiftUI's default `openURL` opens any scheme (`file:`, `smb:`, app schemes). Move the one existing filter to a neutral place and apply it on every path.

## Files to touch
- `StudyReader/Core/Support/LinkPolicy.swift` (new: the filter, moved from `TextReaderView`)
- `StudyReader/Features/Reader/Text/TextReaderView.swift` (modify: `clicked(onLink:at:)` uses `LinkPolicy`; remove `openableLinkSchemes` and `isOpenable`, keep `url(forLink:)`)
- `StudyReader/Features/Annotations/RichTextView.swift` (modify: one modifier on the view's body)
- `StudyReader/Features/Annotations/NoteMarkdown.swift` (modify: one modifier on `NoteMarkdownView.body`)
- `StudyReader/Features/Annotations/LinkPolicy+SwiftUI.swift` (new: the `View` modifier; `Core/Support` stays free of SwiftUI)
- `StudyReaderTests/CoreTests/LinkPolicyTests.swift` (new); `StudyReaderTests/ReaderTests/TextReaderControllerTests.swift` (modify: the two `TextReaderView.isOpenable` calls become `LinkPolicy.isOpenable`)
- You may touch other files if the diagnosis requires it; list each one and the reason in the report.

## Interfaces to produce
```swift
/// The app's only link-scheme filter (SPEC F-03): links from imported documents and notes open outside the app only
/// for these schemes; every other link does nothing.
enum LinkPolicy {
    static let openableSchemes: Set<String> = ["http", "https", "mailto"]
    /// Case-insensitive scheme check; false when the URL has no scheme.
    static func isOpenable(_ url: URL) -> Bool
}

extension View {
    /// Routes every link click inside this view through `LinkPolicy`: openable → `.systemAction`, else `.discarded`.
    func studyReaderLinkPolicy() -> some View   // .environment(\.openURL, OpenURLAction { … })
}
```

## What to do
1. Create `LinkPolicy` with exactly the current behaviour of `TextReaderView.isOpenable` (lowercased scheme in the set). Make `TextReaderView.clicked(onLink:at:)` call `LinkPolicy.isOpenable`. No behaviour change in the reader.
2. Add `studyReaderLinkPolicy()` and apply it inside `RichTextView.body` (both branches, e.g. on a `Group`) and inside `NoteMarkdownView.body`. Applying it inside these two views covers all current uses (`HighlightPopoverView`, `HighlightDetailView`, `HighlightsBrowserView`, `HighlightsPanelView`, the Notes tab preview and every note preview) and any future use; don't add it at the call sites.
3. Grep the app target for other places that open a URL taken from document or note content (`NSWorkspace.shared.open`, `openURL`, `Link(`, `.link =`, `AttributedString(markdown:`). Today the others are app-built URLs (Google Doc links in `ExportSheet.swift` and `GoogleSettingsView.swift`, and T92b's Drive folder link): leave those; list what you found in the report.
4. Stored `richText` and notes are not changed (the link text and destination stay as written; only clicking is filtered).

## Acceptance criteria
1. `LinkPolicyTests/onlyWebAndMailLinksOpen`: true for `https://example.com`, `http://example.com`, `HTTPS://EXAMPLE.COM`, `mailto:a@example.com`; false for `file:///System/Applications/Calculator.app`, `javascript:alert(1)`, `smb://example.invalid/share`, `studyreader-custom://x`, `x-apple.systempreferences:`, `ftp://example.com`, and a URL without a scheme (`URL(string: "relative/path")`).
2. `LinkPolicyTests/schemesMatchTheReader`: `LinkPolicy.openableSchemes == ["http", "https", "mailto"]`.
3. Reviewer check: `TextReaderView` has no own scheme list; `RichTextView` and `NoteMarkdownView` apply `studyReaderLinkPolicy()` in their bodies; the `OpenURLAction` returns `.systemAction` only when `LinkPolicy.isOpenable` is true, else `.discarded`; no call site was changed instead.
4. Existing `MarkdownRendererTests`, `RichTextTests`, `NotePreviewTests` and `TextReaderControllerTests` pass; the only test change outside `LinkPolicyTests` is `TextReaderControllerTests.swift` lines ~258/261: `TextReaderView.isOpenable` → `LinkPolicy.isOpenable`.
5. `./scripts/test.sh StudyReaderTests/LinkPolicyTests StudyReaderTests/RichTextTests StudyReaderTests/NotePreviewTests StudyReaderTests/MarkdownRendererTests StudyReaderTests/TextReaderControllerTests` passes; `./scripts/build.sh` succeeds.
6. Visual check (Mac, row "T95"): import a `.md` file with `[slides](smb://example.invalid/share)`, `[calc](file:///System/Applications/Calculator.app)` and `[web](https://example.com)`; highlight the sentence; in the popover, the Highlights panel row, the Highlights browser row and detail pane, clicking the smb and file links does nothing and the web link opens the browser; the same three links typed into a note behave the same in the Notes tab preview.

## Out of scope
- B8 (the reader's context-menu "Open Link", a Mac check), removing links from stored rich text, any styling change of links.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
