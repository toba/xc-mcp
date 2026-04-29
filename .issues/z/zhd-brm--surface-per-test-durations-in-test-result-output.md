---
# zhd-brm
title: Surface per-test durations in test result output
status: completed
type: feature
priority: normal
tags:
    - citation
created_at: 2026-04-29T04:41:40Z
updated_at: 2026-04-29T04:52:15Z
sync:
    github:
        issue_number: "291"
        synced_at: "2026-04-29T05:14:18Z"
---

**Inspiration**: getsentry/XcodeBuildMCP `02fc85f` (`feat(test-timing): emit per-test timing in test results`).

## Problem

`XCResultParser.TestDetail` already collects per-test `durationInSeconds`, but `BuildResultFormatter.formatTestResult(_:)` only emits aggregate counts and total `testTime`. Per-test durations are dropped on the floor in the user-facing output. This makes it hard to spot slow tests when reviewing test runs.

## Proposal

Add an opt-in `Test Results:` block to the test formatter that lists each test with its status and duration, sorted by duration descending. Toggle via env var `XC_MCP_SHOW_TEST_TIMING=1` (matches upstream's `XCODEBUILDMCP_SHOW_TEST_TIMING`).

```
Test Results:
  ✓ MyAppTests.testHeavyComputation (1.234s)
  ✓ MyAppTests.testFast (0.012s)
  ✗ MyAppTests.testFlaky (0.456s)
```

## Files

- `Sources/Core/BuildResultFormatter.swift` — add `formatTestCases(_ tests: [TestDetail])`.
- `Sources/Core/BuildResultFormatter.swift` line 234 (`formatTestHeader`) — call site for new block.
- `XCResultParser.TestDetail` already has the data; no changes needed there.

## Out of scope

- Structured JSON output (we don't have a structured-output schema yet).
- Per-iteration timing for parameterized tests.


## Summary of Changes

During implementation discovered that `Sources/Core/ErrorExtraction.swift` (`formatXCResultData`) already surfaces per-test durations in two of three branches: small suites (≤50 tests) and all-passed runs both list every test with `(N.Ns)`. The actual gap was in the **>50 tests with failures/skips** branch, which only lists failed and skipped tests — slow passing tests are hidden.

- `Sources/Core/ErrorExtraction.swift`:
  - Added `showTestTimingEnabled()` reading `XC_MCP_SHOW_TEST_TIMING` (any truthy value).
  - Added `formatTestTimings(_:limit:)` that returns the slowest 10 tests sorted by duration desc, with status icon and ms-precision duration.
  - Wired it into the >50+failures branch of `formatXCResultData`.

Default output is unchanged. Setting `XC_MCP_SHOW_TEST_TIMING=1` adds a `Test timings (slowest 10):` block at the end of large failing test runs.
