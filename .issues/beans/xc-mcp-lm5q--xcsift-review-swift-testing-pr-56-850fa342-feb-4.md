---
# xc-mcp-lm5q
title: 'xcsift: Review Swift Testing PR #56 (850fa342, Feb 4)'
status: completed
type: task
priority: high
created_at: 2026-02-07T17:46:40Z
updated_at: 2026-02-07T17:52:43Z
sync:
    github:
        issue_number: "14"
        synced_at: "2026-02-15T22:08:23Z"
---

Very recent (3 days ago) — likely has improvements to Swift Testing parsing not yet in our code. Compare upstream Sources/OutputParser.swift changes from this PR against our Sources/Core/BuildOutputParser.swift.

Files changed upstream: Sources/OutputParser.swift, Tests/ParsingTests.swift

## TODO

- [x] Diff upstream 850fa342 against our BuildOutputParser.swift
- [x] Identify any new parsing logic or fixes
- [x] Port relevant changes to our codebase
- [x] Run tests to verify compatibility

## Summary of Changes

Reviewed upstream xcsift PR #56 (commit 850fa342) which adds Swift Testing support for both quoted and unquoted test name formats.

Our code already had the core functionality but had two gaps:

1. **Missing guards against false positives** — `parsePassedTest()` and `parseFailedTest()` matched on bare "Test " prefix without excluding "Test run with" (summary lines) and "Test Case" (XCTest format). Added guard clauses in both functions.

2. **Less robust unquoted name extraction** — Our `extractSwiftTestingName()` used character-by-character parenthesis tracking for unquoted names. Upstream uses end-marker searching (`[" recorded", " failed", " passed", " started"]`) which is more reliable. Adopted the upstream approach.

Also added a new test case (`testSwiftTestingMixedFormats`) matching upstream PR #56 test coverage, exercising SF Symbol prefixes with unquoted function names and the failure summary line.

All 311 tests pass.
