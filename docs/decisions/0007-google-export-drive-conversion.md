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
