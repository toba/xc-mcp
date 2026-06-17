---
# 2aa-j8p
title: 'Flaky CI: raceTimeout loses post-kill race, no timeout thrown'
status: completed
type: bug
priority: normal
created_at: 2026-06-17T01:40:42Z
updated_at: 2026-06-17T01:44:46Z
sync:
    github:
        issue_number: "390"
        synced_at: "2026-06-17T01:58:39Z"
---

CI run 275 failed on SubprocessTimeoutGroupKillTests/'Timeout reaps a grandchild holding the pipe open': '#expect(throws: ProcessError.self)' saw no error.

Root cause: in ProcessResult.raceTimeout, the timeout task kills the process group then throws. The SIGKILL is what lets the run task finally drain its pipes and return a (signaled) ProcessResult. Both children then race to post completion to the throwing task group; under parallel CI load the run task's result is occasionally observed first, so raceTimeout returns a value instead of throwing the timeout.

Fix: make the timeout sticky via a flag set BEFORE the kill, so any post-kill completion of run is still reported as a timeout — the deterministic winner is the timeout regardless of scheduler ordering.

## Summary of Changes

- `Sources/Core/ProcessResult.swift`: made `raceTimeout` deterministic. The deadline task now raises a sticky `TimeoutFlag` (a small copyable Sendable box wrapping a Mutex, so it can cross the addTask `sending` boundary) *before* killing the process group, and returns a `nil` sentinel instead of throwing. After `group.next()`, the body throws `ProcessError.timeout` whenever the flag is raised — so a post-kill `run` completion can no longer win the race and swallow the timeout.
- `Tests/SessionManagerWarmupTests.swift`: dropped the explicit 5s poll override in 'Repeat setDefaults does not spawn duplicate warmups' so it uses the 15s default budget like its siblings (the 5s override still flaked on saturated runners — runs #264/#267).

Verified: SubprocessTimeoutGroupKillTests + SessionManagerWarmupTests pass; full `swift build --build-tests` succeeds.
