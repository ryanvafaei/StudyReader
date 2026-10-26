# ADR-0019: UI checks with XCUITest and Peekaboo

- Status: Accepted
- Date: 2026-10-25

## Context
Phase 1 batches visual checks at checkpoints (T52, T63, T69, T74; VISUAL_CHECKS.md). The first checkpoint (T52) was run by hand and took long, and agents couldn't verify UI work themselves ("You can't see the UI"). The user wants Claude Code to run the checkpoint checks itself. Two kinds of check exist: flows with a clear expected result (open a document as a tab, a menu item is disabled, a sheet shows an error) and judgment calls (a cover looks right, a swatch is coloured, a layout jumps).

## Decision
- **XCUITest target `StudyReaderUITests`** (project.yml), in its own scheme `StudyReaderUITests`, so `./scripts/test.sh` stays fast and never takes over the screen. Run with `./scripts/uitest.sh`. Tests launch the app with `-StudyReaderInMemory` and `STUDYREADER_IN_MEMORY` (ADR-0011), seed with Debug > Seed Sample Library, and query existing accessibility labels. Screenshots are attached with `.keepAlways` and exported to `build/ui-screenshots/`.
  - This amends CLAUDE.md "XCUITest only when a flow can't be tested otherwise": every checklist step that has a clear expected result gets an XCUITest. Logic stays in Swift Testing unit tests.
  - Tests that encode a known failure keep the failing assertion until the fix task makes it pass; they are never weakened to pass.
- **Peekaboo MCP** (`@steipete/peekaboo`, pinned to 4.9.2) for the exploratory pass: real mouse drags, Finder Open With, appearance, anything that needs eyes. It is defined inline in the `ui-tester` subagent (`mcpServers`), so only that agent connects to it, and only while it runs. Its `analyze` and `clipboard` tools are denied: screenshots never go to an outside AI provider.
- **`ui-tester` agent** (Sonnet, effort high) runs a checkpoint: LaunchServices check, build, XCUITests, Peekaboo pass on `./scripts/run-app.sh` (in-memory library), report in `docs/checkpoints/<checkpoint>.md`. It never edits code. The user only answers items it marks NEEDS HUMAN.
- **LaunchServices hygiene.** `./scripts/lsregister-clean.sh` keeps only `build/DerivedData`'s StudyReader.app registered; `check-fresh-clone.sh` unregisters its clone's app after building. At T52 a stale fresh-clone build (pre-T47) was what Finder's Open With launched as a second instance.

## Alternatives considered
Built-in computer use from a chat (slow, pixel-based, terminals and IDEs are click-only, and it can't run inside Claude Code's loop); XcodeBuildMCP (its UI automation targets iOS simulators, not macOS apps); Xcode's own MCP (`xcrun mcpbridge`: builds, tests and previews, but it doesn't drive a running app).

## Consequences
- UI tests and the Peekaboo pass take over the screen; the user shouldn't use the Mac while a checkpoint runs.
- One-time setup by the user: grant Screen Recording and Accessibility to the terminal app that runs Claude Code (Peekaboo), allow Xcode's UI-testing automation prompt on the first `uitest.sh` run, and allow the Automation prompt when `run-app.sh` quits StudyReader. Node 22+ must be on the PATH Claude Code sees (`npx`).
- UI tests run the app under the same bundle ID as the user's copy, so window frames and other AppKit defaults saved by the app can change. The library itself is never touched.
