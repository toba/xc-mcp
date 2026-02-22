---
# lcu-gfr
title: 'Pipe deadlock: waitUntilExit before reading stdout blocks server'
status: completed
type: bug
priority: critical
created_at: 2026-02-22T18:45:39Z
updated_at: 2026-02-22T19:02:02Z
---

## Bug

`ProcessResult.run()` and `XCResultParser.runXCResultTool()` both call `process.waitUntilExit()` **before** `pipe.fileHandleForReading.readDataToEndOfFile()`. When the child process produces more output than the OS pipe buffer (~64KB), the child blocks on `write()` waiting for the pipe to drain, while the parent blocks on `waitUntilExit()` — classic pipe deadlock.

This deadlocks the entire MCP server since xc-build is single-threaded (one request at a time). All subsequent tool calls (including `set_session_defaults`) hang indefinitely.

## Observed

- `xcresulttool get test-results tests` stuck for 39+ minutes writing JSON (27MB xcresult bundle)
- `xc-build` blocked in `TestMacOSTool.execute` → `XCResultParser.runXCResultTool` → `waitUntilExit`
- Stack sample confirms `xcresulttool` is blocked in `LocalFileOutputByteStream.writeImpl` (pipe full)
- Stack sample confirms `xc-build` is blocked in `NSConcreteTask.waitUntilExit` → `mach_msg`

## Root Cause

Two locations with the same bug pattern:

1. **`Sources/Core/ProcessResult.swift:84-85`** — `ProcessResult.run()` used by all runners
2. **`Sources/Core/XCResultParser.swift:46-50`** — `runXCResultTool()` (independent implementation)

Both do:
```swift
try process.run()
process.waitUntilExit()          // blocks if pipe is full
let data = pipe.readDataToEndOfFile()  // never reached
```

## Fix

Read pipe data **before** or **concurrently with** `waitUntilExit()`:

```swift
// Option A: read first, then wait
try process.run()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()

// Option B: read asynchronously
try process.run()
let stdoutData = stdoutPipe.fileHandleForReading.availableData  // or use async read
process.waitUntilExit()
let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
```

Option A is simplest and correct for the synchronous case — `readDataToEndOfFile()` blocks until EOF (process exit), so `waitUntilExit()` after it just confirms the exit code.

Also consider adding a timeout to `waitUntilExit()` as a safety net.

## Affected Files

| File | Line | Issue |
|------|------|-------|
| `Sources/Core/ProcessResult.swift` | 84-85 | `waitUntilExit()` before `readDataToEndOfFile()` |
| `Sources/Core/XCResultParser.swift` | 46-50 | Same pattern, independent implementation |

## Scope

Every tool that calls `ProcessResult.run()` is affected when output exceeds ~64KB:
- `SimctlRunner`, `SwiftRunner`, `XcodeStateReader`, `CoverageParser`, `DeviceCtlRunner`
- `XCResultParser` (separate implementation, same bug)


## Summary of Changes

Added `ProcessResult.drainPipes(stdout:stderr:)` — a shared helper that reads stdout on the calling thread and stderr concurrently on a background thread via `DispatchQueue.global()`, synchronized with a `DispatchSemaphore`. This prevents the classic pipe deadlock where `waitUntilExit()` blocks because the child process is stuck writing to a full pipe buffer (~64KB).

**Fixed locations (7 files):**
- `ProcessResult.run()` — refactored to use `drainPipes()`
- `DeviceCtlRunner` — uses `drainPipes()`
- `SimctlRunner` — uses `drainPipes()`
- `SwiftRunner` — uses `drainPipes()`
- `XctraceRunner` — uses `drainPipes()`
- `XcodeStateReader` — uses `drainPipes()`
- `XCResultParser.runXCResultTool()` — reordered (single pipe, no helper needed)
- `BuildDebugMacOSTool` — reordered otool/codesign reads (single pipe each)
- `IntegrationTestHelper` — reordered (single pipe)
