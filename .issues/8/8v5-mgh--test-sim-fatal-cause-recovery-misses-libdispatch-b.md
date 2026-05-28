---
# 8v5-mgh
title: test_sim fatal-cause recovery misses libdispatch BUG IN CLIENT and abort-class signatures
status: completed
type: feature
priority: high
created_at: 2026-05-28T03:51:18Z
updated_at: 2026-05-28T04:22:42Z
sync:
    github:
        issue_number: "355"
        synced_at: "2026-05-28T04:26:18Z"
---

While chasing the iOS whole-plan green run in toba/thesis sgp-4wi, the test process aborted with:

  BUG IN CLIENT OF LIBDISPATCH: Assertion failed: Block was expected to execute on queue [com.apple.main-thread (0x1f38cffc0)]

`test_sim` (and `test_macos`) wire `TestCrashDiagnostics.diagnose` into their failure paths and call `fatalLogPredicate(processName:)` against the unified log to recover the actual cause of a "Test crashed with signal trap." Instead the output was:

  Test process crashed but no fatal-error message was recovered. Query the unified log directly:
  show_mac_log with predicate `composedMessage CONTAINS "Fatal error" OR composedMessage CONTAINS "Exception"`.

`fatalLogPredicate` (Sources/Core/TestCrashDiagnostics.swift:79-90) only matches Swift-trap / NSException-shaped strings:

  composedMessage CONTAINS "Fatal error"
  composedMessage CONTAINS "Precondition failed"
  composedMessage CONTAINS "Assertion failed"
  composedMessage CONTAINS "Terminating app due to uncaught exception"
  composedMessage CONTAINS "NSException"

libdispatch / libsystem abort messages don't carry any of those tokens. With ~1500-2000 tests in flight when the abort fires, the test process exits without a Swift-side fatal-error line in the xcresult or the captured stderr, and the user has to drop into `xcrun simctl spawn <UDID> log show …` by hand. `trapSignatures` (line 28-41) for stderr scraping has the same gap.

## Concrete signatures missing

From the iOS sim run + standard libsystem abort surface:

- "BUG IN CLIENT OF LIBDISPATCH" — dispatch_assert_queue / dispatch_assert_queue_not_owner / dispatch_main violations.
- "BUG IN CLIENT OF " — broader (LIBOBJC / Foundation: KVO, NSObject thread-checker, etc.).
- "_dispatch_assert_queue_fail" / "dispatch_assert_queue" — symbolicated traces.
- "Abort trap: 6" / "SIGABRT" / "EXC_CRASH (SIGABRT)" — generic abort.
- "AddressSanitizer" / "ThreadSanitizer" / "ERROR: " — sanitizer trips.
- "Swift runtime failure:" — Swift 6 runtime checks (region violations, Sendable trips).

All appear in the unified log under regular Default/Error events from the test host, not as Fault — the existing predicate's keyword filter is the only thing missing.

## Suggested change

Two array literals in Sources/Core/TestCrashDiagnostics.swift:

- `trapSignatures`: add BUG IN CLIENT / Abort trap / EXC_CRASH / Swift runtime failure / sanitizer strings.
- `fatalLogPredicate`: add `composedMessage CONTAINS \"BUG IN CLIENT\"`, `\"Abort trap\"`, `\"EXC_CRASH\"`, `\"Swift runtime failure\"`, `\"ERROR: AddressSanitizer\"`, `\"ERROR: ThreadSanitizer\"`.

Both arrays are case-sensitive substring matches against distinctive prefixes; false positives unlikely. A regression test exercising a synthetic dispatch_assert_queue / abort()-triggered crash would pin the new coverage.

## Impact

Without this, every test-host abort outside the Swift-trap shape silently drops the cause from `test_sim`/`test_macos` output, and consumers fall back to manual `log show` invocations exactly when they need automation most.

## Source

toba/thesis sgp-4wi: 2026-05-27 whole-plan iOS run mass-cascade where the actual cause was a libdispatch main-queue assertion. Recovering it required `xcrun simctl spawn <UDID> log show --predicate 'process == \"ThesisApp\" AND eventMessage CONTAINS \"BUG IN CLIENT\"'` by hand.



## Summary of Changes

Extended `Sources/Core/TestCrashDiagnostics.swift` to recover crash causes outside the Swift-trap shape:

- `trapSignatures`: added `EXC_CRASH`, `BUG IN CLIENT OF`, `_dispatch_assert_queue_fail`, `dispatch_assert_queue`, `Abort trap: 6`, `SIGABRT`, `Swift runtime failure:`, `ERROR: AddressSanitizer`, `ERROR: ThreadSanitizer`, `ERROR: UndefinedBehaviorSanitizer`.
- `fatalLogPredicate`: added `composedMessage CONTAINS` clauses for `BUG IN CLIENT`, `Abort trap`, `EXC_CRASH`, `Swift runtime failure`, `ERROR: AddressSanitizer`, `ERROR: ThreadSanitizer`.

Added three regression tests in `Tests/TestCrashDiagnosticsTests.swift` covering libdispatch BUG IN CLIENT extraction, abort/runtime/sanitizer stderr extraction, and the expanded predicate clauses. All 15 tests pass.

## Follow-up fix: wire captureCrashLog into TestSimTool / TestDeviceTool

The 1.74.1 brew binary contains the new signatures (`strings /opt/homebrew/Cellar/xc-mcp/1.74.1/bin/xc-simulator | grep "BUG IN CLIENT OF"` matches) — but a fresh `mcp__xc-simulator__test_sim` whole-plan iOS run still returns the *old* fallback verbatim:

  Test process crashed but no fatal-error message was recovered. Query the unified log directly:
  show_mac_log with predicate `composedMessage CONTAINS "Fatal error" OR composedMessage CONTAINS "Exception"`.

…while the unified log clearly carries the killer:

  ThesisApp (debug)[88128] [com.apple.libsystem.libdispatch:]
  BUG IN CLIENT OF LIBDISPATCH: Block was expected to execute on queue [com.apple.main-thread]

Root cause is in `TestSimTool`, not in `TestCrashDiagnostics`:

- `Sources/Core/TestToolHelper.swift:143` only wires the unified-log query when `captureCrashLog: true` is passed by the caller (the parameter defaults to `false`).
- `Sources/Tools/MacOS/TestMacOSTool.swift:121` passes `captureCrashLog: true`.
- `Sources/Tools/Simulator/TestSimTool.swift:83-99` does NOT pass it; `crashLogWindow` stays `nil`, so `diagnose()` only scrapes stderr and the libdispatch/abort lines (which are emitted to the unified log, not stderr) never reach the matcher.

Fixed by passing `captureCrashLog: true` in `Sources/Tools/Simulator/TestSimTool.swift` and `Sources/Tools/Device/TestDeviceTool.swift`, mirroring `TestMacOSTool`. The unified-log query now runs for sim/device test crashes and the expanded predicate (BUG IN CLIENT, Abort trap, EXC_CRASH, Swift runtime failure, sanitizers) can actually fire.

Verification: rerun the toba/thesis sgp-4wi whole-plan iOS test (`mcp__xc-simulator__test_sim`, plan "iOS Tests", skip `CoreTests/ReferenceTests`). With the fix in place, the failure block should append the libdispatch line and a fatal-log section instead of the bare "no fatal-error message was recovered."
