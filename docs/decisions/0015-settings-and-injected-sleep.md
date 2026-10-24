# ADR-0015: Settings storage and injected sleeping

- Status: Accepted
- Date: 2026-10-24 (Phase 1 planning)

## Context
Phase 1 needs per-Mac preferences (default import category, auto-highlight, current color, color labels, PDF inversion, Google export folder, library layout and sort). Tests must never touch the user's preferences, and the UI must update live when a setting changes. Autosave (500 ms), position saves, export backoff and keep-in-sync (60 s) all wait for time to pass, and tests can't wait in real time.

## Decision
- Preferences live in `UserDefaults`, not in the database. They describe this Mac, not the library, and adding a table would need a migration.
- `SettingsStore` (`Core/Support/SettingsStore.swift`) is a `Sendable` struct over one `UserDefaults` instance, with typed properties (`nonmutating set`) and keys prefixed `settings.`. It's the only code that reads or writes these keys.
- `AppEnvironment.settingsStore`: `live()` uses `UserDefaults.standard`; `inMemory()` and the default initializer argument use the suite `com.ryanvafaei.StudyReader.Ephemeral`. Tests that check settings make their own suite (`TestSettings.make()` / `TestSettings.remove(_:)`).
- `AppSettings` (`@MainActor @Observable`) mirrors the store for SwiftUI and writes through on every change. Exactly one instance exists per app, owned by `AppSession`, which `AppLaunchModel` creates when the library is ready. Views and models never use `@AppStorage`.
- `Sleeper` protocol (`func sleep(for: Duration) async throws`): logic waits only through an injected `Sleeper` (`SystemSleeper` in the app, `ImmediateSleeper` / `ManualSleeper` in tests). Never call `Task.sleep` in logic. `AppEnvironment.sleeper` carries it.
- `Debouncer` (actor) runs only the last scheduled action after its delay, using a generation counter, and has `flush()` (run the pending action now) and `cancel()`.

## Alternatives considered
- A `setting` table in SQLite: needs migration `v3` and couples Mac preferences to the library file.
- `@AppStorage` in views: untestable, scattered keys, and it writes to the real defaults from the test host.
- Swift `Clock` injection: needs a hand-written test clock with the same effort and less clarity than a one-method protocol.

## Consequences
- Settings are not part of the library backup; acceptable for a single-Mac app.
- Every waiting component takes a `Sleeper`, so its tests run instantly and deterministically.
