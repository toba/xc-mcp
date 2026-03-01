---
# hvo-oqr
title: Port crash-to-test association from xcsift
status: completed
type: task
priority: normal
created_at: 2026-03-01T18:06:21Z
updated_at: 2026-03-01T18:12:47Z
sync:
    github:
        issue_number: "153"
        synced_at: "2026-03-01T18:14:03Z"
---

xcsift added crash-to-test association in their OutputParser (a1723d8). When a test crashes, the parser now tracks which test was running and associates the crash with it.

Review the implementation and port relevant logic to our BuildOutputParser.swift so test crash diagnostics include the originating test name.

## Reference

- Upstream commit: ldomaradzki/xcsift@a1723d8
- Files: `Sources/OutputParser.swift`, `Tests/ParsingTests.swift`

## TODO

- [x] Review upstream implementation
- [x] Adapt for our BuildOutputParser.swift / BuildOutputModels.swift
- [x] Add tests


## Summary of Changes

Ported crash-to-test association from xcsift (a1723d8) into `BuildOutputParser.swift`:

- Added `lastStartedTestName` / `pendingSignalCode` state tracking
- Added `parseStartedTest()` for XCTest and Swift Testing start line formats
- Signal code detection from "Exited with unexpected signal code N" lines
- Crash confirmation via "Restarting after" lines, creating a `FailedTest` with the associated test name
- Safety net: if `testRunFailed` is true and a test started but never completed, record it as a crash
- Cleared tracking state on normal pass/fail to prevent false associations
- 7 new tests covering signal crashes, no-signal crashes, safety net, Swift Testing format, and no false positives

No changes needed to `BuildOutputModels.swift` — the existing `FailedTest` struct was sufficient.
