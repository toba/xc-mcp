---
# v80-qz0
title: Suppress non-project warnings in build output
status: completed
type: feature
priority: normal
created_at: 2026-02-22T04:49:12Z
updated_at: 2026-02-22T20:28:31Z
sync:
    github:
        issue_number: "98"
        synced_at: "2026-02-24T18:57:43Z"
---

## Context

During a Thesis session, `build_macos` returned 1 error and 118 warnings. The actual error was a single missing import (`import GRDB`), but the output was 12K+ characters (truncated by Claude Code) because it included every warning — most from:

- Third-party GRDB submodule (`Storage/GRDB/`)
- SwiftLint TODOs
- Deprecated API notices in vendored code
- macOS deployment target warnings from subproject xcodeproj files

The signal-to-noise ratio was terrible. By contrast, `test_macos` output was concise because it uses XCResultParser to extract only test failures.

## Problem

`BuildResultFormatter.formatWarnings()` outputs every parsed warning with no filtering or categorization. `BuildWarning` has a `type: WarningType` field but it only distinguishes `.compile`/`.runtime`/`.swiftui` — not source origin.

## Proposed Approach

Suppress warnings from outside the project source tree by default. The formatter already has access to file paths on each `BuildWarning`. On successful builds, omit warnings entirely (the user can see them in Xcode). On failed builds, only show warnings from files within the project directory, excluding known third-party paths (submodules, DerivedData, Pods, etc.).

**Concrete changes:**

- [ ] Detect the project root from `project_path` session default (or xcodebuild `-project` arg)
- [ ] In `BuildResultFormatter.formatWarnings()`, partition warnings into project vs external
- [ ] On success: omit warnings section entirely (just show count in header)
- [ ] On failure: show only project warnings; append summary line like `(+87 warnings from dependencies hidden)`
- [ ] Consider a `show_all_warnings: bool` parameter on build tools for when users want full output

## Files

| File | Change |
|------|--------|
| `Sources/Core/BuildResultFormatter.swift` | Filter warnings by project path, add external summary |
| `Sources/Core/BuildOutputModels.swift` | Optionally add origin tracking to `BuildWarning` |
| `Sources/Tools/MacOS/BuildMacOSTool.swift` | Pass project path to formatter |
| `Sources/Tools/Simulator/BuildSimTool.swift` | Same |

## Session Reference

Thesis session where this was observed: fixing orphan side-note nodes. Build had 1 real error, 118 irrelevant warnings.


## Summary of Changes

Implemented in commit 661f406. All checklist items completed except the optional show_all_warnings parameter (deferred). Project root detection, warning partitioning, success/failure filtering, and hidden count summary all working. 5 new tests added.
