---
# om4-p2i
title: test_macos output should include pass/fail summary when run with -quiet flag
status: completed
type: feature
priority: normal
created_at: 2026-03-08T01:52:33Z
updated_at: 2026-03-08T01:59:57Z
sync:
    github:
        issue_number: "190"
        synced_at: "2026-03-08T02:01:19Z"
---

## Problem

When `test_macos` results are parsed from `xcodebuild -quiet` output, the pass/fail summary line is often missing or buried. This makes it hard to programmatically detect test outcomes — tools grepping for 'passed' or 'failed' can't reliably find results.

## Expected Behavior

The tool's output should always include a clear, parseable summary line like:
```
Tests: 12 passed, 0 failed
```

Even when using `-quiet` mode, the result should have a definitive pass/fail indicator that's easy to grep, so callers don't have to parse xcresult bundles or scrape verbose build logs.

## Context

When running tests in a loop to reproduce flaky failures (`for i in $(seq 1 20); do ... done`), the current output makes it difficult to detect which run failed. The `-quiet` flag suppresses the summary, and without it the output is thousands of lines of build noise.


## Summary of Changes

Always include both passed and failed counts in test result summary headers, even when one is zero. Changed two formatters:
- `ErrorExtractor.formatXCResultData` (xcresult path)
- `BuildResultFormatter.formatTestHeader` (stdout fallback)

Before: `Tests passed (42 passed, 3.2s)` — omits "0 failed"
After: `Tests passed (42 passed, 0 failed, 3.2s)` — always shows both counts

Added a test verifying both counts always appear.
