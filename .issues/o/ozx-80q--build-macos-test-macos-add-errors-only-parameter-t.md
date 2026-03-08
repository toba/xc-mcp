---
# ozx-80q
title: 'build_macos / test_macos: add errors_only parameter to filter warnings from output'
status: completed
type: feature
priority: high
created_at: 2026-03-08T17:51:10Z
updated_at: 2026-03-08T17:57:32Z
sync:
    github:
        issue_number: "195"
        synced_at: "2026-03-08T17:58:44Z"
---

## Problem

When extracting a Swift module, iterating on build errors requires many build cycles. Each `build_macos` call returns the full error + warning output, which is frequently 30k+ characters. The warnings (SwiftLint TODO violations, trailing closure, deployment target, etc.) vastly outnumber the actual compiler errors, and the output gets truncated before showing all errors.

This wastes context window tokens and makes it harder for the agent to parse what actually needs fixing.

## Proposed Solution

Add an \`errors_only\` boolean parameter (default \`false\`) to \`build_macos\` and \`test_macos\` that filters the output to only include:
- Compiler errors (not warnings)
- Linker errors
- Build failure summary

Alternatively, a \`max_warnings\` integer parameter that caps warning output (e.g. \`max_warnings: 0\` for errors only, \`max_warnings: 5\` for a sample).

## Context

During a module extraction session (moving Editor from App to Components/Editor), 4 build cycles were needed. Each returned ~170 warnings alongside 10-40 real errors. The warnings were identical across builds and provided no diagnostic value.

## Summary of Changes

Added `errors_only` boolean parameter (default `false`) to `build_macos` and `test_macos` tools. When set to `true`, all warnings are suppressed from the output — only compiler errors, linker errors, and the build/test summary are shown.

### Files changed

- `Sources/Core/BuildResultFormatter.swift` — `formatBuildResult` and `formatTestResult` accept `errorsOnly` param; warnings section skipped when true
- `Sources/Core/ErrorExtraction.swift` — `checkBuildSuccess`, `extractBuildErrors`, `extractTestResults`, and `formatTestToolResult` thread `errorsOnly` through
- `Sources/Tools/MacOS/BuildMacOSTool.swift` — added `errors_only` schema property; passes to `checkBuildSuccess`
- `Sources/Tools/MacOS/TestMacOSTool.swift` — added `errors_only` schema property; passes to `formatTestToolResult`
