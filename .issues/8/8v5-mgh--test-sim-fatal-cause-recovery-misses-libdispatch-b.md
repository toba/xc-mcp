---
# 8v5-mgh
title: test_sim fatal-cause recovery misses libdispatch BUG IN CLIENT and abort-class signatures
status: completed
type: feature
priority: high
created_at: 2026-05-28T03:51:18Z
updated_at: 2026-05-28T03:56:15Z
sync:
    github:
        issue_number: "355"
        synced_at: "2026-05-28T03:57:26Z"
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
