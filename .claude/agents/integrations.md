---
name: integrations
description: Implements external and on-device AI integrations - Google sign-in and Google Docs export for Gemini Notebook (GoogleSignIn + Drive API), keep-in-sync scheduler, on-device embeddings for Find Similar Highlights, Apple Intelligence Mastery suggestions. Use for tasks assigned to integrations in docs/tasks/.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
memory: project
skills:
  - implementation-rules
color: orange
---

You implement integration tasks for StudyReader. Follow the preloaded implementation-rules skill exactly.

Design sources: `docs/ARCHITECTURE.md` §9 (export), §11 (similarity), §12 (suggestions); ADR-0007, 0008, 0010; SPEC F-14, F-16, F-21.

## Google Docs export
- Auth with the `GoogleSignIn` package (`GIDSignIn.sharedInstance`, `presentingWindow:` on macOS), scope `https://www.googleapis.com/auth/drive.file` only. Refresh tokens before each request (`refreshTokensIfNeeded`).
- Client ID comes from `GIDClientID` in Info.plist, set from the `GOOGLE_CLIENT_ID` build setting in `Secrets/Google.xcconfig`. You can't read `Secrets/`. If it's missing at runtime, show "Google export not configured" and point to DEPENDENCIES.md §4.
- `ExportRenderer` is pure and produces the exact Markdown in ARCHITECTURE §9.1; test with golden files.
- Upload with URLSession through an injected `HTTPClient`: multipart create converting to `application/vnd.google-apps.document`; multipart PATCH update on the same file ID (replaces content). Check `about.importFormats` once and fall back to HTML via swift-markdown `HTMLFormatter`.
- Handle 401 (refresh once, then ask to sign in), 403/404 on update (offer new Doc), 429/5xx (backoff 1s/4s/16s), offline (queue, retry on `NWPathMonitor` change).
- Never log or persist tokens, auth codes, emails, or document contents outside Keychain/GoogleSignIn. Tests never hit real Google endpoints.

## Find Similar Highlights
- `NLEmbedding.sentenceEmbedding(for:)` per language detected with `NLLanguageRecognizer`; skip languages without a model. Store Float32 vectors with model ID and source hash; recompute when stale.
- Brute-force cosine, exclude self, threshold 0.55, top 5, in-memory cache invalidated on change.

## Mastery suggestions
- FoundationModels: gate on `SystemLanguageModel.default.availability == .available`; guided generation with a `@Generable` suggestion type; input truncated to 1,500 characters; never save without user confirmation; handle `LanguageModelError`. Reference: `.references/annotate/Sources/AnnotateCore/DocumentAssistantLanguageModel.swift`.
