# T25: One shared minimum size for the main window

- **Phase:** 0 (fix from the user's T24 visual check, 2026-10-24)
- **Agent:** ui-builder
- **Depends on:** T24
- **ADRs:** none; ARCHITECTURE §3 (launch)
- **Visual check needed:** yes

## Goal
T24 gave `LaunchView` a 700 × 450 minimum, but `RootView` needs 900 × 600. So the default `LaunchView` preview shows `RootView` in a window that's too narrow: the sidebar gets clipped and the toolbar overflows. (The "Failed" preview is fine.) Define the main window's minimum size once, as 900 × 600, and use that one constant in both `RootView` and `LaunchView` so every state and both previews get the same minimum.

## Files to touch
- `StudyReader/App/MainWindowLayout.swift` (new)
- `StudyReader/App/RootView.swift` (modify: one line)
- `StudyReader/App/LaunchView.swift` (modify: one line)

Read this too, but don't change it: `StudyReader/App/StudyReaderApp.swift` (the `Window` scene with `.defaultSize(width: 1100, height: 720)`).

The new file goes under `StudyReader/`, which `project.yml` already includes as a source folder. `./scripts/build.sh` and `./scripts/test.sh` regenerate the project, so `project.yml` doesn't change.

## Interfaces to produce
`StudyReader/App/MainWindowLayout.swift`, exactly:
```swift
import CoreGraphics

/// Layout constants for the main window, shared by every state of `LaunchView` and by `RootView`.
enum MainWindowLayout {
    /// Smallest width the main window can be resized to, in points.
    static let minWidth: CGFloat = 900
    /// Smallest height the main window can be resized to, in points.
    static let minHeight: CGFloat = 600
}
```
Rules:
- It's a caseless `enum` (a namespace), not a `struct`, and it has no actor annotation. `CGFloat` is `Sendable`, so these `static let` constants are safe under Swift 6 strict concurrency, and you can read them from any isolation. Don't add `@MainActor`, `nonisolated`, or `nonisolated(unsafe)`.
- It goes in `App/`, not `Core/`, because it's UI-only.
- Don't add a `CGSize` property, other constants, or a `View` extension.

`RootView.swift` line 29 changes from `.frame(minWidth: 900, minHeight: 600)` to:
```swift
        .frame(minWidth: MainWindowLayout.minWidth, minHeight: MainWindowLayout.minHeight)
```

`LaunchView.swift` line 22 (on the root `Group`) changes from `.frame(minWidth: 700, minHeight: 450)` to:
```swift
        .frame(minWidth: MainWindowLayout.minWidth, minHeight: MainWindowLayout.minHeight)
```
Leave everything else in both files alone: the `Group` and its three states, `.task { await model.start() }`, both `#Preview`s, every string, and `RootView`'s `NavigationSplitView`, column width, and detail views. Leave the frame where it is in each file (on `Group` in `LaunchView`, on `NavigationSplitView` in `RootView`), and don't add frames anywhere else.

Don't change scene sizing in `StudyReaderApp.swift` (`.defaultSize(width: 1100, height: 720)`, `.windowResizability`, the `Window` declaration). If the window still jumps when it goes from loading to ready, or the default preview still clips the sidebar, and the only fix you can see is a scene change or a different number, don't make that change. Report BLOCKED and describe what you saw.

## Tests
None new. Window and view sizing can't be unit-tested, and a test asserting `minWidth == 900` would only repeat the constant. The visual check covers the behavior. The existing suite, including `StudyReaderTests/AppLaunchModelTests` and `StudyReaderTests/RootModelTests`, must stay green.

## Acceptance criteria
1. `StudyReader/App/MainWindowLayout.swift` matches the "Interfaces to produce" block (a caseless enum with `minWidth = 900` and `minHeight = 600` as `CGFloat`, no actor annotation). → code review of the diff
2. In `RootView.swift` and `LaunchView.swift`, the only change is that the literal frame line became `.frame(minWidth: MainWindowLayout.minWidth, minHeight: MainWindowLayout.minHeight)`. After the change, neither `700`, `450`, `900`, nor `600` appears in either file. → code review of the diff
3. The full suite passes with no new warnings, including no Swift 6 concurrency warnings about `MainWindowLayout`. → test-runner (`./scripts/test.sh`)
4. Visual check (user), Xcode previews: open `StudyReader/App/LaunchView.swift`.
   - Default preview: the canvas is at least 900 × 600 points. "Opening library…" may flash. Then the sidebar is fully visible, with all six section names (Library through Categories, including "Themed Reviews") unclipped,, and the toolbar fits with no overflow (») menu.
   - "Failed" preview: still correct as after T24, but now at least 900 × 600. It shows, centered, the warning triangle, the full title "Couldn't open the library", and the full "The library database is damaged." text with the backup suggestion, with nothing cut off.
5. Visual check (user), real app (Debug run):
   - The window opens at about 1100 × 720. "Opening library…" may flash, centered.
   - The window doesn't jump or resize when the sidebar window appears.
   - Dragging the window smaller stops at 900 × 600, both while the main window is showing and (if you can catch it) during loading.

## Out of scope
- Changing `StudyReaderApp.swift` (scene, `.defaultSize`, resizability).
- Changing any text, the `State` enum, `AppLaunchModel`, `RootModel`, `SidebarItem`, or the previews' factories.
- Changing the minimum's values (they stay 900 × 600) or the sidebar column widths.
- Adding unit tests or XCUITests for sizing.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 154/154, only 3 files changed, no literals left in views. Visual check pending from user.
