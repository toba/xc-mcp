---
# u1o-vvg
title: Full test suite times out or fails with 5 issues
status: completed
type: bug
priority: normal
created_at: 2026-03-02T19:12:39Z
updated_at: 2026-03-02T19:25:43Z
sync:
    github:
        issue_number: "166"
        synced_at: "2026-03-02T19:25:54Z"
---

- [x] Identify which 5 tests are failing — all in SchemeSuggestionTests
- [x] Root cause: commit c056107 added exit-code override in formatTestToolResult that flipped succeeded=true even when no tests ran
- [x] Fix: only override exit code when totalTestCount > 0

Running `swift test` (or `swift_package_test` with default 300s timeout) either times out or reports 675 tests with 5 issues. Individual test suites pass when filtered. Need to identify the specific failures.


## Summary of Changes

Added `totalTestCount > 0` guard to the exit-code override in `ErrorExtraction.swift:89`. The override was intended for cases where swift test exits non-zero despite all tests passing, but it was also triggering when parseBuildOutput found no errors in short failure messages (like test-plan membership errors), incorrectly flipping the result to success.
