---
# g8r-9u3
title: test_macos should return XCTest measure() timing data in results
status: completed
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-03-04T03:03:28Z
updated_at: 2026-03-04T03:11:42Z
sync:
    github:
        issue_number: "169"
        synced_at: "2026-03-04T03:13:03Z"
---

## Problem

When running XCTest performance tests via `test_macos`, the tool result says "Tests passed (4 passed)" but does not include the `measure()` timing data (average, values, standard deviation) that `xcodebuild` outputs.

To get timing data, you must fall back to running `xcodebuild test` directly via Bash and grep for "measured".

## Expected

The `test_macos` tool result should include performance metric lines when XCTest `measure()` blocks are run. Example output from xcodebuild:

```
measured [Time, seconds] average: 0.037, relative standard deviation: 112.254%, values: [0.125595, 0.033183, ...]
```

## Context

Discovered while running `DocumentRenderPerformanceTests` in the Thesis project to benchmark launch performance optimizations. Had to use raw `xcodebuild` via Bash to see timing numbers.

Also: `test_macos` with `configuration: "Release"` fails because the TEST_HOST path contains "(debug)" even in Release mode — this may be expected behavior for hosted test targets but worth documenting.

## Summary of Changes

### New model
- Added `PerformanceMeasurement` struct to `BuildOutputModels.swift` with test name, metric, average, relative standard deviation, and values array

### Parser changes
- `BuildOutputParser` now captures `measured [...]` lines from xcodebuild stdout
- Lines are parsed before the fast-path filter so they're never skipped
- Measurements are associated with the last started test name via `lastStartedTestName`

### Formatter changes
- `BuildResultFormatter.formatTestResult()` includes a "Performance:" section when measurements exist
- `formatPerformanceMeasurements()` is public so it can be reused

### xcresult path
- `ErrorExtraction.formatTestToolResult()` also parses stdout for performance data when using the xcresult path, since xcresulttool doesn't expose measure() data

### Tests
- 3 new tests: basic parsing, multiple metrics, formatted output verification
- All 39 parser tests and 13 formatter tests pass

### Files changed
- `Sources/Core/BuildOutputModels.swift` — added `PerformanceMeasurement` struct and `performanceMeasurements` field on `BuildResult`
- `Sources/Core/BuildOutputParser.swift` — parse `measured [...]` lines, new state + parser method
- `Sources/Core/BuildResultFormatter.swift` — format performance section in test results
- `Sources/Core/ErrorExtraction.swift` — append performance data for xcresult path
- `Tests/BuildOutputParserTests.swift` — 3 new tests
