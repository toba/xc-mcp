---
# qbz-ek1
title: 'build_debug_macos: build succeeds but app never launches; post-build launch/attach stalls'
status: completed
type: bug
priority: high
tags:
    - administrative
created_at: 2026-05-25T05:47:38Z
updated_at: 2026-05-25T05:56:03Z
blocked_by:
    - vh7-pah
sync:
    github:
        issue_number: "331"
        synced_at: "2026-05-25T05:56:50Z"
---

## Symptom

`build_debug_macos` compiles the project successfully but **no app ever launches** — no window appears and no `ThesisApp (debug)` process is running after the call returns/hangs. The build phase works; the launch/attach phase does not.

## Observed this session (Thesis project, scheme `Standard`, Debug)

Two consecutive calls, with the orphaned `lldb-rpc-server` cleared in between:

1. **Call 1** returned:
   ```
   MCP error -32603: Internal error: Build appears stuck (no output for 30 seconds)

   Build succeeded
   ```
   i.e. the build itself succeeded, but the tool's "no output for 30s" watchdog fired (presumably during the launch/attach step after compilation) and returned an error. Immediately after, `pgrep -fl "ThesisApp (debug)"` found **no process** → the app never launched.
2. Cleared a stale `lldb-rpc-server` (`pkill -9 -f lldb-rpc-server`) to rule out `vh7-pah` wedging the attach.
3. **Call 2** hung with no output and was cancelled (`user-cancel`). Still no app window / process.

So: compilation is fine and warm, but the post-build **launch-under-LLDB step stalls** and produces no running app. The "Build appears stuck (no output for 30 seconds)" watchdog message is misleading — the build had already succeeded; it's the launch/attach that stalled.

## Suspected area

- The launch path (Launch Services launch with `DYLD_FRAMEWORK_PATH` + LLDB attach) stalls after a successful build, yielding no process.
- The 30s "no output" watchdog returns an `Internal error` even when the build succeeded, instead of either (a) reporting the app launched, or (b) clearly stating the launch/attach step timed out.
- May share machinery with `vh7-pah` (LLDB attach hang / orphaned `lldb-rpc-server`), but the distinguishing symptom here is **build success with zero app launch**, reproduced even after clearing the orphaned server.

## Suggested investigation / fixes

1. Separate the build watchdog from the launch/attach watchdog; on a post-build stall, report "build succeeded; launch/attach timed out" with the app path, not a generic "build stuck" internal error.
2. Confirm whether the app process is actually spawned (Launch Services) before the attach; if spawn succeeds but attach stalls, surface the PID so callers can use it without the debugger.
3. Add a launch/attach timeout that returns a structured result (built app path + PID if known) instead of hanging.
4. Verify the `DYLD_FRAMEWORK_PATH` launch still works on this OS/Xcode (debug dylib symbol resolution) — a silent launch failure would also present as "no app."

## Impact / workaround

`build_debug_macos` cannot launch the app for runtime verification. Workaround: `build_macos` to confirm compilation (works), then **Build + Run in Xcode** for the actual launch.

## Related

- `vh7-pah` — LLDB attach hang; orphaned `lldb-rpc-server` wedges next launch (this bug reproduces even after clearing that orphan).
- `b1b-k93` (completed) — cold-build slowness; documents `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1`.


## Summary of Changes

Root cause: after `xcodebuild` prints its terminal result (`** BUILD SUCCEEDED **` / `Build succeeded in …`), grandchild daemons it spawned (SwiftPM resolver, build-system services) inherit and hold its stdout/stderr pipes open. `XcodebuildRunner.runProcess`'s stream readers therefore never finish, so the 30s no-output watchdog fired and threw `XcodebuildError.stuckProcess` — aborting `build_debug_macos` with a misleading "Build appears stuck" internal error *even though the build had succeeded*. The launch/attach step was never reached, so no app ever launched.

Changes in `Sources/Core/XcodebuildRunner.swift`:

1. **Recognize a finished build in the no-output watchdog** — when the no-output timeout fires, check the collected output for a terminal marker (`outputShowsBuildFinished`: legacy `** BUILD SUCCEEDED/FAILED **`, `** TEST … **`, `** CLEAN SUCCEEDED **`, and modern `Build succeeded in `/`Build failed after `/`Build complete!`). If found, throw a new internal-only `XcodebuildError.completedPipesHeldOpen(partialOutput:)` instead of `.stuckProcess`.
2. **Recover it into a normal result** — `runProcess` now wraps `Subprocess.run` in do/catch; on `.completedPipesHeldOpen` it returns a normal `XcodebuildResult` with an exit code derived from the output (`exitCode(forFinishedOutput:)` → 0 on success, 65 on failure) rather than propagating an error. `build_debug_macos` then proceeds to the launch/attach step as intended.

The hard overall-timeout watchdog and the genuine `.stuckProcess` path (no terminal marker seen) are unchanged, so a truly hung compile is still reported.

Also fixed the stale `test-debug.sh` harness: it built a non-existent `--product xc-debug`; the focused servers are now dispatched from the single multicall `xc-mcp` binary via argv[0], so the harness builds `xc-mcp` and invokes it through an `xc-debug` symlink.

Tests: new `Tests/XcodebuildCompletionDetectionTests.swift` (6 tests) covering marker detection and exit-code derivation — all pass.

### End-to-end verification

Ran `./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard` against the freshly built server: build succeeded (`** BUILD SUCCEEDED **`) and the app **launched under LLDB, stopped at entry (PID 8872)** — confirming `build_debug_macos` both builds and launches again.
