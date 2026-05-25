---
# 4jz-4xa
title: WaitForProcessExitTests flaky in CI under parallel load
status: completed
type: bug
priority: normal
created_at: 2026-05-25T20:01:04Z
updated_at: 2026-05-25T20:01:37Z
sync:
    github:
        issue_number: "336"
        synced_at: "2026-05-25T20:03:35Z"
---

Three timing-sensitive tests in WaitForProcessExitTests intermittently fail in CI (run 26417163088): 'Returns true when process exits within timeout', 'Detects process killed by SIGKILL mid-wait', and 'Timeout is bounded'.

waitForProcessExit polls with Task.sleep on the Swift cooperative thread pool. When the full 1166-test suite runs in parallel, blocking calls (e.g. process.waitUntilExit()) across other suites starve the pool, delaying the poll loop. The 3s detection budgets and the 'elapsed < 2s' upper bound are too tight to survive that delay.

Fix: give the detection-based tests generous timeouts and loosen the upper-bound timing assertion so they tolerate pool starvation.

## Summary of Changes

Hardened the three timing-sensitive tests in `Tests/WaitForProcessExitTests.swift` against cooperative-thread-pool starvation during the full parallel suite:
- 'Returns true when process exits within timeout': detection timeout 3s → 15s.
- 'Detects process killed by SIGKILL mid-wait': detection timeout 3s → 15s.
- 'Timeout is bounded': upper-bound assertion 2s → 15s (still proves no indefinite hang; lower bound of 250ms unchanged).

No production code changed — the flake was test-side timing, not a bug in waitForProcessExit. Verified with swift_package_test (5 passed).
