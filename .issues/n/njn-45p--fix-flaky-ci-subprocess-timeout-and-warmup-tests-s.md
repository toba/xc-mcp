---
# njn-45p
title: 'Fix flaky CI: subprocess-timeout and warmup tests starve on saturated runner'
status: completed
type: bug
priority: normal
created_at: 2026-06-28T22:36:15Z
updated_at: 2026-06-28T22:36:15Z
sync:
    github:
        issue_number: "405"
        synced_at: "2026-06-28T23:06:20Z"
---

Two tests intermittently failed in CI (run 289) under heavy parallel load (1422 tests):

- SubprocessTimeoutGroupKillTests: elapsed 20.18s tripped the 20s wall-clock bound (timeout is 1s; kill+drain was starved ~19s on the cooperative pool).
- SessionManagerWarmupTests 'Warmup runs and reports completed': the .background-priority warmup completed in 0.08s but wasn't observed within the 15s poll budget due to runner starvation.

Both pass locally in seconds; the failures are pure scheduling jitter, not product bugs.

## Summary of Changes
- SubprocessTimeoutGroupKillTests: changed the inner sleep to 600s (effectively unbounded) and raised the wall-clock bound from 20s to 60s, decoupling the 'did not hang' guard from natural command completion so CI starvation can't trip it while a true hang still does.
- SessionManagerWarmupTests: raised the default waitUntilCompleted poll budget from 15s to 60s, fixed the stale 'within 2s' Issue message, and updated comments.
