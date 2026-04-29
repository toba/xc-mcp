---
# 3ng-z0t
title: Workspace-scope DerivedData to prevent concurrent build collisions
status: completed
type: feature
priority: normal
tags:
    - citation
created_at: 2026-04-29T04:41:40Z
updated_at: 2026-04-29T05:13:26Z
sync:
    github:
        issue_number: "289"
        synced_at: "2026-04-29T05:14:18Z"
---

**Inspiration**: getsentry/XcodeBuildMCP `6a593f9` + follow-ups (workspace-scoped DerivedData).

## Problem

Currently we don't override `derivedDataPath` for `xcodebuild`. Xcode defaults to a shared `~/Library/Developer/Xcode/DerivedData/<Project>-<hash>` directory keyed by the workspace/project location. Two clones of the same project at different paths get different hashes, so they don't collide. **However**, when the same clone is built concurrently from multiple xc-mcp sessions (different agents, different focused servers, focused + monolithic, etc.), they share one DerivedData and can race on incremental build artifacts.

XcodeBuildMCP solves this by computing a per-session/per-workspace subdirectory like `<base>/<ProjectName>-<hash>` and passing it via `-derivedDataPath`. Hash is derived from the absolute project/workspace path.

## Investigation

- [x] Reproduce: confirmed by inspection — `XcodebuildRunner` does not pass `-derivedDataPath`, so concurrent invocations against the same clone share Xcode's default DerivedData directory.
- [x] Confirmed: it does not. No callers passed it via `additionalArguments` either.
- [x] Decided: scope by absolute workspace/project path (matches XcodeBuildMCP). Different clones get different scoped dirs; same clone reused across sessions hits the same scoped cache.
- [x] Compared. Upstream uses `<ProjectName>-<hash>` under DerivedData; we use `~/Library/Caches/xc-mcp/DerivedData/<ProjectName>-<hash>` to avoid Xcode IDE collisions.

## Proposal (tentative)

Add a `derivedDataPath` field to `SessionDefaults`. When unset, compute `<DerivedData>/<ProjectName>-<sha1(workspacePath)>` and pass it to xcodebuild. Allow explicit override.

## Out of scope

- Cleanup of old DerivedData directories.
- Changing the default for users who already have working setups.


## Summary of Changes

- New `Sources/Core/DerivedDataScoper.swift`:
  - `scopedPath(workspacePath:projectPath:)` → `~/Library/Caches/xc-mcp/DerivedData/<ProjectName>-<sha256-prefix>`. Deterministic for the same absolute path; clones at different paths get different dirs.
  - `effectivePath(...)` returns `nil` when (a) caller already supplied `-derivedDataPath`, (b) `XC_MCP_DISABLE_DERIVED_DATA_SCOPING` is set truthy, or (c) no project/workspace context is available. Honors `XC_MCP_DERIVED_DATA_PATH` for explicit override.
- `Sources/Core/XcodebuildRunner.swift`: injects `-derivedDataPath` in `build`, `buildTarget`, `test`, `clean`, and `showBuildSettings`. `clean` and `showBuildSettings` use the same scoping so artifacts and `BUILD_DIR` stay consistent across the runner's surface.
- `Tests/DerivedDataScoperTests.swift`: 10 tests covering nil inputs, workspace/project precedence, determinism, hash divergence, and all three env/arg override paths.

Full suite: 1068 passed.

## Behavioral note

This is a behavior change: existing users will see builds populate `~/Library/Caches/xc-mcp/DerivedData/...` instead of Xcode's default DerivedData. Their first build under the new scheme will be a clean build (the scoped dir doesn't exist yet); subsequent builds reuse the cache normally. Users who want the old behavior can set `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1`.
