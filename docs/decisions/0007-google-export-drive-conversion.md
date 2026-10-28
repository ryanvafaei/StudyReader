# ADR-0007: Google export: GoogleSignIn + Drive Markdown→Docs conversion

- Status: Accepted
- Date: 2026-10-23

## Context
Gemini Notebook auto-syncs Google Docs added from Drive. We need to create and update a Doc with highlights and notes.

## Decision
Sign in with GoogleSignIn-iOS (macOS supported) using only the `drive.file` scope. Render Markdown, upload with Drive `files.create` converting to `application/vnd.google-apps.document`; re-export with `files.update` (full content replace) on the same file ID. Fall back to HTML if `about.importFormats` lacks Markdown.

## Alternatives considered
Docs `batchUpdate` structural edits; hand-written OAuth with AppAuth or PKCE; exporting files for manual upload.

## Consequences
Requires the user's one-time Google Cloud setup (DEPENDENCIES.md §4) and a signed app with a Keychain access group.

## Amendment 2026-10-28: notes in the exported Markdown (user decision, BACKLOG B29, task T87)
Highlight text is neutralised by `ExportMarkdownSafety.neutralise` (T70). Notes are user Markdown (SPEC F-09), so they go in raw with their inline formatting and lists, with these rules (`ExportMarkdownSafety.note(_:headings:)`):
- **Headings are demoted** so a note can't break the export's outline. In a document note (under `### Document note` or `### <title>`), `#`, `##` and `###` become `####`; `####` to `######` stay as they are. In a highlight's `- Note:` item, a heading line becomes `**text**`.
- **A line-start `#` not followed by a space and text is escaped** (`#todo` → `\#todo`), so a tag never becomes a heading in Google Docs. This is the same rule as in the app: `# text` is a heading, `#name` is a tag.
- `<`, `|` and `~` are escaped outside code spans, as for highlight text.
Titles and authors still go in raw. Whether to escape them is undecided (BACKLOG B29).
