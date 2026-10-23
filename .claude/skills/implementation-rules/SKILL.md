---
name: implementation-rules
description: Shared rules every StudyReader implementer agent follows when building a task from docs/tasks/.
---

# Implementation rules

You build exactly one task, described in a spec file under `docs/tasks/`. The main session gives you its path.

## Before coding
1. Read the task spec in full: goal, acceptance criteria, required tests, files to touch, out-of-scope.
2. Read any ADRs the spec links and the ARCHITECTURE.md sections it names. Follow them; don't re-decide them.
3. Read only the files you need. Don't explore the whole codebase.
4. Check your agent memory for patterns and pitfalls you recorded earlier.
5. If the spec is ambiguous or contradicts CLAUDE.md, stop and report the question instead of guessing.

## While coding
- Stay inside the spec's "Files to touch". If you must touch another file, say so in your report.
- Write the tests the spec lists (Swift Testing, `import Testing`) alongside the code.
- Swift 6 strict concurrency: no `@unchecked Sendable`, no `nonisolated(unsafe)`, no force-unwraps on external data, unless the spec allows it.
- No new package dependencies (allowed list: docs/DEPENDENCIES.md §2). No EPUB code. No `#available` checks for macOS below 27.
- New files and targets go through `project.yml` only; never edit `.xcodeproj`.
- Reference repos: read only the `.references/` files the spec or DEPENDENCIES.md §3 lists. Copying >20 lines → keep the license notice and add to THIRD_PARTY_NOTICES.md.
- Inject time (`Now`) and network (`HTTPClient`). Repositories are the only GRDB users; `FileStore` the only path builder.
- No placeholder code, TODO stubs, or commented-out code in what you hand back.

## Before handing back
1. Build: `xcodegen generate --use-cache --quiet && xcodebuild -project StudyReader.xcodeproj -scheme StudyReader -destination 'platform=macOS' build 2>&1 | grep -E "error:|warning: .*(Sendable|isolat)|BUILD (SUCCEEDED|FAILED)"`
2. Run only your task's tests with `-only-testing:` and the same grep plus `passed|failed`.
3. Fix until the build succeeds and your tests pass. Don't hand back broken code.
4. Update your agent memory with anything reusable you learned (patterns, API pitfalls, file locations). Keep it short.

## Report format (your final message)
- **Task:** spec path
- **Status:** DONE or BLOCKED (with the question)
- **Files changed:** list
- **Tests added:** list of test names
- **Build/tests:** result in one line
- **Notes for reviewer:** anything non-obvious, any deviation from the spec and why
- **Visual check needed:** yes/no. If yes, exactly what the user should look at
