---
# d93-3rk
title: test_macos should surface per-test results, skip reasons, and performance metrics
status: ready
type: feature
priority: high
tags:
    - enhancement
created_at: 2026-03-07T21:38:25Z
updated_at: 2026-03-07T21:38:25Z
sync:
    github:
        issue_number: "180"
        synced_at: "2026-03-07T21:39:58Z"
---

## Problem

`test_macos` output is too coarse. When tests include skips, failures, or performance measurements, the tool only reports summary counts (e.g. "1 passed"). This forces multiple follow-up steps:

1. Run `test_macos` → "Tests passed (1 passed)"
2. Realize results are incomplete, run with `result_bundle_path`
3. Shell out to `xcrun xcresulttool get test-results tests --path` to see per-test status
4. Discover 2 tests were skipped with reason "No project node in fixture database"

That's 4 steps for what should be 1.

## Expected behavior

`test_macos` output should include:
- Per-test status (passed/failed/skipped) with test name
- Skip reasons (from `XCTSkip` messages)
- Failure messages and file:line locations (already partially done)
- Performance metric values when `measure()` blocks are used (signpost durations, clock time, etc.)

Example desired output:
```
Tests: 3 total (1 passed, 2 skipped)

  ✓ testAppLaunchesWithUsageMessage (2.1s)
  ⊘ testRapidTypingSignpostDuration — skipped: No project node in fixture database
  ⊘ testBurstTypingSignpostDuration — skipped: No project node in fixture database
```

For performance tests with `measure()`:
```
  ✓ testRapidTypingSignpostDuration (45.2s)
    selectionChanged: avg 0.42ms, stddev 0.08ms (5 iterations)
    didProcessEditing: avg 0.11ms, stddev 0.02ms (5 iterations)
    Clock: avg 8.3s, stddev 0.4s (5 iterations)
```

## Implementation

The xcresult bundle already contains all this data. The tool creates a result bundle internally — it just needs to parse it before returning.

Parse via: `xcrun xcresulttool get test-results tests --path <bundle>` (JSON output).

## Related

This would also eliminate the need for a separate "read xcresult" tool in most cases.
