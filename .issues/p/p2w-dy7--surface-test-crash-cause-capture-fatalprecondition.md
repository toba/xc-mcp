---
# p2w-dy7
title: 'Surface test-crash cause: capture fatal/precondition message + backtrace from test host'
status: completed
type: feature
priority: normal
created_at: 2026-05-28T00:14:00Z
updated_at: 2026-05-28T00:20:38Z
sync:
    github:
        issue_number: "351"
        synced_at: "2026-05-28T00:23:24Z"
---

When a test run crashes (signal trap / SIGTRAP / NSException), `test_macos` reports only "Test crashed with signal trap." with no message or backtrace. Diagnosing the cause currently requires manually querying the unified log (`log show --predicate 'composedMessage CONTAINS "Fatal error"'`) — the only reliable channel because (a) the app-hosted test process is sandboxed so the test cannot write debug files, (b) the OS dedups crash reports by signature so no fresh .ips is written for a repeated signature, and (c) Swift traps print to the test host stderr which the current MCP summary discards.

## Real case (cost ~half a day in the Thesis project)
A DOM move operation crashed every move test with a bare 'signal trap'. The actual causes were only found via `log show`:
- `DOM/Document+changes.swift:119: Fatal error: Dropped 1 text element change(s); text view may be stale` (an async `assertionFailure` on a detached Task — which can even crash a sibling parallel test).
- `NSRangeException: NSMutableRLEArray insertObject:range:: Out of bounds` with a full ObjC backtrace.

## Proposed
On a test crash, automatically capture and include in the failure result:
1. The test host process stderr (Swift 'Fatal error: …' / 'Precondition failed: …' lines).
2. The unified-log fatal line, e.g. `log show --last <window> --predicate 'process == "<TestHost>" AND (composedMessage CONTAINS "Fatal error" OR composedMessage CONTAINS "Exception")'`, scoped to the run window.
3. Any ReportCrash backtrace if a .ips was written.

Surfacing just (1)/(2) inline with the failed test would turn a half-day hunt into seconds.

## Notes
- `show_mac_log` already works as the manual workaround and should be documented as the go-to for test-host traps.
- Scope the log query to the run start/end timestamps to avoid stale matches.


## Summary of Changes

- Added `Sources/Core/TestCrashDiagnostics.swift`: detects test-process crash signatures (signal trap, restart-after-crash, uncaught exception), scrapes Swift trap / ObjC exception lines from the captured test-host stderr, and queries the unified log (`log show`) scoped to the test run's wall-clock window for fatal/exception lines.
- `ErrorExtractor.formatTestToolResult` now appends a `Crash diagnosis` section when a failed run is a process crash. When no cause is recovered it points the user at `show_mac_log` as the manual fallback.
- `TestToolHelper.runAndFormat` captures the run start/end wall-clock window and forwards it via a new `captureCrashLog` flag.
- `test_macos` opts in (`captureCrashLog: true`) and documents the auto-capture in its tool description. `test_sim`/`test_device` are unaffected (unified-log query is macOS-specific; stderr trap scraping would also apply but is gated behind the macOS opt-in for now).
- Added `Tests/TestCrashDiagnosticsTests.swift` (12 tests, all passing).
