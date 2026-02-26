---
# 7g4-xje
title: 'start_mac_log_cap: improve subsystem filter reliability and add connectivity verification'
status: completed
type: feature
priority: normal
tags:
    - logging
    - dx
created_at: 2026-02-26T03:19:59Z
updated_at: 2026-02-26T03:25:14Z
sync:
    github:
        issue_number: "147"
        synced_at: "2026-02-26T03:41:27Z"
---

## Problem

`start_mac_log_cap` with a `subsystem` filter can silently capture zero logs even when the target process is actively logging via `os.Logger`. There is no feedback mechanism to verify the log stream is connected or that the filter predicate is matching anything. The user discovers the problem only after stopping capture and finding an empty file.

### Observed behavior (Thesis session)

1. User started log capture: `start_mac_log_cap(subsystem: "com.thesisapp.ThesisKit")`
2. TestApp was running and emitting `Diagnostic.log` calls via `os.Logger`
3. After stopping capture, the log file was empty
4. User had to manually investigate the logging subsystem string, process name, and predicate syntax

### Root causes

1. **`bundle_id` predicate is unreliable**: The current implementation uses `processImagePath CONTAINS "\(bundleId)"` which matches the executable path, not the actual bundle identifier. This fails when the bundle ID doesn't appear in the path (e.g., `TestApp.app` with bundle ID `com.thesisapp.TestApp`).

2. **No stream verification**: After launching `log stream`, there's no check that the predicate is valid or that any process matches the filter. A brief verification period (e.g., check that the log stream process is still running and hasn't errored) would catch obvious issues.

3. **No diagnostic guidance**: When filters match nothing, the user gets no help. The tool could suggest running `log stream --info --predicate 'subsystem == "..."'` manually to test, or it could list active processes with matching subsystems.

## Proposed improvements

1. **Fix `bundle_id` predicate**: Use `processImagePath ENDSWITH "/\(appName)"` or parse the bundle's Info.plist to get the actual executable name, rather than assuming the bundle ID appears in the path.

2. **Add stream health check**: After starting the `log stream` process, wait 1-2 seconds and verify the process is still alive. If it exited with an error (e.g., invalid predicate syntax), surface that error immediately instead of silently writing to an empty file.

3. **Add `level` parameter**: Allow specifying log level (`--level info` or `--level debug`) since `log stream` defaults to showing only `default` level and above. Many apps log at `info` or `debug` level, which would be silently filtered out.

4. **Surface filter diagnostics in output**: After starting capture, include the exact predicate being used in the response so the user can verify it's correct: `Predicate: subsystem == "com.thesisapp.ThesisKit"`

## Files

- `Sources/Tools/MacOS/StartMacLogCapTool.swift` — fix bundle_id predicate, add level parameter, add stream health check
- `Sources/Core/ProcessResult.swift` or `LogCapture.swift` — add process health verification helper


## Summary of Changes

### `StartMacLogCapTool.swift`
- **Fixed `bundle_id` predicate**: Changed from `processImagePath CONTAINS` (unreliable — bundle ID often doesn't appear in executable path) to `process ==` using the last component of the bundle ID (e.g., `com.thesisapp.TestApp` → `process == "TestApp"`).
- **Added `level` parameter**: New enum parameter (`default`, `info`, `debug`) that maps to `--info` / `--debug` flags on `log stream`. Fixes silent filtering of info/debug-level messages.
- **Surface predicate in output**: The exact predicate string is now included in the response message so users can verify correctness.
- **Added stream health check**: After launching, waits 1 second and verifies the process is still alive. If it exited (e.g., invalid predicate syntax), surfaces the error output immediately instead of silently writing to an empty file.
- **Made `execute` async**: Required for the health check sleep.

### `ProcessResult.swift` (LogCapture)
- Added `verifyStreamHealth(pid:outputFile:)` — checks if a log stream process exited immediately after launch and surfaces error output from the log file.

### `MacLogCapToolTests.swift`
- Added assertion for the new `level` parameter in schema tests.
