---
# vfo-qne
title: test_macos reports success when only_testing filter matches zero tests
status: completed
type: bug
priority: high
created_at: 2026-02-24T23:25:03Z
updated_at: 2026-02-24T23:32:45Z
sync:
    github:
        issue_number: "129"
        synced_at: "2026-02-24T23:33:03Z"
---

## Description

When `only_testing` contains identifiers that don't match any test (e.g. wrong struct name for Swift Testing), `test_macos` reports "Tests passed" with no indication that zero tests actually ran. This is dangerously misleading — a deliberately failing test (`#expect(Bool(false))`) still reports success.

## Reproduction

1. Have a Swift Testing test in struct `AnalysisSnapshotTests`
2. Call `test_macos` with `only_testing: ["MathViewTests/SwiftMathExamples/analysis(_:)"]` (wrong struct name)
3. Tool reports: "Tests passed for scheme 'Standard' on macOS / Test run completed"
4. The test never ran — no test count shown, no warning about unmatched filters

The correct identifier would be `MathViewTests/AnalysisSnapshotTests/analysis(_:)`.

## Impact

During a MathView bugfix session this caused ~15 minutes of wasted debugging. A guaranteed-fail test was inserted but the tool kept reporting success, leading to incorrect assumptions about code behavior.

## Expected Behavior

When `only_testing` filters match zero tests, `test_macos` should either:
1. **Error** with a message like "No tests matched the only_testing filter" (preferred)
2. **Warn** in the output: "0 tests ran — check that only_testing identifiers are correct"

## Investigation

- [x] Check if xcodebuild reports test count in output when using `-only-testing`
- [x] Parse test count from xcodebuild output and detect zero-test runs
- [x] Return an error or warning when no tests matched the filter

## Context

Swift Testing uses struct names as test identifiers, not file names. Users commonly guess wrong (file name vs struct name), and silent success makes this error invisible.


## Summary of Changes

Added zero-test detection to `ErrorExtractor.formatTestToolResult()`. When `only_testing` filters are specified but zero tests run, the tool now throws an `MCPError.internalError` with an actionable message including the filters used and guidance on correct identifier format.

### Files changed
- `Sources/Core/ErrorExtraction.swift` — added `onlyTesting` parameter and zero-test detection logic
- `Sources/Tools/MacOS/TestMacOSTool.swift` — pass `onlyTesting` through
- `Sources/Tools/Simulator/TestSimTool.swift` — pass `onlyTesting` through
- `Sources/Tools/Device/TestDeviceTool.swift` — pass `onlyTesting` through
- `Tests/XCResultParserTests.swift` — 4 new tests for zero-test detection
