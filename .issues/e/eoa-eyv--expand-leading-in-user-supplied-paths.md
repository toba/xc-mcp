---
# eoa-eyv
title: Expand leading ~ in user-supplied paths
status: completed
type: bug
priority: normal
tags:
    - citation
created_at: 2026-04-29T04:41:40Z
updated_at: 2026-04-29T04:48:29Z
sync:
    github:
        issue_number: "292"
        synced_at: "2026-04-29T05:14:18Z"
---

**Inspiration**: getsentry/XcodeBuildMCP `77c206a` (`fix(config): expand leading ~ in config paths`).

## Problem

`Sources/Core/PathUtility.swift` and `SessionManager.swift` do not expand leading `~` in user-supplied paths. If a caller passes `~/Developer/MyApp.xcodeproj` (a common pattern for human-readable paths), `URL(fileURLWithPath:)` treats it as literal — `~` becomes a directory under the current working directory and the file isn't found.

Repro:
```
set_session_defaults(project_path: "~/Developer/foo.xcodeproj")
# Resolved to: <cwd>/~/Developer/foo.xcodeproj
```

## Proposal

Add a small helper in `PathUtility` that expands a leading `~` (bare or `~/...`) to `NSHomeDirectory()` before resolution. Apply it in:

- `PathUtility.resolvePath(from:)`
- `SessionManager.set(...)` for `projectPath`, `workspacePath`, `packagePath`.

```swift
static func expandTilde(_ path: String) -> String {
    guard path.hasPrefix("~") else { return path }
    if path == "~" { return NSHomeDirectory() }
    if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst(1)) }
    return path  // ~user/... — leave as-is, not supported
}
```

## Tests

- `~` alone → `$HOME`
- `~/foo` → `$HOME/foo`
- `/absolute/path` → unchanged
- `relative/path` → unchanged
- `~user/foo` → unchanged (rare, not supported)


## Summary of Changes

- `Sources/Core/PathUtility.swift`: added `expandTilde(_:)` static helper. Applied in instance `resolvePathURL(from:)` and the static legacy variant.
- `Sources/Core/SessionManager.swift`: applied `PathUtility.expandTilde` to `projectPath` / `workspacePath` / `packagePath` in `setDefaults`, and to the per-call `project_path`/`workspace_path`/`package_path` arguments in `resolveBuildPaths` and `resolvePackagePath`.
- `Tests/PathUtilityTests.swift`: 6 new tests covering `~`, `~/`, absolute, relative, `~user/` (unchanged), and end-to-end `resolvePath` expansion.

All 17 PathUtilityTests pass.
