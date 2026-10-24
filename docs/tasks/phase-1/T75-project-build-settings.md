# T75: Project build settings (dead-code stripping, string and asset symbols)

- **Phase:** 1 (build housekeeping)
- **Agent:** ui-builder
- **Depends on:** none (may run any time before T31)
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md (Debug `DEAD_CODE_STRIPPING = NO`; signing amendment)
- **Visual check needed:** no

## Goal
Adopt three build settings Xcode recommends: dead-code stripping (Release only, because ADR-0011 keeps it off in Debug so hosted tests can link package symbols), generated Swift symbols for String Catalog keys, and generated Swift symbols for asset catalog colors and images.

## Files to touch
- `project.yml` (modify: `settings.base` only)
- `docs/decisions/0011-build-signing-and-test-hosting.md` (already amended by the architect; don't edit)

## Change
Add these three keys under the top-level `settings.base` in `project.yml`, next to the existing keys:
```yaml
    DEAD_CODE_STRIPPING: YES
    STRING_CATALOG_GENERATE_SYMBOLS: YES
    ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: YES
```
- Keep `settings.configs.Debug.DEAD_CODE_STRIPPING: NO` exactly as it is (ADR-0011). Debug wins over base, so stripping is effectively Release only.
- Change nothing else in `project.yml`: no signing keys (`DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE`), no entitlements, no Info.plist properties, no targets, packages or schemes. Don't touch `scripts/`, `Config/` or `Secrets/`.
- Xcode's "Update to recommended settings" warning about dead-code stripping in Debug is expected and is ignored (ADR-0011). Don't "fix" it.
- If generated string or asset symbols collide with existing Swift names and break the build, report BLOCKED with the compiler error. Don't rename app code in this task.

## Acceptance criteria
1. `project.yml` has the three keys under `settings.base`, and `settings.configs.Debug.DEAD_CODE_STRIPPING: NO` is unchanged. → code review of the diff
2. The diff touches only those three added lines in `project.yml` (plus any `.xcodeproj` regeneration, which is git-ignored). → code review
3. `./scripts/build.sh` passes. → test-runner
4. `./scripts/test.sh` (full suite) passes. → test-runner
5. `./scripts/check-fresh-clone.sh` passes. It only sees committed files, so the implementer leaves the change **uncommitted**; after review approval the orchestrator commits (`T75: Project build settings`) and then has test-runner run the fresh-clone check.

## Out of scope
- Using the generated symbols in app code, signing, entitlements, scripts.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. Three settings added, Debug override intact, 166 tests pass.
