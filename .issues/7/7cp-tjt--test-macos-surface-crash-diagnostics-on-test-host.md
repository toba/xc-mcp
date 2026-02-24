---
# 7cp-tjt
title: 'test_macos: surface crash diagnostics on test host bootstrap failure'
status: completed
type: feature
priority: normal
tags:
    - xc-build
created_at: 2026-02-22T22:54:13Z
updated_at: 2026-02-22T23:00:41Z
sync:
    github:
        issue_number: "100"
        synced_at: "2026-02-24T18:57:43Z"
---

## Problem

When the test host app crashes during bootstrapping (before any tests run), `test_macos` returns only:

```
Early unexpected exit, operation never finished bootstrapping - no restart will be attempted.
(Underlying Error: The test runner crashed while preparing to run tests: ThesisApp (debug) at <external symbol>)
```

No crash log, stack trace, or actionable diagnostic info is surfaced. The agent has no way to determine the cause of the crash.

### Session context

During a Thesis session, applying a `SuiteTrait` + `TestScoping` trait crashed the test runner during bootstrapping. The agent had to resort to bisecting (removing the trait, running individual tests) to isolate the problem. A crash report would have immediately shown the issue.

### Expected behavior

When a test host crashes during bootstrapping, `test_macos` should attempt to surface crash diagnostics:

1. **Check `~/Library/Logs/DiagnosticReports/`** for recent crash reports matching the test host process name or PID
2. **Extract from `.xcresult` bundle** — the result bundle may contain crash info
3. **Capture recent Console logs** — `log show --predicate 'process == "ThesisApp (debug)"' --last 30s` could capture relevant entries
4. **Include partial stderr** — any output before the crash

### Precedent

The existing `detectInfrastructureWarnings()` in `ErrorExtraction.swift` already scans stderr for testmanagerd SIGSEGV/pointer-auth failures (issue u7z-pgk). This is a similar pattern — detecting and surfacing crash info — but for the test host app itself rather than the test infrastructure.

## Tasks

- [x] After detecting "Early unexpected exit" or "operation never finished bootstrapping" in test output, check for crash reports
- [x] Parse crash report for thread backtraces and exception info
- [x] Include crash summary in the tool's error response
- [x] Consider using `log show` as fallback when no crash report is found


## Summary of Changes

Added test host crash diagnostics to `ErrorExtraction.swift`:

- `detectTestHostCrash()` detects bootstrap failure patterns in test output
- `extractCrashedAppName()` parses the app name from xcodebuild error messages
- `findAndParseCrashReport()` searches `~/Library/Logs/DiagnosticReports/` for recent .ips crash reports matching the app name
- `parseCrashReport()` / `formatCrashJSON()` extract exception type, signal, termination reason, and details from .ips JSON
- `fetchRecentLogs()` falls back to `log show` when no crash report is found
- 5 new tests in `XCResultParserTests.swift`
