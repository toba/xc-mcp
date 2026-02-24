---
# nbo-0zb
title: Add timeout support to SwiftRunner
status: completed
type: bug
priority: high
created_at: 2026-02-23T00:16:23Z
updated_at: 2026-02-23T00:23:44Z
sync:
    github:
        issue_number: "125"
        synced_at: "2026-02-24T18:57:48Z"
---

## Problem

SwiftRunner uses the Subprocess framework with no timeout parameter. If a subprocess hangs (e.g. \`swift package show-dependencies\` on a large repo), the MCP tool call blocks forever with no way to recover.

Observed during integration testing: \`SwiftPackageListTool\` and \`SwiftPackageBuildTool\` both hung when run against the xc-mcp project itself. Only swift-testing's \`.timeLimit()\` trait prevented an infinite hang — the tool itself would never have returned.

## Context

\`ProcessResult.runSubprocess()\` delegates to \`Subprocess.run()\` which blocks until process exit. No \`WaitDelay\` or deadline is configured.

## Acceptance Criteria

- [ ] Add optional \`timeout\` parameter to \`ProcessResult.runSubprocess()\`
- [ ] Apply a sensible default timeout (e.g. 10 minutes) to all SwiftRunner calls
- [ ] Return a clear error message when a timeout fires instead of hanging
- [ ] Expose \`timeout\` as an optional MCP tool parameter on long-running SPM tools (build, test, run)


## Summary of Changes

- Added `ProcessError` enum with `timeout(duration:)` case to `ProcessResult.swift`, conforming to `Error`, `Sendable`, `LocalizedError`, and `MCPErrorConvertible`
- Added `timeout: Duration?` parameter to `ProcessResult.runSubprocess()` with a private `raceTimeout()` helper that uses `withThrowingTaskGroup` to race the subprocess against a sleep deadline
- Added `SwiftRunner.defaultTimeout` (300s) and threaded `timeout: Duration` through `run()`, `build()`, `test()`, `runExecutable()`, `showDependencies()`, `resolve()`, and `update()`
- Exposed optional `timeout` integer parameter (seconds) on `SwiftPackageBuildTool`, `SwiftPackageTestTool`, `SwiftPackageRunTool`, and `SwiftPackageListTool` MCP tool schemas
- All 570 tests pass, swiftformat and swiftlint clean
