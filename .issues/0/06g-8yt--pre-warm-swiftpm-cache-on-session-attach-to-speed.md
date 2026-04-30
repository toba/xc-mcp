---
# 06g-8yt
title: Pre-warm SwiftPM cache on session attach to speed up first swift_package_test
status: completed
type: feature
priority: normal
created_at: 2026-04-30T15:56:24Z
updated_at: 2026-04-30T16:09:19Z
blocked_by:
    - tc2-9jv
sync:
    github:
        issue_number: "296"
        synced_at: "2026-04-30T16:11:24Z"
---

Spawn a background `swift build --build-tests` (or just `swift package resolve` + `swift build`) when a Swift package is first registered with the session (or first touched by any swift_package_* tool). The first user-driven `swift_package_test` would then hit a warm cache and complete in seconds instead of the 5-15 minute cold compile of swift-syntax-heavy graphs.

## Design notes

- Track per-package warm state in `SessionManager` (or a dedicated `PackageWarmupManager`).
- Trigger on `set_session_defaults` when `package_path` is set, and on first `resolvePackagePath` call for a package not yet seen.
- Use a detached task; surface progress/errors via session diagnostics, not via the user-facing tool result.
- Skip if `isColdCache` returns false (already warm).
- Cancel in-flight warmup if the user kicks off their own build/test for the same package — the user task will reuse the artifacts SwiftPM has already produced, and racing two `swift build` invocations on the same `.build` is unsafe.

Follow-up to tc2-9jv (timeout fix only addressed the symptom).



## Summary of Changes

- `SessionManager` (actor) gains `WarmupState`, `warmupTasks`, `warmupStatus`, `warmedPackages`, an injectable `warmupRunner` (defaulting to `swift build --build-tests` at `coldCacheTimeout`), and an `enableWarmup` init flag.
- `setDefaults` schedules a background `Task.detached(priority: .background)` warmup for the active package when the cache is cold, `Package.swift` exists, no warmup is already running, and `XC_MCP_DISABLE_WARMUP` isn't set.
- New `cancelWarmupIfRunning(packagePath:)` cancels and awaits the warmup task so the BuildGuard flock is released before the user's command runs. Wired into `SwiftPackageBuildTool`, `SwiftPackageTestTool`, `SwiftPackageRunTool`, `SwiftPackageCleanTool`.
- `clear()` cancels all in-flight warmups and drops state.
- `summary()` reports per-package `Warmup: running|warmed|cancelled|failed` so `show_session_defaults` reflects status.
- 7 new tests in `SessionManagerWarmupTests` cover: completion path, env-disabled skip, dedupe across repeat `setDefaults`, cancellation, no-op cancel, missing-Package.swift skip, summary surfaces state. Existing 13 `SessionManagerPersistenceTests` still pass.

## Follow-ups filed

- `qps-3nm` — stream swift build/test progress to MCP client
- `sv3-s84` — investigate swift-syntax compile speedups
- `a68-g9s` — share built artifacts across packages via shared `.build`
