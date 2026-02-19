---
# 43u-2ho
title: Fix build_SwiftFormat_macOS integration test failure
status: completed
type: bug
priority: normal
created_at: 2026-02-19T20:22:57Z
updated_at: 2026-02-19T20:51:40Z
sync:
    github:
        issue_number: "91"
        synced_at: "2026-02-19T20:42:40Z"
---

The build_SwiftFormat_macOS integration test is failing with a build error (3 errors, 2 warnings). This is a pre-existing failure unrelated to recent refactoring.

- [x] Investigate the SwiftFormat fixture build errors
- [x] Fix or skip the test


## Summary of Changes

Updated SwiftFormat fixture pin from develop branch commit `2d1b035` (pre-0.56) to release tag `0.59.1` (`22a472c`). The previous pin had 3 compilation errors under Xcode 26 / Swift 6.2 (removeTokens range type, Range.split, AutoUpdatingIndex mismatch). The 0.59.1 release compiles cleanly with no patches needed.
