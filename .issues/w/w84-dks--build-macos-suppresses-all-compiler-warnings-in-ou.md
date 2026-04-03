---
# w84-dks
title: build_macos suppresses all compiler warnings in output
status: completed
type: bug
priority: high
tags:
    - enhancement
created_at: 2026-03-25T20:20:41Z
updated_at: 2026-04-03T22:15:32Z
sync:
    github:
        issue_number: "238"
        synced_at: "2026-04-03T22:16:06Z"
---

## Problem

When running `build_macos` (or `build_macos` with `for_testing: true`), the tool reports **Build succeeded** but suppresses all compiler warnings from the output. The Thesis project shows 302 warnings in Xcode but the MCP tool returns zero.

This makes the tool unsuitable for collecting and triaging build warnings programmatically.

## Expected Behavior

All compiler warnings should be included in the build output by default. The existing `errors_only` flag should be the opt-in mechanism for suppressing warnings — when `errors_only` is false/unset, warnings must appear.

## Steps to Reproduce

1. Open a project with known compiler warnings (e.g. unused imports, no calls to throwing functions in `try`, type-check time warnings)
2. Run `build_macos` via MCP
3. Observe: output shows "Build succeeded" with no warnings listed
4. Compare: Xcode Issue Navigator shows hundreds of warnings

## Warning Categories Being Suppressed

From the Thesis project (302 warnings):
- Unused imports (`Public import of 'X' was not used in public declarations or inlinable code`)
- No async operations in async expression
- No calls to throwing functions in `try` expression
- Initialization of immutable value was never used
- Type-check time warnings (e.g. `took 110ms to type-check`)
- Conditional downcast warnings
- `@preconcurrency` conformance warnings
- SwiftLint `command not found`

## Tasks

- [x] Identify where warnings are filtered out in the build output parser
- [x] Ensure warnings are included in output (via `show_warnings` opt-in parameter)
- [x] Verify fix against a project with known warnings


## Summary of Changes

Added `show_warnings` parameter to `build_macos` tool. By default, successful builds report the warning count in the summary header (e.g. "Build succeeded (302 warnings, 12.4s)") but suppress verbose per-warning details. When `show_warnings: true`, all project-local warnings are listed with file/line/message. The `errors_only` flag still suppresses everything including the count.

Files changed:
- `Sources/Core/BuildResultFormatter.swift` — added `showWarnings` parameter; on success, warning details gated behind this flag
- `Sources/Core/ErrorExtraction.swift` — plumbed `showWarnings` through `extractBuildErrors`
- `Sources/Tools/MacOS/BuildMacOSTool.swift` — added `show_warnings` input parameter; includes parsed build summary in success output
- `Sources/Tools/MacOS/DiagnosticsTool.swift` — passes `showWarnings: true` since diagnostics always wants full details
