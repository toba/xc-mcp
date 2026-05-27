---
# ycq-rdc
title: test_sim appears to hang on long cold iOS rebuilds — must be cancelled manually
status: completed
type: bug
priority: normal
created_at: 2026-05-27T19:51:00Z
updated_at: 2026-05-27T19:56:24Z
sync:
    github:
        issue_number: "350"
        synced_at: "2026-05-27T19:57:05Z"
---

## Symptom
`test_sim` (TestSimTool) appeared to hang during a large **cold** iOS-simulator rebuild and had to be cancelled manually from the client — it never returned a result on its own within the time the user was willing to wait.

Context: triggered from the Thesis project after editing a `TestSupport` source file, which forces a downstream rebuild of Core + DOM + TestSupport + test targets for `iphonesimulator`. Invocation:
`test_sim(test_plan: 'iOS Tests', only_testing: ['CoreTests','DOMTests'], timeout: 600, output_timeout: 300)`. A prior `test_sim` run in the same session (before the edit, incremental) completed normally and returned compile errors.

## What's already wired (so this may be partial)
- `TestSimTool.execute` → `TestToolHelper.runAndFormat` passes `timeout: TimeInterval(testParams.timeout ?? 300)` and `outputTimeout` (default `XcodebuildRunner.defaultTestOutputTimeout`, 0 ⇒ disabled) into `runner.test(...)`.
- `ProcessResult.raceTimeout` races the subprocess against the overall `timeout`.

So a genuine run exceeding `timeout` (600s), or exceeding `output_timeout` (300s) of silence, *should* self-terminate. The user observed it not returning, which suggests one of:

## Candidate causes to verify
1. **Overall `timeout` not actually firing for sim test builds** — confirm `raceTimeout` cancels/terminates the build subprocess (and its child `swift-frontend`/`xctest` processes) when the deadline hits, and that the timeout path returns a `CallTool.Result` rather than awaiting `waitUntilExit`.
2. **`outputTimeout` reset by chatty-but-stuck output** — a cold build emits steady progress lines, so the 300s *silence* window may never elapse even though wall-clock far exceeds expectations; the overall `timeout` (600s) becomes the only real backstop. Verify that backstop terminates.
3. **Pipe/buffer backpressure on very large output** — related to the previously-fixed lcu-gfr (waitUntilExit-before-drain deadlock). A full cold iOS build produces a lot of stdout/stderr; confirm draining keeps up and no deadlock is reintroduced when both pipes fill.
4. **Child-process cleanup on timeout/cancel** — after cancel, no build-driver process remained, but simulator daemons + a macOS-target `swift-frontend` *index* job were still running; confirm timeout/cancel terminates the whole build process group, not just the parent.

## Repro
1. From a project where a `TestSupport`/shared framework file was just edited (forces cold downstream rebuild for `iphonesimulator`).
2. `test_sim(test_plan:'iOS Tests', only_testing:['CoreTests','DOMTests'], timeout:600, output_timeout:300)`.
3. Observe whether it returns within ~600s or has to be cancelled.

## Asks
- Add a deterministic test (or manual verification) that the overall `timeout` reliably terminates a long-running sim test build and returns a timeout result.
- Surface periodic progress / a clear timeout message so the caller can distinguish 'slow but alive' from 'hung'.
- Ensure the wall-clock `timeout` backstop is always honored independent of `output_timeout`.

Reported from Thesis fw5-27h / akn-6oq iOS-test bring-up.

## Summary of Changes

Root cause: `test_sim`/`build_sim` run through `XcodebuildRunner.runProcess`, a separate execution path that — unlike `ProcessResult.runSubprocess` — never spawned xcodebuild in its own process group and, on timeout/stuck, only did `execution.send(signal: .terminate)` against the **parent** xcodebuild. xcodebuild ignores parent-only SIGTERM and leaves `swift-frontend` / build-system grandchildren running. Those grandchildren keep the stdout/stderr pipes open, so the stream-reader tasks never see EOF, the watchdog's throw can't propagate out of the Subprocess body, and the call hangs until the client cancels manually. On a cold build the steady stream of progress lines also keeps the `output_timeout` silence window from ever elapsing, leaving the wall-clock `timeout` as the only backstop — and that backstop was the one that hung.

Fixes:
- `XcodebuildRunner.runProcess`: spawn xcodebuild as a process-group leader (`PlatformOptions.processGroupID = 0` + graceful teardown), capture the pgid, and `kill(-pgid, SIGKILL)` the whole group on timeout, stuck-detection, and external cancellation (new `withTaskCancellationHandler`). Killing the group closes the pipes, the readers reach EOF, and the watchdog's timeout result returns promptly.
- `ProcessResult.runSubprocess`: closed the same latent gap. `raceTimeout` now takes an `onTimeout` hook that SIGKILLs the group synchronously before the timeout throw propagates — cancelling the run task alone only triggered Subprocess's SIGTERM teardown of the parent, leaving grandchildren holding the pipes.

Tests (`Tests/SubprocessTimeoutGroupKillTests.swift`):
- Timeout terminates a parent that traps/ignores SIGTERM.
- Timeout reaps a grandchild holding the pipe open (the discriminating hang scenario).
- Fast command still completes normally under a generous timeout.

All pass; `XcodebuildCompletionDetectionTests` still green; full build clean.
