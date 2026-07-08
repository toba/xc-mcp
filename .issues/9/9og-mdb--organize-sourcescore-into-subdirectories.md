---
# 9og-mdb
title: Organize Sources/Core into subdirectories
status: completed
type: task
priority: normal
created_at: 2026-07-08T14:47:29Z
updated_at: 2026-07-08T14:54:43Z
sync:
    github:
        issue_number: "409"
        synced_at: "2026-07-08T14:55:33Z"
---

Group 59 flat Core files into subdirectories by concern; update CLAUDE.md.

## Summary of Changes

Reorganized the flat `Sources/Core/` directory (59 top-level files) into
subdirectories by concern via `git mv` (history preserved). No `Package.swift`
change needed — the `XCMCPCore` target globs `Sources/Core` recursively, so
all files stay in the same module and imports are unaffected.

New layout:

- `Runners/` (8) — subprocess wrappers + ProcessResult
- `BuildOutput/` (10) — build/test/coverage/crash output parsing & formatting
- `ProjectFile/` (7) — pbxproj/scheme/test-plan editing
- `Interaction/` (6) — UI automation helpers
- `Locators/` (6) — path/binary/PID/DerivedData/PIF-cache resolution
- `MCP/` (6) — protocol plumbing + arg extraction + next-step hints
- `Testing/` (4) — test discovery/diagnostics helpers
- `Session/` (4) — session/workflow state + build guard + Xcode state reader
- `AppBundle/` (3) — app-bundle staging & inspection
- `XCStrings/` (10, unchanged)
- 5 cross-cutting singletons kept at root (XCMCPCore, ElapsedFormatting,
  MachineMetadata, BreakpointConditionAdvisor, PackageResolvedParser)

Updated CLAUDE.md's Package Structure tree (was stale at "25 files") and the
two path-specific references (`Sources/Core/Runners/`,
`Sources/Core/MCP/MCPErrorConvertible.swift`).

Build succeeds; full suite passes (1455 tests).
