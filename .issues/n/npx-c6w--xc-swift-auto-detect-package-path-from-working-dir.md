---
# npx-c6w
title: 'xc-swift: auto-detect package_path from working directory'
status: completed
type: feature
priority: high
tags:
    - xc-swift
created_at: 2026-02-22T23:02:56Z
updated_at: 2026-02-22T23:06:08Z
---

## Problem

Every `xc-swift` session starts with a failed tool call because `package_path` is not set:

```
MCP error -32602: Invalid params: package_path is required. Set it with set_session_defaults or pass it directly.
```

This forces an extra `set_session_defaults` round-trip before any useful work can happen. The MCP client (Claude Code) already sets a working directory, and `SessionManager.resolvePackagePath()` has zero auto-detection logic — it only checks the explicit argument and stored session default.

### Observed in

Session 2026-02-22: building xc-mcp itself. First `swift_package_build` call failed, required manual `set_session_defaults` call.

### Expected behavior

When no `package_path` is provided and no session default is set, `resolvePackagePath()` should walk up from `FileManager.default.currentDirectoryPath` looking for `Package.swift`. This matches how `swift build` itself works — it finds the package root from cwd.

### Scope

- `SessionManager.resolvePackagePath(from:)` in `Sources/Core/SessionManager.swift:241-251`
- Same pattern should apply to `resolveProjectPath` and `resolveWorkspacePath` (search for `.xcodeproj` / `.xcworkspace` from cwd)

## Tasks

- [x] Add `findPackageRoot(from:)` helper that walks up directories looking for `Package.swift`
- [x] Fall back to cwd-based detection in `resolvePackagePath` before throwing
- [x] Consider equivalent auto-detection for project/workspace paths
- [x] Add tests for auto-detection (found, not found, nested directories)


## Summary of Changes

Added cwd-based auto-detection to `PathUtility` and `SessionManager`:

- `PathUtility.findAncestorDirectory(matching:startingFrom:)` — generic helper that walks up directories matching a predicate (max 20 levels)
- `PathUtility.findPackageRoot()` — finds nearest `Package.swift`
- `PathUtility.findProjectPath()` — finds nearest `.xcodeproj`
- `PathUtility.findWorkspacePath()` — finds nearest `.xcworkspace` (excludes Pods/hidden)
- `SessionManager.resolvePackagePath()` — falls back to `findPackageRoot()` before throwing
- `SessionManager.resolveBuildPaths()` — falls back to `findWorkspacePath()` then `findProjectPath()` before throwing
- 5 tests in `PathUtilityAncestorSearchTests` (start dir, parent dir, not found, xcodeproj, live repo)
