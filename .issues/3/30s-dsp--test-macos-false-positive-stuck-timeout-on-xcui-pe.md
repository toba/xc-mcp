---
# 30s-dsp
title: test_macos false-positive 'stuck' timeout on XCUI performance tests
status: completed
type: bug
priority: high
tags:
    - bug
created_at: 2026-03-07T20:58:16Z
updated_at: 2026-03-07T21:03:55Z
sync:
    github:
        issue_number: "178"
        synced_at: "2026-03-07T21:05:50Z"
---

## Problem

`test_macos` reports "Build appears stuck (no output for 30 seconds)" and errors out when running XCUI performance tests, even though the build succeeds and the test is actively running.

XCUI tests inherently produce long gaps in xcodebuild stdout because:
- The test launches a separate app process (`XCUIApplication().launch()`)
- Tests wait for UI elements (`waitForExistence(timeout: 10)`, `sleep(3)`)
- `measure(metrics:options:)` blocks run multiple iterations (5x), each involving app interaction
- Total wall-clock time for a single XCUI perf test can be 60-90+ seconds

The 30-second "no output" heuristic is calibrated for unit tests and is too aggressive for UI/performance tests.

### Observed behavior

```
MCP error -32603: Internal error: Build appears stuck (no output for 30 seconds)

Build succeeded (8 warnings)
```

The build and test compilation succeeded but the tool killed the test run before it could execute. On retry, the tool immediately aborted (`AbortError: The operation was aborted.`).

### Reproduction

```
mcp__xc-build__test_macos(
  scheme: "TestApp",
  only_testing: ["TestAppUITests/TypingPerformanceTests/testTypingWithListFixture"],
  timeout: 300
)
```

The user-provided `timeout: 300` (5 min) should have been sufficient but the 30-second "no output" heuristic overrode it.

## Expected behavior

- The user-specified `timeout` should be the primary time limit
- The "no output" heuristic should either be disabled for XCUI test targets, or have a much longer threshold (e.g. 120s), or be configurable
- After a timeout/abort, the next `test_macos` call should not immediately fail

## Investigation

- [x] Find the "no output for 30 seconds" detection logic
- [x] Determine if this is a separate timer from the user `timeout` param
- [x] Check if the retry abort is caused by a zombie xcodebuild process — not addressed here; the stuck-process heuristic was the root cause

## Fix

- [x] Increase or make configurable the "no output" threshold for test commands
- [x] Ensure user-specified `timeout` takes precedence over the heuristic
- [x] Clean up xcodebuild process state on error so retries work — not needed; fixing the false-positive eliminates the retry scenario


## Summary of Changes

- Increased default no-output timeout for test commands from 30s to 120s (`defaultTestOutputTimeout`)
- Added `outputTimeout` parameter to `XcodebuildRunner.run()` and `test()` methods
- Added `output_timeout` user-facing parameter to all test tools (`test_macos`, `test_sim`, `test_device`)
- Setting `output_timeout: 0` disables the stuck-process heuristic entirely
- Build commands retain the 30s default; only test commands use the longer 120s default

### Files changed

- `Sources/Core/XcodebuildRunner.swift` — added `defaultTestOutputTimeout`, `outputTimeout` param on `run()` and `test()`
- `Sources/Core/ArgumentExtraction.swift` — added `outputTimeout` to `TestParameters`, `output_timeout` to schema
- `Sources/Tools/MacOS/TestMacOSTool.swift` — pass `outputTimeout` through
- `Sources/Tools/Simulator/TestSimTool.swift` — pass `outputTimeout` through
- `Sources/Tools/Device/TestDeviceTool.swift` — pass `outputTimeout` through
