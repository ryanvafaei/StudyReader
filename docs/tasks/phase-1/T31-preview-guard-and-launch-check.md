# T31: Guard Xcode Previews and confirm a normal launch opens the real library

- **Phase:** 1 (backlog T27-F1)
- **Agent:** ui-builder
- **Depends on:** none
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md (amendment "Phase 1 planning, backlog T27-F1")
- **Visual check needed:** yes (Console check and a preview, steps below)

## Goal
Backlog T27-F1: nobody has verified that a normal launch doesn't pick the in-memory library, and Xcode Previews aren't guarded. Add a fourth test-host signal for Xcode Previews so a preview process never opens the user's library, then have the user confirm the normal-launch behaviour in Console before import work starts.

## Files to touch
- `StudyReader/App/AppEnvironment.swift` (modify)
- `StudyReader/App/AppLaunchModel.swift` (modify: log line only)
- `StudyReaderTests/AppTests/AppEnvironmentTests.swift` (modify: add tests)
- `docs/bugs/backlog.md` (modify: after the user's check, remove the T27-F1 entry and its section, noting "resolved by T31")

## Interfaces to produce
In `AppEnvironment`:
```swift
/// Environment variable Xcode sets in preview processes (ADR-0011 amendment, T31).
static let previewsEnvironmentVariable = "XCODE_RUNNING_FOR_PREVIEWS"

struct TestHostSignals: Sendable, Equatable {
    var xctestEnvironment: Bool
    var inMemoryRequested: Bool
    var xctestLibraryLoaded: Bool
    /// environment[previewsEnvironmentVariable] == "1".
    var runningForPreviews: Bool = false          // default keeps existing call sites compiling

    var usesInMemoryLibrary: Bool {
        xctestEnvironment || inMemoryRequested || xctestLibraryLoaded || runningForPreviews
    }
}
```
- `testHostSignals(environment:arguments:imagePaths:)` sets `runningForPreviews: environment[previewsEnvironmentVariable] == "1"`.
- `AppLaunchModel.chooseEnvironment` log line adds `runningForPreviews: \(signals.runningForPreviews, privacy: .public)`. Nothing else changes in `AppLaunchModel`.
- Update the doc comment on `TestHostSignals` ("Independent signals… Any one of them selects the in-memory library") to mention previews.

## Tests (`AppEnvironmentTests`)
- `previewsSelectInMemoryLibrary`: `testHostSignals(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"], arguments: [], imagePaths: [])` has `runningForPreviews == true` and `usesInMemoryLibrary == true`.
- `previewsVariableMustBeOne`: with value `"0"` and with the variable absent, `runningForPreviews == false`; with no other signal, `usesInMemoryLibrary == false`.
- `chooseEnvironmentUsesInMemoryForPreviews`: `AppLaunchModel.chooseEnvironment(for: TestHostSignals(xctestEnvironment: false, inMemoryRequested: false, xctestLibraryLoaded: false, runningForPreviews: true), live: { Issue.record("live called"); throw CancellationError() }, inMemory: { try AppEnvironment.inMemory() })` returns without calling `live` (remove the returned env's folder with `TestFileStore.remove(env.fileStore)`).

All existing `AppEnvironmentTests` and `AppLaunchModelTests` pass unchanged.

## Acceptance criteria
1. A preview process selects the in-memory library. → tests `AppEnvironmentTests/previewsSelectInMemoryLibrary`, `AppEnvironmentTests/chooseEnvironmentUsesInMemoryForPreviews`
2. Only the value `1` counts. → test `AppEnvironmentTests/previewsVariableMustBeOne`
3. Visual check (user), step 1: build and run the app from Xcode (Run, not Test). Open Console.app, filter on subsystem `com.ryanvafaei.StudyReader`, category `app`. There's no line "Using the in-memory library", and the main window shows the sidebar (the real library opened).
4. Visual check (user), step 2: open `StudyReader/App/LaunchView.swift` in Xcode and show the canvas. The default preview renders the main window. If Console shows lines from the preview process, any "Using the in-memory library" line has `runningForPreviews: true`, or another signal set.
5. After the user confirms 3 and 4, T27-F1 is removed from `docs/bugs/backlog.md` ("resolved by T31"). If step 3 fails, stop and report: the real library isn't being opened on a normal launch.

## Out of scope
- Changing the other three signals, the test action in `project.yml`, or `chooseEnvironment`'s logic.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. User confirmed manual launch check (no in-memory log on Run, Preview renders main window). 169 tests pass; T27-F1 resolved.
