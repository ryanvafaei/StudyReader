# T24: Give LaunchView a minimum size

- **Phase:** 0 (fix from the user's T23 visual check, 2026-10-24)
- **Agent:** ui-builder
- **Depends on:** T23
- **ADRs:** none; ARCHITECTURE §3 (launch)
- **Visual check needed:** yes

> **Superseded value (2026-10-24):** The user's T24 visual check found that 700 × 450 is too small for the default preview, which renders `RootView` and clips its sidebar. [T25](T25-shared-main-window-minimum-size.md) replaces both literals with the shared `MainWindowLayout.minWidth`/`minHeight` (900 × 600). The text below records T24 as it was shipped.

## Goal
`LaunchView` has no frame, so its loading and failed states, and both of its previews (default and "Failed"), render in a tiny window. The "Failed" preview shows only a truncated "Couldn't open" with no icon or description. Give the view's root a minimum size so every state fills a normal window and the failure message wraps and is fully visible, centered.

## Files to touch
- `StudyReader/App/LaunchView.swift` (modify)

Read these too, but don't change them: `StudyReader/App/StudyReaderApp.swift` (the `Window` scene with `.defaultSize(width: 1100, height: 720)`) and `StudyReader/App/RootView.swift` (it has `.frame(minWidth: 900, minHeight: 600)`).

## Interfaces to produce
None. The change is layout only. `LaunchView` keeps `let model: AppLaunchModel`, its three states, the `.task { await model.start() }` call, and both previews unchanged.

The `body` shape after the change:
```swift
var body: some View {
    Group {
        switch model.state {
        case .loading:
            ProgressView("Opening library…")
        case .ready(let environment):
            RootView(environment: environment)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't open the library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        }
    }
    .frame(minWidth: 700, minHeight: 450)
    .task { await model.start() }
}
```
Rules:
- Put `.frame(minWidth: 700, minHeight: 450)` on the `Group` (the view's root), so it applies to all three states. Don't add frames to the individual cases.
- `ContentUnavailableView` already centers its content and wraps its description once it has room. Don't add extra `.multilineTextAlignment`, `.fixedSize`, or padding unless the visual check shows the message is still truncated. If you do add one, say which and why in your report.
- In the `.ready` state, `RootView`'s own `minWidth: 900, minHeight: 600` is larger than the launch minimum, so it still decides the main window's minimum size. Don't change it.
- Keep every user-facing string exactly as it is ("Opening library…", "Couldn't open the library", the `message` text). No new `Localizable.xcstrings` entries.
- Don't change the window scene sizing (`.defaultSize`, `.windowResizability`, or the `Window` declaration) in `StudyReaderApp.swift`. If the launch window and the main window still visibly fight (the window jumps or snaps to a different size when the state changes from loading to ready) and the only fix is a scene change, don't make it: report BLOCKED and describe what you saw.

## Tests
None new. Window and view sizing can't be checked by a unit test, and adding an XCUITest for this isn't worth it (CLAUDE.md: XCUITest only when a flow can't be tested otherwise, and a visual check covers this). The existing suite, including `StudyReaderTests/AppLaunchModelTests`, must stay green.

## Acceptance criteria
1. `LaunchView`'s root `Group` has `.frame(minWidth: 700, minHeight: 450)`, and nothing else in the file changed except that line (plus any wrapping modifier the report names and justifies, per the rules above). → code review of the diff
2. The full suite passes with no new warnings. → test-runner (`./scripts/test.sh`)
3. Visual check (user), Xcode previews: open `StudyReader/App/LaunchView.swift`.
   - Default preview: a canvas at least 700 × 450 points. The spinner with "Opening library…" may flash, then the sidebar window appears.
   - "Failed" preview: a canvas at least 700 × 450 points showing, centered, the warning triangle icon, the full title "Couldn't open the library" (not truncated), and below it "The library database is damaged." plus the backup suggestion, wrapped onto several lines if needed, with no text cut off.
4. Visual check (user), real app: run the app (Debug).
   - The window opens at its normal size (about 1100 × 720), not tiny. "Opening library…" may flash, centered.
   - When the main window with the sidebar appears, the window doesn't jump or resize.
   - Dragging the window smaller stops at the main window's minimum (900 × 600), as before T24.

## Out of scope
- Changing texts, the `State` enum, `AppLaunchModel`, or the previews' factories.
- Changing `StudyReaderApp.swift` scene sizing or `RootView.swift`.
- Retry or reset buttons on the failed state.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 154/154, diff is the single frame line. Visual check pending from user.
