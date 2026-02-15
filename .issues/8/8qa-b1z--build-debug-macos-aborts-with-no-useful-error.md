---
# 8qa-b1z
title: build_debug_macos aborts with no useful error
status: completed
type: bug
priority: normal
created_at: 2026-02-15T20:44:54Z
updated_at: 2026-02-15T20:50:31Z
---

## Problem

`build_debug_macos` returns `AbortError: The operation was aborted` with no additional context. Likely a timeout issue since building a full Xcode project can exceed MCP tool call timeouts.

## Steps to Reproduce

1. Set up a non-trivial Xcode project (e.g. multi-module app)
2. Call `build_debug_macos(project_path: "Project.xcodeproj", scheme: "Standard")`
3. Get: `MCP error -32001: AbortError: The operation was aborted.`

## Expected Behavior

- Build should complete (or stream progress) without timing out
- If it does fail, the error should include the build log or reason for failure

## Possible Fixes

- [x] Increase timeout for build+launch operations
- [x] Stream build output to keep the MCP connection alive
- [x] Return partial build logs in the error response
- [x] Add progress notifications during long builds

## Summary of Changes

- Increased build timeout from 300s (5 min) to 600s (10 min) in `BuildDebugMacOSTool`
- Added `onProgress` logging during builds so output is streamed to the server log
- Made `XcodebuildError` conform to `MCPErrorConvertible` so timeout/stuck errors include partial build output (extracted errors or last 2000 chars)
- Added `timeout` and `onProgress` parameters to `XcodebuildRunner.build()` method
- All 315 tests pass
