---
# tc2-9jv
title: swift_package_test first-run timeout
status: completed
type: bug
priority: normal
created_at: 2026-04-30T15:46:52Z
updated_at: 2026-04-30T15:56:13Z
sync:
    github:
        issue_number: "295"
        synced_at: "2026-04-30T16:11:24Z"
---

First swift_package_test call on a swift-syntax-heavy package times out at default 300s with a generic 'Process timed out' error; second call (warm cache) completes in <1s. Suggest raising default timeout, detecting cold cache, or surfacing build progress in the timeout error message. Repro: swiftiomatic's BinaryOperatorExprTests filter.

## Tasks

- [x] Add `SwiftRunner.coldCacheTimeout` (15 min) + `isColdCache(packagePath:)` helper
- [x] Update `SwiftPackageBuildTool` and `SwiftPackageTestTool` to auto-use cold-cache timeout when no explicit timeout
- [x] Wrap `ProcessError.timeout` with packagePath + cold-cache hint in tool errors
- [x] Update tool schema timeout descriptions



## Summary of Changes

- `SwiftRunner` gains `coldCacheTimeout` (15 min) and `isColdCache(packagePath:)` (checks `.build/checkouts`).
- `SwiftPackageBuildTool` and `SwiftPackageTestTool` use the cold-cache timeout automatically when the caller didn't pass `timeout` and the cache is cold.
- On `ProcessError.timeout`, both tools rethrow with the package path, the duration used, whether cold-cache was detected, and a hint to retry with an explicit `timeout` or pre-build to warm the cache.
- Tool schemas updated to document the cold-cache default.

Note: this does not speed up builds — it only prevents premature timeout aborts and improves the error message. Pre-warming is tracked separately.
