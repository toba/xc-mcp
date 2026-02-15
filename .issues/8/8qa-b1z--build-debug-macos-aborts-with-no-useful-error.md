---
# 8qa-b1z
title: build_debug_macos aborts with no useful error
status: completed
type: bug
priority: normal
created_at: 2026-02-15T20:44:54Z
updated_at: 2026-02-15T22:00:19Z
sync:
    github:
        issue_number: "38"
        synced_at: "2026-02-15T22:08:23Z"
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

## Update (2026-02-15)

After xc-mcp update, the AbortError is fixed but now fails with a different error:

```
MCP error -32603: Internal error: LLDB command failed: Timed out waiting for LLDB response
```

### Observations

- No build error returned, so the build phase likely succeeded
- LLDB times out during the launch/attach phase
- No Thesis process found after the failure (`pgrep -fl Thesis` returns nothing)
- App never actually launched

### Reproduction

```
mcp__xc-debug__set_session_defaults(project_path: "Thesis.xcodeproj", scheme: "Standard")
mcp__xc-debug__build_debug_macos()
# → MCP error -32603: Internal error: LLDB command failed: Timed out waiting for LLDB response
```

### Root Cause

LLDB suppresses the interactive `(lldb) ` prompt when stdin is a pipe (not a TTY). `LLDBSession` used `Pipe()` for stdin/stdout, so LLDB never emitted the prompt that `readUntilPrompt()` waits for — causing every command to hang until the 30s timeout.

Additionally, the 30s command timeout was too short for launch operations even if prompts were working.

### Fix Applied (see also op7-ozw)

1. **PTY instead of pipes** — Replaced `Pipe()` with a pseudo-TTY (`posix_openpt/grantpt/unlockpt/ptsname`) for LLDB's stdin/stdout in `LLDBSession`. LLDB now believes it's connected to a terminal and emits `(lldb) ` prompts correctly.
2. **Increased launch timeout** — Added `launchCommandTimeout` (120s) to `LLDBRunner`, threaded through `createLaunchSession` → `LLDBSession` init.
3. **Better timeout diagnostics** — Timeout errors now include partial LLDB output (last 2000 chars) instead of the generic "Timed out waiting for LLDB response".
4. **Test harness** — Created `test-debug.sh` for end-to-end testing without brew install/deploy.

### Verified

Thesis app builds and launches under LLDB in ~23s. All 315 tests pass.
