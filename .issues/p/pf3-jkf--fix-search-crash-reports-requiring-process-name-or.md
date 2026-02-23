---
# pf3-jkf
title: Fix search_crash_reports requiring process_name or bundle_id
status: completed
type: bug
priority: normal
created_at: 2026-02-23T00:12:59Z
updated_at: 2026-02-23T00:13:48Z
---

The `search_crash_reports` tool schema declares no required parameters, but the `execute` method throws `MCPError.invalidParams` when neither `process_name` nor `bundle_id` is provided. The underlying `CrashReportParser.search()` already handles both being nil (returns all recent reports), so the guard is unnecessarily restrictive.

## Steps
- [x] Identify the bug in `SearchCrashReportsTool.swift`
- [x] Remove the unnecessary guard that requires at least one filter parameter
- [x] Verify the fix builds

## Summary of Changes

Removed the guard in `SearchCrashReportsTool.execute()` that threw `MCPError.invalidParams` when neither `process_name` nor `bundle_id` was provided. The underlying `CrashReportParser.search()` already handles both being nil by returning all recent crash reports, which is the correct behavior when no filter is specified. This aligns the runtime behavior with the tool schema (which declares no required parameters).
