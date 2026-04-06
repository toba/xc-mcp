---
# 7u3-e31
title: Add ReportCrash throttle detection to search_crash_reports
status: completed
type: feature
priority: normal
created_at: 2026-04-06T16:53:15Z
updated_at: 2026-04-06T16:57:00Z
sync:
    github:
        issue_number: "259"
        synced_at: "2026-04-06T16:59:31Z"
---

macOS throttles ReportCrash after ~25 .ips files per process name, silently stopping new report generation. Our tool returns a plain "no crash reports found" with no explanation.

Inspired by skwallace36/Pepper@e43e422.

## Tasks

- [x] Count total reports for process across all time when no recent reports found
- [x] Warn when >= 25 total reports exist but none in time window (throttle likely)
- [x] Suggest cleanup command in warning message
- [x] List process names with reports in time window when no match found
- [x] Add tests for throttle detection


## Summary of Changes

Added `SearchDiagnostics` struct and `searchWithDiagnostics` method to CrashReportParser. When no crash reports match, the tool now:
1. Counts all-time reports for the filtered process to detect ReportCrash throttling (~25 report limit)
2. Warns with a cleanup command (`rm .../*.ips`) when throttling is likely
3. Lists process names that DO have reports in the time window to help identify name mismatches

Added 2 tests for the diagnostics path.
