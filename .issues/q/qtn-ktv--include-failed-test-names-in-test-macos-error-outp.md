---
# qtn-ktv
title: Include failed test names in test_macos error output
status: completed
type: feature
priority: normal
created_at: 2026-03-07T22:46:27Z
updated_at: 2026-03-07T22:48:45Z
sync:
    github:
        issue_number: "185"
        synced_at: "2026-03-07T22:49:24Z"
---

When `test_macos` returns a failure, the error output includes the full list of passed tests but doesn't clearly surface which tests failed. The user has to manually search through thousands of lines to find failures.

## Expected behavior

The error summary should list the failed test names prominently, e.g.:

```
Tests failed (3617 total, 3599 passed, 4 failed, 14 skipped)

Failed:
  ✗ testFoo() — expected X but got Y
  ✗ testBar() — index out of range

(3599 passed, 14 skipped)
```

## Current behavior

The output lists all tests (passed and failed) in a flat list. Finding the 4 failures among 3600+ results requires manual scanning or shell gymnastics like piping through `xcresulttool`.

## Context

After running `test_macos` with `only_testing: ["CSLTests"]`, the 4 pre-existing failures were buried in the output. The user had to attempt `xcresulttool` and `diagnostics` calls to identify them — neither surfaced the failed test names directly.

## Summary of Changes

Modified `formatXCResultData` in `ErrorExtraction.swift` to surface failed test names prominently in large test suites:

- **Small suites (≤50 tests)**: unchanged — lists all tests with pass/fail/skip status
- **Large suites (>50 tests) with failures**: now shows only `Failed:` and `Skipped:` sections instead of listing all 3600+ tests
- Extracted `formatTestLine` helper to eliminate duplicated per-test formatting logic
- Fallback `data.failures` path now uses `Failed:` header (was `Failures:`) and `✗` marker for consistency
