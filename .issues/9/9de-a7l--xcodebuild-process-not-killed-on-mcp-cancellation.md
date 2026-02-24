---
# 9de-a7l
title: xcodebuild process not killed on MCP cancellation
status: completed
type: bug
priority: high
created_at: 2026-02-22T03:01:33Z
updated_at: 2026-02-22T03:04:00Z
sync:
    github:
        issue_number: "104"
        synced_at: "2026-02-24T18:57:44Z"
---

## Description

When the MCP client cancels a tool call (e.g., Claude Code aborting a `test_macos` request), the underlying `xcodebuild` process is NOT terminated. It continues running as an orphan process.

## Root Cause

In `Sources/Core/XcodebuildRunner.swift`, the polling loop:

```swift
while process.isRunning {
    if startTime.duration(to: .now) > .seconds(timeout) {
        process.terminate()  // ✓ handled
        throw XcodebuildError.timeout(...)
    }
    try await Task.sleep(nanoseconds: 100_000_000)  // throws CancellationError on abort
}
```

When MCP cancels the Task, `Task.sleep` throws `CancellationError` which propagates up WITHOUT calling `process.terminate()`. The timeout and stuck-process paths correctly terminate the process, but external cancellation does not.

## Observed Behavior

- Set `timeout: 60` on `test_macos`
- MCP client aborts the call after ~2 minutes
- Returns `AbortError: The operation was aborted`
- The `xcodebuild` process continues running in the background

## Expected Behavior

When the MCP tool call is cancelled, the `xcodebuild` process should be terminated.

## Suggested Fix

Add cancellation cleanup to the run method:

```swift
defer {
    if process.isRunning {
        process.terminate()
    }
}
```

Or use `withTaskCancellationHandler` to ensure the process is killed on cancellation.

## Checklist

- [x] Add `defer { if process.isRunning { process.terminate() } }` to `XcodebuildRunner.run()`
- [x] Verify timeout still works correctly after change
- [x] Test MCP cancellation kills the process

## Summary of Changes

Added `defer { if process.isRunning { process.terminate() } }` after `process.run()` in `XcodebuildRunner.run()`. This ensures the xcodebuild process is terminated whenever the function exits, including via Task cancellation.
