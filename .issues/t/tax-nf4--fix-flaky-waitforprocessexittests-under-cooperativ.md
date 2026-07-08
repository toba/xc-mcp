---
# tax-nf4
title: Fix flaky WaitForProcessExitTests under cooperative pool starvation
status: completed
type: bug
priority: normal
created_at: 2026-07-08T18:43:18Z
updated_at: 2026-07-08T18:44:30Z
sync:
    github:
        issue_number: "422"
        synced_at: "2026-07-08T18:46:28Z"
---

waitForProcessExit polls with Task.sleep on the cooperative thread pool. Under a starved pool (full parallel test run) a 100ms sleep overshoots by ~20s, so the loop misses process exits or blows past its wall-clock deadline (CI runs 295-297 failed: elapsed 19.9s vs 15s bound; #expect(exited) false for processes that did exit). Replace the poll loop with a blocking kqueue EVFILT_PROC/NOTE_EXIT wait on a dedicated thread so exit detection and timeout are precise regardless of pool state.

## Summary of Changes

Replaced the `Task.sleep`-based poll loop in `ProcessResult.waitForProcessExit` (`Sources/Core/Runners/ProcessResult.swift`) with a blocking kqueue `EVFILT_PROC`/`NOTE_EXIT` wait dispatched to a dedicated thread via `Thread.detachNewThread` + `withCheckedContinuation`.

- Fast path returns immediately if the pid is already gone (`kill(pid, 0)`).
- ESRCH race (process exits between the fast-path check and kevent registration) is treated as an exit.
- The timeout is enforced by kevent's own `timespec`, so it no longer overshoots under cooperative-pool starvation.

Fixes the 3 flaky `WaitForProcessExitTests` (CI runs 295–297): exit detection is now exact (kernel event, not polling) and the wall-clock timeout is precise regardless of parallel test load. All 5 tests pass in 0.369s (was ~22s and flaky); full `swift build` clean.
