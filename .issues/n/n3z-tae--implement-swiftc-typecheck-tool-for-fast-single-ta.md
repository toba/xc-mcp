---
# n3z-tae
title: Implement swiftc -typecheck tool for fast single-target type checking
status: draft
type: feature
priority: normal
created_at: 2026-02-22T01:15:55Z
updated_at: 2026-02-22T01:15:55Z
sync:
    github:
        issue_number: "114"
        synced_at: "2026-02-24T18:57:45Z"
---

## Motivation

The removed `check_build` tool used `xcodebuild -target` which doesn't resolve SPM packages or cross-project references, making it fail on real projects. A `swiftc -typecheck` approach can deliver the original "seconds not minutes" goal.

## Approach

1. Extract compiler flags from `xcodebuild -showBuildSettings -target <name>` (or `-scheme`)
   - `SWIFT_INCLUDE_PATHS`, `FRAMEWORK_SEARCH_PATHS`, `HEADER_SEARCH_PATHS`
   - `OTHER_SWIFT_FLAGS`, `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
   - Module map paths from built dependencies
2. Collect source files for the target (from xcodeproj or build settings)
3. Run `swiftc -typecheck <sources> <flags>` — type-check only, no codegen, no linking
4. Parse diagnostics from swiftc stderr

## Requirements

- Requires dependencies already built (warm derived data) — document this clearly
- Should work with both .xcodeproj targets and SPM targets
- Parse and format swiftc diagnostics similarly to BuildOutputParser

## References

- Removed in commit that deleted `CheckBuildTool.swift` (see git log)
- `swiftc -typecheck` docs: https://github.com/swiftlang/swift/blob/main/docs/Driver.md
