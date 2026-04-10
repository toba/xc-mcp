---
# o6t-i3t
title: 'Cherry-pick XcodeBuildMCP parser improvements: fix Swift Testing edge cases, add snapshot tests'
status: completed
type: task
priority: normal
created_at: 2026-04-10T21:55:26Z
updated_at: 2026-04-10T22:04:14Z
sync:
    github:
        issue_number: "269"
        synced_at: "2026-04-10T22:06:00Z"
---

Compare xc-mcp BuildOutputParser against getsentry/XcodeBuildMCP line parsers.

## Parser bugs found (real parsing failures)

- [x] Swift Testing \`(aka 'funcName()')\` verbose suffix breaks parsing of started, passed, failed, and issue lines — remaining text doesn't match expected prefixes
- [x] Swift Testing \`with N test cases\` parameterized prefix before passed/failed breaks result line parsing
- [x] Swift Testing parameterized issue \`recorded an issue with N argument value(s) → ...\` breaks issue line parsing

## Snapshot tests

- [x] Add golden-file snapshot tests for BuildResultFormatter output (build success, build failure, test pass, test fail, linker errors, cascade errors, coverage)



## Summary of Changes

Fixed 3 Swift Testing parser bugs in `BuildOutputParser.swift` found by comparing against getsentry/XcodeBuildMCP's parser:

1. **`(aka '...')` verbose suffix** — `extractSwiftTestingName` now skips past the `(aka 'funcName()')` suffix that Swift Testing emits in verbose mode, fixing parsing of started/passed/failed/issue lines
2. **`with N test cases` parameterized suffix** — same function now skips past `with N test case(s)` for parameterized tests
3. **Parameterized issue arguments** — issue parsing now finds ` at ` after optional `with N argument value(s) → ...` text instead of requiring ` recorded an issue at ` as a fixed prefix; also added no-location `recorded an issue: message` variant

Added 7 golden-file snapshot tests in `BuildResultFormatterSnapshotTests.swift` covering build success, build failure, test pass, test fail, linker errors, cascade errors, and coverage output. 10 new parser tests cover all three bug fixes.
