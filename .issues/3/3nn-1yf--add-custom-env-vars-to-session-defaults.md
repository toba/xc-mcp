---
# 3nn-1yf
title: Add custom env vars to session defaults
status: completed
type: feature
priority: normal
created_at: 2026-02-27T17:41:04Z
updated_at: 2026-02-27T18:01:07Z
sync:
    github:
        issue_number: "148"
        synced_at: "2026-02-27T18:13:36Z"
---

Allow users to set custom environment variables in session defaults that get merged into build/run/test commands.

Inspired by getsentry/XcodeBuildMCP's implementation (7356c4c, fc5a184) which supports persistent custom env vars with deep merge semantics.

## Tasks

- [x] Add `env: [String: String]` field to session defaults
- [x] Support `set_session_defaults(env: {...})` with deep merge (new keys add, existing keys update)
- [x] Pass session env vars through to xcodebuild, swift, and launch commands
- [x] `clear_session_defaults` resets env along with everything else
- [x] Add tests

## Use cases

- Setting `DYLD_` vars for debugging
- Custom build flags via env (e.g. `ENABLE_FEATURE_X=1`)
- CI-specific env passthrough

## References

- getsentry/XcodeBuildMCP@7356c4c (initial impl)
- getsentry/XcodeBuildMCP@fc5a184 (hardened store + schema validation)


## Summary of Changes

Added `env: [String: String]?` to `SessionDefaults` and `SessionManager` with deep-merge semantics. Added `resolveEnvironment(from:)` to merge session env with per-invocation env (per-invocation wins). Threaded environment through `XcodebuildRunner` (both `run()` overloads, `build()`, `buildTarget()`, `test()`) and `SwiftRunner` (`build()`, `runExecutable()`). Updated 13 tools to resolve and pass environment: BuildMacOS, TestMacOS, BuildRunMacOS, BuildSim, BuildRunSim, TestSim, BuildDevice, TestDevice, SwiftPackageBuild, SwiftPackageTest, SwiftPackageRun, BuildDebugMacOS, and SetSessionDefaults. Added 6 new tests covering persistence, deep-merge, clear, resolveEnvironment merging, empty state, and summary output.
