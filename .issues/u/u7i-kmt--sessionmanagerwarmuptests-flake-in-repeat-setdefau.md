---
# u7i-kmt
title: 'SessionManagerWarmupTests: flake in ''Repeat setDefaults does not spawn duplicate warmups'''
status: completed
type: bug
priority: normal
created_at: 2026-05-05T23:12:38Z
updated_at: 2026-05-05T23:47:06Z
sync:
    github:
        issue_number: "311"
        synced_at: "2026-05-05T23:47:21Z"
---

Test `Repeat setDefaults does not spawn duplicate warmups` failed once on CI (run 211, main) with `await runCount.value == 1` at `SessionManagerWarmupTests.swift:94` — i.e. more than one warmup ran. Run 210 (same code) passed it. Suggests a race in the warmup-dedup logic under CI scheduling pressure rather than a regression.

CI run: https://github.com/toba/xc-mcp/actions/runs/25386556212

## Tasks
- [x] Re-read SessionManager warmup dedup path; confirmed it's a *test* flake, not a production race — `SessionManager` is a `public actor`, so `triggerWarmupIfNeeded` atomically checks `warmupTasks[path]` and assigns it before returning. Three serial `await setDefaults` calls cannot spawn duplicates by construction.
- [x] Production dedup needs no change — already atomic inside the actor.
- [x] Replaced the test's fixed `sleep(500ms)` with a poll-for-`.completed` loop (5s cap) plus a 100ms grace window — same pattern test #1 in the suite already uses.


## Summary of Changes

`SessionManager` is `public actor`, so the dedup path is already correct: `triggerWarmupIfNeeded` checks `warmupTasks[packagePath] == nil` and assigns the new `Task.detached` handle in a single actor-isolated step. Three serial `await manager.setDefaults(...)` calls cannot race the inflight guard.

The flake was in the **test's wait strategy**. The injected runner sleeps 200ms and then awaits `runCount.increment()` (a hop to the `AsyncCounter` actor); the warmup runs at `.background` priority via `Task.detached`. Under heavy GitHub Actions runner load, a `.background` Task can be deferred long enough that the increment hasn't landed within the test's fixed 500ms grace, leaving `runCount == 0` when the assertion fires.

Fix: replaced the fixed sleep with a poll loop that waits up to 5s for `manager.warmupState(for:) == .completed`, then a 100ms grace period to catch any spurious duplicates that would also increment the counter. Same pattern test #1 (`Warmup runs and reports completed for cold cache`) in the same suite already uses.

Local verification: `SessionManagerWarmupTests` passes 7/7 in 0.7s. CI verification pending push.
