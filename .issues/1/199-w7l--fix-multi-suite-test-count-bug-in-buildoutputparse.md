---
# 199-w7l
title: Fix multi-suite test count bug in BuildOutputParser
status: completed
type: bug
priority: normal
created_at: 2026-04-06T16:53:15Z
updated_at: 2026-04-06T16:57:00Z
sync:
    github:
        issue_number: "261"
        synced_at: "2026-04-06T16:59:31Z"
---

Our BuildOutputParser has the same three bugs fixed by ldomaradzki/xcsift@194dac8:

1. **XCTest multi-bundle**: `xctestExecutedCount`/`xctestFailedCount` are overwritten by each `Executed N tests` line — only the last bundle's counts survive
2. **Swift Testing multi-run**: `swiftTestingExecutedCount`/`swiftTestingFailedCount` similarly overwritten
3. **Parallel test scheduling**: `parallelTestsTotalCount` only set once (`if == nil`), second parallel block ignored

Fix: accumulate counts instead of overwriting, distinguish bundle-level from nested suite summaries.

Reference: ldomaradzki/xcsift@194dac8

## Tasks

- [x] Fix XCTest multi-bundle counting (accumulate instead of overwrite)
- [x] Fix Swift Testing multi-run counting
- [x] Fix parallel test scheduling reset detection
- [x] Add tests for multi-suite scenarios


## Summary of Changes

Fixed three counting bugs in BuildOutputParser where test counts were overwritten instead of accumulated across multiple test bundles/runs:
1. XCTest `Executed N tests` lines now accumulate across .xctest bundles
2. Swift Testing `Test run with N tests` lines now accumulate across runs (all 3 format variants)
3. Parallel test scheduling `[1/N]` lines detect index reset and accumulate totals

Added 4 tests covering multi-bundle/multi-run scenarios.
