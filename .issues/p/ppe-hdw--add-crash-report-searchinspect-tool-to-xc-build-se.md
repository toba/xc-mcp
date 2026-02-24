---
# ppe-hdw
title: Add crash report search/inspect tool to xc-build server
status: completed
type: feature
priority: low
tags:
    - xc-build
created_at: 2026-02-22T23:03:20Z
updated_at: 2026-02-22T23:16:02Z
sync:
    github:
        issue_number: "127"
        synced_at: "2026-02-24T18:57:48Z"
---

## Problem

When debugging test host crashes or app crashes, agents need to inspect crash reports in `~/Library/Logs/DiagnosticReports/`. Currently this requires raw Bash (`ls`, `head`, manual JSON parsing of .ips files).

### Observed in

Session 2026-02-22: while implementing crash diagnostics for test host bootstrap failures (issue 7cp-tjt), had to use Bash to `ls ~/Library/Logs/DiagnosticReports/` and `head` an .ips file to understand the format.

### Note

Issue 7cp-tjt added automatic crash report surfacing inside `test_macos` error output, which covers the most common case. This issue is for a standalone tool that lets agents proactively search crash reports outside of a test run — e.g., after a `build_run_macos` app crash, or when investigating historical crashes.

### Expected behavior

A `search_crash_reports` tool that:
1. Searches `~/Library/Logs/DiagnosticReports/` for `.ips` files matching a process name or bundle ID
2. Filters by recency (last N minutes)
3. Returns a structured summary: exception type, signal, termination reason, faulting thread backtrace
4. Reuses `ErrorExtractor.parseCrashReport()` / `formatCrashJSON()` (added in 7cp-tjt)

## Tasks

- [x] Add `SearchCrashReportsTool` to `Sources/Tools/Utility/`
- [x] Accept `process_name`, `bundle_id`, `minutes` (default 5) parameters
- [x] Created `CrashReportParser` in Core (reusable by ErrorExtractor and the tool)
- [x] Register in xc-build server and monolithic server
- [x] Add tests (7 tests in CrashReportParserTests)


## Summary of Changes

New files:
- `Sources/Core/CrashReportParser.swift` — reusable .ips crash report parser with `parse(at:)`, `parseJSON()`, `search()`, and `CrashSummary` type
- `Sources/Tools/Utility/SearchCrashReportsTool.swift` — `search_crash_reports` MCP tool
- `Tests/CrashReportParserTests.swift` — 7 tests

Modified:
- `Sources/Servers/Build/BuildMCPServer.swift` — registered tool
- `Sources/Server/XcodeMCPServer.swift` — registered tool in monolithic server
- `Sources/Core/ServerToolDirectory.swift` — added to xc-build tool list for wrong-server hints
