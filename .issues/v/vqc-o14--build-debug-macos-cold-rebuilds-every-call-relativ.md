---
# vqc-o14
title: 'build_debug_macos cold-rebuilds every call: relative project path makes scoped DerivedData root unstable'
status: completed
type: bug
priority: high
created_at: 2026-05-25T20:24:06Z
updated_at: 2026-05-25T20:27:49Z
sync:
    github:
        issue_number: "338"
        synced_at: "2026-05-25T20:30:27Z"
---

## Problem

`build_debug_macos` (and other build tools using `DerivedDataScoper`) performed a **full cold rebuild on every invocation within a single session**, even with unchanged sources and identical session defaults (`project_path: "Thesis.xcodeproj"`, `scheme: "Standard"`). Observed scoped DerivedData roots across consecutive builds:

- 1st build → `~/Library/Caches/xc-mcp/DerivedData/Thesis-4019ecb6511d`
- 2nd build → `~/Library/Caches/xc-mcp/DerivedData/jason-67aaf8852074`

Different root ⇒ no warm cache ⇒ minutes-long cold build each time. From the user's side this is indistinguishable from a hang.

## Root cause

`DerivedDataScoper.scopedPath` (Sources/Core/DerivedDataScoper.swift:56-68) hashes the project path via:

```swift
let absolute = URL(fileURLWithPath: source).standardized.path
let projectName = URL(fileURLWithPath: absolute).deletingPathExtension().lastPathComponent
let hash = shortHash(of: absolute)
```

When `source` is a **relative** path (as stored by `set_session_defaults` here: `"Thesis.xcodeproj"`), `URL(fileURLWithPath:)` resolves it against the **server process's current working directory**. That cwd is not stable — it differs between the xc-build and xc-debug servers and can be mutated by other tool calls — so the same logical project yields different absolute paths, different hashes, and different scoped roots. The bogus `jason-67aaf8852074` (project name "jason") is a relative path resolving against `/Users/jason`.

## Impact

- Repeated multi-minute cold builds; defeats the whole point of scoping (cache reuse).
- Stale/duplicate DerivedData trees accumulate under `~/Library/Caches/xc-mcp/DerivedData`.

## Suggested fix

Normalize the project/workspace path to a stable absolute path **before** hashing — independent of process cwd. Options:
1. In `set_session_defaults`, resolve `project_path`/`workspace_path` to absolute (against the discovered project root) and store the absolute form.
2. In `DerivedDataScoper.scopedPath`, reject or resolve relative inputs against a known base (the located project root) rather than cwd; or refuse to scope (and log) when given a relative path so the bug is loud rather than silent.
3. Add a regression test: relative vs absolute inputs for the same project must produce the same scoped path.

## Repro

1. `set_session_defaults project_path: "Thesis.xcodeproj"` (relative)
2. `build_debug_macos` twice in a session where server cwd changes between calls
3. Observe two different `~/Library/Caches/xc-mcp/DerivedData/<name>-<hash>` roots and a cold rebuild on the second call.


## Summary of Changes

Fixed at the resolution chokepoints in `SessionManager` so the path handed to `DerivedDataScoper` is always a stable absolute path, independent of the server process's cwd:

- `setDefaults` now stores `project_path`/`workspace_path`/`package_path` via `PathUtility.resolvePath` (absolute, idempotent) instead of `expandTilde`, so a relative input like `Thesis.xcodeproj` is persisted absolute at the moment the user supplies it.
- `resolveBuildPaths` resolves both per-invocation args and session-stored values to absolute (normalizing any legacy relative paths persisted before this fix). Idempotent for already-absolute paths.
- `resolvePackagePath` upgraded to the same absolute resolution.

Result: the same logical project hashes to the same `~/Library/Caches/xc-mcp/DerivedData/<name>-<hash>` root across calls → warm cache reuse, no more cold rebuild every invocation, and no bogus `jason-<hash>` roots.

Added regression tests in `SessionManagerPersistenceTests`: a relative `project_path` is stored absolute, and `resolveBuildPaths` returns a stable path after cwd drifts.
