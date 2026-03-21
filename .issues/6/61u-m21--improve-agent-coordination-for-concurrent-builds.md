---
# 61u-m21
title: Improve agent coordination for concurrent builds
status: completed
type: feature
priority: normal
created_at: 2026-03-21T21:41:42Z
updated_at: 2026-03-21T21:45:54Z
sync:
    github:
        issue_number: "231"
        synced_at: "2026-03-21T21:47:04Z"
---

## Problem

When multiple agents run concurrently, they frequently collide on `build_macos` / `test_macos` calls for the same project:

```
Error: MCP error -32600: Invalid Request: Another process is already building this project
(Thesis.xcodeproj). Wait for it to finish before starting another build.
```

The current `BuildGuard` (`Sources/Core/BuildGuard.swift`) uses `flock` with `LOCK_NB` (non-blocking) and throws immediately if the lock is held. There is no queuing, retry, or wait mechanism — the calling agent simply gets an error and has to give up or manually retry.

## Current Behavior

- `BuildGuard.acquire()` attempts a non-blocking `flock`
- If the lock is held, it throws `BuildGuardError` immediately
- The MCP error is returned to the agent, which typically fails the task

## Desired Behavior

Agents should be able to wait for the build lock instead of failing immediately. Options to consider:

### Option A: Blocking wait with timeout
Add a `wait` or `timeout` parameter to build tools. When set, `BuildGuard.acquire()` blocks (using `LOCK_EX` without `LOCK_NB`) with a configurable timeout instead of failing immediately. This lets agents queue up naturally via the OS file lock.

### Option B: Retry loop with backoff
Keep non-blocking acquisition but add a retry loop with exponential backoff up to a max wait time. Periodically re-attempt the lock.

### Option C: Return "busy" status with ETA
Instead of an error, return a structured response indicating the project is busy, what operation holds the lock, and suggest the agent retry after N seconds. This gives agents enough info to schedule a retry.

## Files

- `Sources/Core/BuildGuard.swift` — lock acquisition logic
- `Sources/Tools/MacOS/BuildMacOSTool.swift` — primary consumer
- `Sources/Tools/MacOS/TestMacOSTool.swift` — primary consumer


## Summary of Changes

`BuildGuard.acquire()` now blocks with a polling loop (500ms interval) instead of failing immediately. Default timeout is 10 minutes. When multiple agents try to build the same project, they queue up naturally — the second agent waits for the first to finish.

### Files changed
- `Sources/Core/BuildGuard.swift` — polling loop with configurable timeout, `async throws` signature, split out `writeLockDescription` helper
- `Sources/Core/XcodebuildRunner.swift` — `await` the now-async `acquire` call
- `Sources/Core/SwiftRunner.swift` — same
- `Sources/Tools/SwiftPackage/DetectUnusedCodeTool.swift` — same
